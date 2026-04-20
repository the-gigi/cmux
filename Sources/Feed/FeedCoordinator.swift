import CMUXWorkstream
import Foundation

/// App-level coordinator that owns the shared `WorkstreamStore` and
/// mediates between the socket thread (which processes `feed.*` V2
/// commands) and the main-actor store.
///
/// Blocking hook semantics: a hook calls `feed.push` with a `request_id`
/// and `wait_timeout_seconds`. The coordinator creates the `WorkstreamItem`
/// on the store and parks the socket worker on a `DispatchSemaphore` until
/// the user resolves the item via `feed.*.reply` (or the timeout elapses).
/// Hooks then receive the decision inline in the `feed.push` response.
final class FeedCoordinator: @unchecked Sendable {
    static let shared = FeedCoordinator()

    // The store runs on the main actor. The coordinator is not isolated,
    // so it hops to main explicitly when touching the store.
    @MainActor private(set) var store: WorkstreamStore!

    /// Pending blocking-hook waiters keyed by request id. The waiter owns
    /// a semaphore plus a slot for the resolved decision; the reply
    /// handler signals the semaphore after filling the slot.
    private let waiterLock = NSLock()
    private var waiters: [String: PendingWaiter] = [:]

    private init() {}

    /// Must be called once at app launch to install the store.
    @MainActor
    func install(store: WorkstreamStore) {
        self.store = store
    }

    /// Ingests a wire-frame event and, when `waitTimeout` > 0, blocks the
    /// current (non-main) thread until the item is resolved or the
    /// timeout elapses.
    func ingestBlocking(
        event: WorkstreamEvent,
        waitTimeout: TimeInterval
    ) -> IngestBlockingResult {
        let semaphore = DispatchSemaphore(value: 0)
        let waiter = PendingWaiter(semaphore: semaphore)

        // Register the waiter before the store sees the event so a very
        // fast reply can't slip through.
        if let requestId = event.requestId, waitTimeout > 0 {
            waiterLock.lock()
            waiters[requestId] = waiter
            waiterLock.unlock()
        }

        // Hop to main to actually insert the item.
        let itemIdSlot = UnsafeItemIdSlot()
        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                FeedCoordinator.shared.store.ingest(event)
                itemIdSlot.value = FeedCoordinator.shared.store.items.last?.id
            }
        }

        guard let requestId = event.requestId, waitTimeout > 0 else {
            return .acknowledged(itemId: itemIdSlot.value)
        }

        let deadline: DispatchTime = .now() + waitTimeout
        let waitResult = semaphore.wait(timeout: deadline)

        waiterLock.lock()
        let w = waiters.removeValue(forKey: requestId)
        waiterLock.unlock()

        switch waitResult {
        case .success:
            if let decision = w?.decision {
                return .resolved(itemId: itemIdSlot.value, decision: decision)
            }
            return .timedOut(itemId: itemIdSlot.value)
        case .timedOut:
            return .timedOut(itemId: itemIdSlot.value)
        }
    }

    /// Called by the `feed.*.reply` handlers. Marks the corresponding
    /// item resolved on the main-actor store and wakes any waiter.
    func deliverReply(requestId: String, decision: WorkstreamDecision) {
        // Resolve the store side first.
        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                let store = FeedCoordinator.shared.store
                guard let store else { return }
                // Find the item matching this request id by scanning the
                // payload. In practice the store's own request-id index
                // handles this, but `markResolved` takes an item id so we
                // re-derive it here.
                if let itemId = Self.findItemId(for: requestId, in: store.items) {
                    store.markResolved(itemId, decision: decision)
                }
            }
        }

        waiterLock.lock()
        if let waiter = waiters[requestId] {
            waiter.decision = decision
            waiter.semaphore.signal()
        }
        waiterLock.unlock()
    }

    private static func findItemId(
        for requestId: String,
        in items: [WorkstreamItem]
    ) -> UUID? {
        for item in items.reversed() {
            switch item.payload {
            case .permissionRequest(let rid, _, _, _) where rid == requestId:
                return item.id
            case .exitPlan(let rid, _, _) where rid == requestId:
                return item.id
            case .question(let rid, _, _, _) where rid == requestId:
                return item.id
            default:
                continue
            }
        }
        return nil
    }

    enum IngestBlockingResult {
        case acknowledged(itemId: UUID?)
        case resolved(itemId: UUID?, decision: WorkstreamDecision)
        case timedOut(itemId: UUID?)
    }
}

