import Foundation
import Observation

/// Size of the in-memory ring buffer. Older items are evicted to disk-only.
public let WorkstreamDefaultRingCapacity = 2_000

/// Main-actor `@Observable` store that holds the Feed state.
///
/// One instance per cmux process. All windows observe it through the
/// SwiftUI environment; mutations happen on the main actor, which matches
/// the store's observation boundary and keeps SwiftUI view updates
/// deterministic.
///
/// Reply-id correlation is owned here so blocking hooks that wait on a
/// socket response (see plan §3a) get their decision routed back through
/// the same store that issued the pending item.
@MainActor
@Observable
public final class WorkstreamStore {
    public private(set) var items: [WorkstreamItem] = []

    public var pending: [WorkstreamItem] {
        items.filter { $0.status.isPending }
    }

    public var actionable: [WorkstreamItem] {
        items.filter { $0.kind.isActionable }
    }

    private let transport: any WorkstreamTransport
    private let persistence: WorkstreamPersistence?
    private let ringCapacity: Int
    private let clock: @Sendable () -> Date

    /// Maps a wire-frame `_opencode_request_id` (or agent request id) to
    /// the generated `WorkstreamItem.id`. Populated on ingest, consulted
    /// when a reply action arrives so we know which item to mark resolved.
    private var requestIdToItemId: [String: UUID] = [:]

    /// Reverse map used when a socket reply arrives with the item id; we
    /// need the original wire request id to route the reply back to the
    /// correct blocking hook.
    private var itemIdToRequestId: [UUID: String] = [:]

    public init(
        transport: any WorkstreamTransport = NullWorkstreamTransport(),
        persistence: WorkstreamPersistence? = nil,
        ringCapacity: Int = WorkstreamDefaultRingCapacity,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.transport = transport
        self.persistence = persistence
        self.ringCapacity = ringCapacity
        self.clock = clock
    }

    // MARK: - Lifecycle

    /// Replays recent items from disk, then connects the transport.
    public func start() async {
        if let persistence {
            if let recent = try? await persistence.loadRecent(limit: ringCapacity) {
                items = recent
                rebuildRequestIdIndex()
            }
        }
        do {
            try await transport.subscribe { [weak self] event in
                guard let self else { return }
                Task { @MainActor in
                    self.ingest(event)
                }
            }
        } catch {
            // Transport failures are non-fatal; the store stays usable for
            // locally-injected items and tests.
        }
    }

    // MARK: - Ingest

    /// Applies an inbound wire frame. Creates or updates a
    /// `WorkstreamItem`, enforces the ring-buffer cap, and appends to
    /// the JSONL log.
    public func ingest(_ event: WorkstreamEvent) {
        let item = makeItem(from: event)
        insert(item)
        if let requestId = event.requestId {
            requestIdToItemId[requestId] = item.id
            itemIdToRequestId[item.id] = requestId
        }
        if let persistence {
            Task { [persistence, item] in
                try? await persistence.append(item)
            }
        }
    }

    // MARK: - Actions

    /// Sends a user-initiated action through the transport and marks the
    /// corresponding item resolved on success.
    public func send(_ action: WorkstreamAction) async throws {
        try await transport.send(action)
        applyResolution(for: action)
    }

    /// Marks the local item resolved without sending. Used when the reply
    /// channel is being driven by another layer (e.g. an inbound socket
    /// resolution event).
    public func markResolved(_ itemId: UUID, decision: WorkstreamDecision) {
        guard let idx = items.firstIndex(where: { $0.id == itemId }) else { return }
        items[idx].status = .resolved(decision, at: clock())
        items[idx].updatedAt = clock()
    }

    /// Marks every still-pending item created before `threshold` as
    /// expired. Call periodically to clean stale items.
    public func expirePending(olderThan threshold: TimeInterval) {
        let now = clock()
        for idx in items.indices {
            guard items[idx].status.isPending else { continue }
            if now.timeIntervalSince(items[idx].createdAt) > threshold {
                items[idx].status = .expired(at: now)
                items[idx].updatedAt = now
            }
        }
    }

    // MARK: - Private helpers

