import CMUXWorkstream
import SwiftUI

/// Right-sidebar Feed view. Shows actionable items (permission /
/// exit-plan / question) at the top with inline decision buttons, and
/// optionally the full activity stream when the user flips the
/// Actionable / All segment.
///
/// Follows the CLAUDE.md snapshot-boundary rule: rows receive immutable
/// value snapshots and closure action bundles only. The store is read
/// here in the outer panel body — never inside row views.
struct FeedPanelView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case actionable
        case all
        var id: String { rawValue }
        var label: String {
            switch self {
            case .actionable:
                return String(localized: "feed.filter.actionable", defaultValue: "Actionable")
            case .all:
                return String(localized: "feed.filter.all", defaultValue: "All")
            }
        }
    }

    @State private var filter: Filter = .actionable

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            FeedListView(
                filter: filter,
                store: FeedCoordinator.shared.store
            )
        }
    }

    private var filterBar: some View {
        Picker("", selection: $filter) {
            ForEach(Filter.allCases) { f in
                Text(f.label).tag(f)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

/// Inner list view. Isolated so the outer panel's `@State` changes don't
/// invalidate rows unnecessarily.
private struct FeedListView: View {
    let filter: FeedPanelView.Filter
    let store: WorkstreamStore?

    var body: some View {
        if let store {
            // `@Observable` store: reading computed props in the body
            // registers a dependency automatically.
            let items = snapshot(from: store)
            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(items, id: \.id) { item in
                            FeedItemRow(
                                snapshot: FeedItemSnapshot(item: item),
                                actions: FeedRowActions.bound()
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
        } else {
            emptyState
        }
    }

    private func snapshot(from store: WorkstreamStore) -> [WorkstreamItem] {
        let base: [WorkstreamItem]
        switch filter {
        case .actionable:
            base = store.actionable
        case .all:
            base = store.items
        }
        // Newest first. Pending items always float above resolved so the
        // user's attention isn't buried when they scroll.
        return base.sorted { a, b in
            if a.status.isPending != b.status.isPending {
                return a.status.isPending
            }
            return a.createdAt > b.createdAt
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text(
                filter == .actionable
                    ? String(localized: "feed.empty.actionable",
                             defaultValue: "No pending decisions.")
                    : String(localized: "feed.empty.all",
                             defaultValue: "No feed activity yet.")
            )
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Row snapshot + actions (respects snapshot-boundary rule)

/// Immutable snapshot of a `WorkstreamItem` handed to row views so rows
/// never hold a reference to the store.
struct FeedItemSnapshot: Equatable {
    let id: UUID
    let source: WorkstreamSource
    let kind: WorkstreamKind
    let title: String?
    let cwd: String?
    let createdAt: Date
    let status: WorkstreamStatus
    let payload: WorkstreamPayload

    init(item: WorkstreamItem) {
        self.id = item.id
        self.source = item.source
        self.kind = item.kind
        self.title = item.title
        self.cwd = item.cwd
        self.createdAt = item.createdAt
        self.status = item.status
        self.payload = item.payload
    }
}

/// Closure bundle; binds to `FeedCoordinator` by default, can be
/// overridden in tests.
struct FeedRowActions {
    let approvePermission: (UUID, WorkstreamPermissionMode) -> Void
    let replyQuestion: (UUID, [String]) -> Void
    let approveExitPlan: (UUID, WorkstreamExitPlanMode) -> Void
    let jump: (String) -> Void

    static func bound() -> FeedRowActions {
        FeedRowActions(
            approvePermission: { itemId, mode in
                Task { @MainActor in
                    FeedCoordinator.shared.deliverReply(
                        requestId: Self.requestId(for: itemId) ?? itemId.uuidString,
                        decision: .permission(mode)
                    )
                }
            },
            replyQuestion: { itemId, selections in
                Task { @MainActor in
                    FeedCoordinator.shared.deliverReply(
                        requestId: Self.requestId(for: itemId) ?? itemId.uuidString,
                        decision: .question(selections: selections)
                    )
                }
            },
            approveExitPlan: { itemId, mode in
                Task { @MainActor in
                    FeedCoordinator.shared.deliverReply(
                        requestId: Self.requestId(for: itemId) ?? itemId.uuidString,
                        decision: .exitPlan(mode)
                    )
                }
            },
            jump: { workstreamId in
                // TODO: route through workspace.select / surface.focus
                _ = workstreamId
            }
        )
    }

    @MainActor
    private static func requestId(for itemId: UUID) -> String? {
        guard let store = FeedCoordinator.shared.store else { return nil }
        return store.items.first(where: { $0.id == itemId }).flatMap { item in
            switch item.payload {
            case .permissionRequest(let rid, _, _, _): return rid
            case .exitPlan(let rid, _, _): return rid
            case .question(let rid, _, _, _): return rid
            default: return nil
            }
        }
    }
}

// MARK: - Row view

private struct FeedItemRow: View {
    let snapshot: FeedItemSnapshot
    let actions: FeedRowActions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            switch snapshot.payload {
            case .permissionRequest(_, let toolName, let toolInputJSON, _):
                PermissionRow(
                    toolName: toolName,
                    toolInputJSON: toolInputJSON,
                    status: snapshot.status,
                    onApprove: { mode in actions.approvePermission(snapshot.id, mode) }
                )
            case .exitPlan(_, let plan, _):
                ExitPlanRow(
                    plan: plan,
                    status: snapshot.status,
                    onApprove: { mode in actions.approveExitPlan(snapshot.id, mode) }
                )
            case .question(_, let prompt, let options, let multiSelect):
                QuestionRow(
                    prompt: prompt,
                    options: options,
                    multiSelect: multiSelect,
                    status: snapshot.status,
                    onReply: { selections in actions.replyQuestion(snapshot.id, selections) }
                )
            default:
                TelemetryRow(snapshot: snapshot)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: snapshot.kind.symbolName)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(snapshot.source.rawValue.capitalized)
                .font(.system(size: 11, weight: .medium))
            if let title = snapshot.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            statusBadge
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch snapshot.status {
        case .pending:
            Text(String(localized: "feed.status.pending", defaultValue: "Pending"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.orange)
        case .resolved(let decision, _):
            Text(decisionBadgeLabel(decision))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.green)
        case .expired:
            Text(String(localized: "feed.status.expired", defaultValue: "Expired"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        case .telemetry:
            EmptyView()
        }
    }

    private func decisionBadgeLabel(_ decision: WorkstreamDecision) -> String {
        switch decision {
        case .permission(let m):
            return "\(String(localized: "feed.badge.allowed", defaultValue: "Allowed")): \(m.rawValue)"
        case .exitPlan(let m):
            return m.rawValue
        case .question:
            return String(localized: "feed.badge.answered", defaultValue: "Answered")
        }
    }
}

// MARK: - Per-kind rows

private struct PermissionRow: View {
    let toolName: String
    let toolInputJSON: String
    let status: WorkstreamStatus
    let onApprove: (WorkstreamPermissionMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(toolName)
                .font(.system(size: 12, weight: .semibold))
            Text(toolInputJSON)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(3)
            if status.isPending {
                HStack(spacing: 4) {
                    feedButton(String(localized: "feed.permission.once", defaultValue: "Once")) { onApprove(.once) }
                    feedButton(String(localized: "feed.permission.always", defaultValue: "Always")) { onApprove(.always) }
                    feedButton(String(localized: "feed.permission.all", defaultValue: "All")) { onApprove(.all) }
                    feedButton(String(localized: "feed.permission.bypass", defaultValue: "Bypass")) { onApprove(.bypass) }
                    feedButton(String(localized: "feed.permission.deny", defaultValue: "Deny"), isDestructive: true) { onApprove(.deny) }
                }
            }
        }
    }
}

private struct ExitPlanRow: View {
    let plan: String
    let status: WorkstreamStatus
    let onApprove: (WorkstreamExitPlanMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(plan)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(6)
            if status.isPending {
                HStack(spacing: 4) {
                    feedButton(String(localized: "feed.exitplan.bypass", defaultValue: "Bypass")) { onApprove(.bypassPermissions) }
                    feedButton(String(localized: "feed.exitplan.autoaccept", defaultValue: "Auto-accept")) { onApprove(.autoAccept) }
                    feedButton(String(localized: "feed.exitplan.manual", defaultValue: "Manual")) { onApprove(.manual) }
                    feedButton(String(localized: "feed.exitplan.deny", defaultValue: "Deny"), isDestructive: true) { onApprove(.deny) }
                }
            }
        }
    }
}

private struct QuestionRow: View {
    let prompt: String
    let options: [WorkstreamQuestionOption]
    let multiSelect: Bool
    let status: WorkstreamStatus
    let onReply: ([String]) -> Void

    @State private var selectedIds: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !prompt.isEmpty {
                Text(prompt)
                    .font(.system(size: 11))
            }
            if options.isEmpty {
                Text(String(localized: "feed.question.noOptions", defaultValue: "Agent provided no options"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(options, id: \.id) { option in
                    Button {
                        if multiSelect {
                            if selectedIds.contains(option.id) {
                                selectedIds.remove(option.id)
                            } else {
                                selectedIds.insert(option.id)
                            }
                        } else {
                            selectedIds = [option.id]
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: selectedIds.contains(option.id)
                                ? (multiSelect ? "checkmark.square.fill" : "largecircle.fill.circle")
                                : (multiSelect ? "square" : "circle"))
                            Text(option.label).font(.system(size: 11))
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if status.isPending {
                HStack {
                    Spacer()
                    feedButton(String(localized: "feed.question.submit", defaultValue: "Submit")) {
                        onReply(Array(selectedIds))
                    }
                    .disabled(selectedIds.isEmpty)
                }
            }
        }
    }
}

private struct TelemetryRow: View {
    let snapshot: FeedItemSnapshot

    var body: some View {
        Text(summary)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(4)
    }

    private var summary: String {
        switch snapshot.payload {
        case .toolUse(let name, let json):
            return "\(name) \(json)"
        case .toolResult(let name, let json, let err):
            return "\(name) \(err ? "error" : "ok") \(json)"
        case .userPrompt(let text), .assistantMessage(let text):
            return text
        case .sessionStart: return "session start"
        case .sessionEnd: return "session end"
        case .stop(let reason): return "stop \(reason ?? "")"
        case .todos(let todos):
            let done = todos.filter { $0.state == .completed }.count
            let inProgress = todos.filter { $0.state == .inProgress }.count
            let pending = todos.filter { $0.state == .pending }.count
            return "todos: \(done) done, \(inProgress) in progress, \(pending) pending"
        default:
            return snapshot.kind.rawValue
        }
    }
}

// MARK: - Small helpers

@ViewBuilder
private func feedButton(
    _ label: String,
    isDestructive: Bool = false,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
    }
    .buttonStyle(.borderless)
    .foregroundStyle(isDestructive ? .red : .primary)
    .background(
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.primary.opacity(0.06))
    )
}

private extension WorkstreamKind {
    var symbolName: String {
        switch self {
        case .permissionRequest: return "lock.shield"
        case .exitPlan: return "list.bullet.rectangle"
        case .question: return "questionmark.circle"
        case .toolUse, .toolResult: return "terminal"
        case .userPrompt: return "person"
        case .assistantMessage: return "sparkles"
        case .sessionStart, .sessionEnd: return "play.circle"
        case .stop: return "stop.circle"
        case .todos: return "checkmark.circle"
        }
    }
}