private final class PendingWaiter: @unchecked Sendable {
    let semaphore: DispatchSemaphore
    var decision: WorkstreamDecision?

    init(semaphore: DispatchSemaphore) {
        self.semaphore = semaphore
    }
}

/// Tiny box so the `DispatchQueue.main.sync` closure can mutate an
/// `UUID?` without a capture warning.
private final class UnsafeItemIdSlot: @unchecked Sendable {
    var value: UUID?
}

private final class SnapshotSlot: @unchecked Sendable {
    var value: [WorkstreamItem] = []
}

// MARK: - Socket-layer helpers

extension FeedCoordinator {
    /// Thread-safe snapshot of the store's items; hops to main to read
    /// the observable state.
    func snapshot(pendingOnly: Bool) -> [WorkstreamItem] {
        let slot = SnapshotSlot()
        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                guard let store = FeedCoordinator.shared.store else { return }
                slot.value = pendingOnly ? store.pending : store.items
            }
        }
        return slot.value
    }

    /// Stub that the UI PR replaces with a real resolution against
    /// `SessionIndexStore` + `workspace.select` / `surface.focus`.
    func resolvePossibleSurface(for workstreamId: String) -> Bool {
        _ = workstreamId
        return false
    }
}

/// JSON-shape helpers used by the V2 `feed.*` socket handlers.
enum FeedSocketEncoding {
    static func payload(for result: FeedCoordinator.IngestBlockingResult) -> [String: Any] {
        switch result {
        case .acknowledged(let itemId):
            var dict: [String: Any] = ["status": "acknowledged"]
            if let itemId { dict["item_id"] = itemId.uuidString }
            return dict
        case .resolved(let itemId, let decision):
            var dict: [String: Any] = [
                "status": "resolved",
                "decision": decisionDict(decision)
            ]
            if let itemId { dict["item_id"] = itemId.uuidString }
            return dict
        case .timedOut(let itemId):
            var dict: [String: Any] = ["status": "timed_out"]
            if let itemId { dict["item_id"] = itemId.uuidString }
            return dict
        }
    }

    static func decisionDict(_ decision: WorkstreamDecision) -> [String: Any] {
        switch decision {
        case .permission(let mode):
            return ["kind": "permission", "mode": mode.rawValue]
        case .exitPlan(let mode):
            return ["kind": "exit_plan", "mode": mode.rawValue]
        case .question(let selections):
            return ["kind": "question", "selections": selections]
        }
    }

    static func itemDict(_ item: WorkstreamItem) -> [String: Any] {
        let isoFormatter = ISO8601DateFormatter()
        var dict: [String: Any] = [
            "id": item.id.uuidString,
            "workstream_id": item.workstreamId,
            "source": item.source.rawValue,
            "kind": item.kind.rawValue,
            "created_at": isoFormatter.string(from: item.createdAt),
            "updated_at": isoFormatter.string(from: item.updatedAt),
        ]
        if let cwd = item.cwd { dict["cwd"] = cwd }
        if let title = item.title { dict["title"] = title }
        switch item.status {
        case .pending:
            dict["status"] = "pending"
        case .resolved(let decision, let at):
            dict["status"] = "resolved"
            dict["decision"] = decisionDict(decision)
            dict["resolved_at"] = isoFormatter.string(from: at)
        case .expired(let at):
            dict["status"] = "expired"
            dict["resolved_at"] = isoFormatter.string(from: at)
        case .telemetry:
            dict["status"] = "telemetry"
        }
        return dict
    }
}