    private func insert(_ item: WorkstreamItem) {
        items.append(item)
        if items.count > ringCapacity {
            let overflow = items.count - ringCapacity
            let dropped = items.prefix(overflow)
            for d in dropped {
                if let rid = itemIdToRequestId.removeValue(forKey: d.id) {
                    requestIdToItemId.removeValue(forKey: rid)
                }
            }
            items.removeFirst(overflow)
        }
    }

    private func applyResolution(for action: WorkstreamAction) {
        switch action {
        case .approvePermission(let itemId, let mode):
            markResolved(itemId, decision: .permission(mode))
        case .replyQuestion(let itemId, let selections):
            markResolved(itemId, decision: .question(selections: selections))
        case .approveExitPlan(let itemId, let mode):
            markResolved(itemId, decision: .exitPlan(mode))
        case .jumpToSession:
            // Jump is a navigation action; the item (if any) is unchanged.
            break
        }
    }

    private func rebuildRequestIdIndex() {
        requestIdToItemId.removeAll(keepingCapacity: true)
        itemIdToRequestId.removeAll(keepingCapacity: true)
        for item in items {
            if case .permissionRequest(let rid, _, _, _) = item.payload {
                requestIdToItemId[rid] = item.id
                itemIdToRequestId[item.id] = rid
            } else if case .exitPlan(let rid, _, _) = item.payload {
                requestIdToItemId[rid] = item.id
                itemIdToRequestId[item.id] = rid
            } else if case .question(let rid, _, _, _) = item.payload {
                requestIdToItemId[rid] = item.id
                itemIdToRequestId[item.id] = rid
            }
        }
    }

    private func makeItem(from event: WorkstreamEvent) -> WorkstreamItem {
        let source = WorkstreamSource(wireName: event.source) ?? .claude
        let (kind, payload) = decode(event: event, source: source)
        let status: WorkstreamStatus = kind.isActionable ? .pending : .telemetry
        return WorkstreamItem(
            workstreamId: event.sessionId,
            source: source,
            kind: kind,
            createdAt: event.receivedAt,
            updatedAt: event.receivedAt,
            cwd: event.cwd,
            title: defaultTitle(for: event),
            status: status,
            payload: payload
        )
    }

    private func decode(
        event: WorkstreamEvent,
        source: WorkstreamSource
    ) -> (WorkstreamKind, WorkstreamPayload) {
        let toolInput = event.toolInputJSON ?? "{}"
        switch event.hookEventName {
        case .permissionRequest:
            return (
                .permissionRequest,
                .permissionRequest(
                    requestId: event.requestId ?? event.sessionId,
                    toolName: event.toolName ?? "unknown",
                    toolInputJSON: toolInput,
                    pattern: nil
                )
            )
        case .askUserQuestion:
            return (
                .question,
                .question(
                    requestId: event.requestId ?? event.sessionId,
                    prompt: "",
                    options: [],
                    multiSelect: false
                )
            )
        case .exitPlanMode:
            return (
                .exitPlan,
                .exitPlan(
                    requestId: event.requestId ?? event.sessionId,
                    plan: toolInput,
                    defaultMode: .manual
                )
            )
        case .preToolUse:
            return (.toolUse, .toolUse(toolName: event.toolName ?? "", toolInputJSON: toolInput))
        case .postToolUse:
            return (
                .toolResult,
                .toolResult(toolName: event.toolName ?? "", resultJSON: toolInput, isError: false)
            )
        case .userPromptSubmit:
            return (.userPrompt, .userPrompt(text: ""))
        case .sessionStart:
            return (.sessionStart, .sessionStart)
        case .sessionEnd:
            return (.sessionEnd, .sessionEnd)
        case .stop, .subagentStop:
            return (.stop, .stop(reason: nil))
        case .todoWrite:
            return (.todos, .todos([]))
        case .notification:
            return (.toolResult, .toolResult(toolName: "notification", resultJSON: toolInput, isError: false))
        }
    }

    private func defaultTitle(for event: WorkstreamEvent) -> String? {
        if let tool = event.toolName, !tool.isEmpty {
            return tool
        }
        return nil
    }
}
