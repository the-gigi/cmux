import CMUXWorkstream
import SwiftUI

/// Right-sidebar Feed view. Matches the Sessions page visual language:
/// compact rows with SF Symbol + 13pt title + secondary metadata,
/// rounded-rect hover backgrounds with 6px inset, and control-bar
/// pill buttons styled like `GroupingButton` in `SessionIndexView`.
///
/// Pending items float above resolved; telemetry is hidden unless the
/// user flips the Actionable / All filter. Rows receive immutable
/// snapshots + closure action bundles only (snapshot-boundary rule).
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
        var symbolName: String {
            switch self {
            case .actionable: return "exclamationmark.circle"
            case .all: return "list.bullet"
            }
        }
    }

    @State private var filter: Filter = .actionable

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()
            FeedListView(
                filter: filter,
                store: FeedCoordinator.shared.store
            )
        }
    }

    private var controlBar: some View {
        HStack(spacing: 6) {
            ForEach(Filter.allCases) { f in
                FeedPillButton(
                    label: f.label,
                    symbolName: f.symbolName,
                    isSelected: filter == f
                ) {
                    filter = f
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(height: 29)
    }
}

/// Inner list view. Isolated so the outer panel's `@State` changes don't
/// invalidate rows unnecessarily.
private struct FeedListView: View {
    let filter: FeedPanelView.Filter
    let store: WorkstreamStore?

    var body: some View {
        if let store {
            let items = snapshot(from: store)
            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        let pending = items.filter { $0.status.isPending }
                        let rest = items.filter { !$0.status.isPending }
                        ForEach(pending, id: \.id) { item in
                            FeedItemRow(
                                snapshot: FeedItemSnapshot(item: item),
                                actions: FeedRowActions.bound()
                            )
                        }
                        if !pending.isEmpty && !rest.isEmpty {
                            ResolvedDivider()
                        }
                        ForEach(rest, id: \.id) { item in
                            FeedItemRow(
                                snapshot: FeedItemSnapshot(item: item),
                                actions: FeedRowActions.bound()
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
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
        return base.sorted { a, b in
            if a.status.isPending != b.status.isPending {
                return a.status.isPending
            }
            return a.createdAt > b.createdAt
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text(filter == .actionable
                 ? String(localized: "feed.empty.actionable.title",
                          defaultValue: "No pending decisions")
                 : String(localized: "feed.empty.all.title",
                          defaultValue: "No feed activity yet"))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text(filter == .actionable
                 ? String(localized: "feed.empty.actionable.subtitle",
                          defaultValue: "Permission, plan, and question requests from AI agents will appear here.")
                 : String(localized: "feed.empty.all.subtitle",
                          defaultValue: "Tool use, messages, and session events will appear here."))
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Row snapshot + actions (respects snapshot-boundary rule)

/// Immutable snapshot of a `WorkstreamItem` handed to row views so rows
/// never hold a reference to the store.
struct FeedItemSnapshot: Equatable {
    let id: UUID
    let workstreamId: String
    let source: WorkstreamSource
    let kind: WorkstreamKind
    let title: String?
    let cwd: String?
    let createdAt: Date
    let status: WorkstreamStatus
    let payload: WorkstreamPayload

    init(item: WorkstreamItem) {
        self.id = item.id
        self.workstreamId = item.workstreamId
        self.source = item.source
        self.kind = item.kind
        self.title = item.title
        self.cwd = item.cwd
        self.createdAt = item.createdAt
        self.status = item.status
        self.payload = item.payload
    }
}

private func snapshotWorkstreamId(_ s: FeedItemSnapshot) -> String {
    s.workstreamId
}

/// Closure bundle; binds to `FeedCoordinator` by default.
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
                Task { @MainActor in
                    _ = FeedCoordinator.shared.focusIfPossible(workstreamId: workstreamId)
                }
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

// MARK: - Row (matches SessionIndexView row aesthetic)

private struct FeedItemRow: View {
    let snapshot: FeedItemSnapshot
    let actions: FeedRowActions

    @State private var isHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            actionArea
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
        .opacity(isResolvedOrExpired ? 0.6 : 1.0)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovered = $0 }
        .help(helpText)
        .onTapGesture(count: 2) {
            actions.jump(workstreamIdForJump)
        }
    }

    private var isResolvedOrExpired: Bool {
        switch snapshot.status {
        case .pending: return false
        case .telemetry: return false
        case .resolved, .expired: return true
        }
    }

    private var cardBackground: Color {
        if snapshot.status.isPending {
            return Color.primary.opacity(isHovered ? 0.06 : 0.04)
        }
        return Color.primary.opacity(isHovered ? 0.03 : 0.02)
    }

    private var cardBorder: Color {
        switch snapshot.status {
        case .pending: return Color.primary.opacity(0.14)
        default: return Color.primary.opacity(0.08)
        }
    }

    private var workstreamIdForJump: String {
        // Store mirror of the workstream id; snapshot doesn't carry it
        // directly because payloads do. Fall back to source-only when
        // the item kind doesn't embed a session linkage.
        switch snapshot.payload {
        case .permissionRequest, .exitPlan, .question:
            return snapshotWorkstreamId(snapshot)
        default:
            return snapshotWorkstreamId(snapshot)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: snapshot.kind.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(kindTint)
                .frame(width: 14, height: 14)
            HStack(spacing: 4) {
                Text(kindLabel)
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.5)
                    .foregroundColor(kindTint)
                Text("·")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.5))
                Text(snapshot.source.rawValue.capitalized)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.85))
            }
            Spacer(minLength: 8)
            if case .resolved(let decision, _) = snapshot.status {
                statusTag(resolvedBadgeLabel(decision), color: .green)
            } else if case .expired = snapshot.status {
                statusTag(
                    String(localized: "feed.status.expired", defaultValue: "Expired"),
                    color: .secondary
                )
            }
            Text(relativeTime(snapshot.createdAt))
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(.secondary.opacity(0.7))
                .fixedSize()
        }
    }

    private var kindLabel: String {
        switch snapshot.kind {
        case .permissionRequest: return "PERMISSION"
        case .exitPlan: return "PLAN"
        case .question: return "QUESTION"
        case .toolUse: return "TOOL USE"
        case .toolResult: return "TOOL RESULT"
        case .userPrompt: return "PROMPT"
        case .assistantMessage: return "MESSAGE"
        case .sessionStart: return "SESSION START"
        case .sessionEnd: return "SESSION END"
        case .stop: return "STOP"
        case .todos: return "TODOS"
        }
    }

    private var kindTint: Color {
        switch snapshot.kind {
        case .permissionRequest: return .orange
        case .exitPlan: return .purple
        case .question: return .blue
        default: return snapshot.status.isPending ? .orange : .secondary.opacity(0.8)
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        switch snapshot.payload {
        case .permissionRequest(_, let toolName, let toolInputJSON, _):
            PermissionActionArea(
                toolName: toolName,
                toolInputJSON: toolInputJSON,
                status: snapshot.status,
                onApprove: { mode in actions.approvePermission(snapshot.id, mode) }
            )
        case .exitPlan(_, let plan, _):
            ExitPlanActionArea(
                plan: plan,
                status: snapshot.status,
                onApprove: { mode in actions.approveExitPlan(snapshot.id, mode) }
            )
        case .question(_, let prompt, let options, let multiSelect):
            QuestionActionArea(
                prompt: prompt,
                options: options,
                multiSelect: multiSelect,
                status: snapshot.status,
                onReply: { selections in actions.replyQuestion(snapshot.id, selections) }
            )
        default:
            TelemetryActionArea(snapshot: snapshot)
        }
    }

    private var primaryTitle: String {
        switch snapshot.payload {
        case .permissionRequest(_, let toolName, _, _):
            return "\(snapshot.source.rawValue.capitalized) · \(toolName)"
        case .exitPlan:
            return "\(snapshot.source.rawValue.capitalized) · ExitPlanMode"
        case .question:
            return "\(snapshot.source.rawValue.capitalized) · Question"
        default:
            if let title = snapshot.title, !title.isEmpty {
                return "\(snapshot.source.rawValue.capitalized) · \(title)"
            }
            return snapshot.source.rawValue.capitalized
        }
    }

    private var helpText: String {
        var lines: [String] = [primaryTitle]
        if let cwd = snapshot.cwd { lines.append(cwd) }
        lines.append(absoluteTime(snapshot.createdAt))
        return lines.joined(separator: "\n")
    }

    private func resolvedBadgeLabel(_ decision: WorkstreamDecision) -> String {
        switch decision {
        case .permission(let m):
            return "\(String(localized: "feed.badge.allowed", defaultValue: "Allowed")) · \(m.rawValue)"
        case .exitPlan(let m):
            return String(localized: "feed.badge.plan", defaultValue: "Plan") + " · \(m.rawValue)"
        case .question:
            return String(localized: "feed.badge.answered", defaultValue: "Answered")
        }
    }

    private func statusTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color.opacity(0.12))
            )
    }

    private func relativeTime(_ date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func absoluteTime(_ date: Date) -> String {
        Self.absoluteFormatter.string(from: date)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}

// MARK: - Per-kind action areas

private struct PermissionActionArea: View {
    let toolName: String
    let toolInputJSON: String
    let status: WorkstreamStatus
    let onApprove: (WorkstreamPermissionMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !toolInputJSON.isEmpty && toolInputJSON != "{}" {
                Text(toolInputJSON)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.9))
                    .lineLimit(3)
                    .truncationMode(.tail)
            }
            if status.isPending {
                HStack(spacing: 6) {
                    FeedPillButton(
                        label: String(localized: "feed.permission.once", defaultValue: "Once"),
                        symbolName: "checkmark.circle",
                        style: .action
                    ) { onApprove(.once) }
                    FeedPillButton(
                        label: String(localized: "feed.permission.always", defaultValue: "Always"),
                        symbolName: "infinity",
                        style: .action
                    ) { onApprove(.always) }
                    FeedPillButton(
                        label: String(localized: "feed.permission.all", defaultValue: "All tools"),
                        symbolName: "checkmark.seal",
                        style: .action
                    ) { onApprove(.all) }
                    FeedPillButton(
                        label: String(localized: "feed.permission.bypass", defaultValue: "Bypass"),
                        symbolName: "bolt",
                        style: .action
                    ) { onApprove(.bypass) }
                    Spacer(minLength: 4)
                    FeedPillButton(
                        label: String(localized: "feed.permission.deny", defaultValue: "Deny"),
                        symbolName: "xmark.circle",
                        tint: .red,
                        style: .action
                    ) { onApprove(.deny) }
                }
            }
        }
    }
}

private struct ExitPlanActionArea: View {
    let plan: String
    let status: WorkstreamStatus
    let onApprove: (WorkstreamExitPlanMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(plan)
                .font(.system(size: 11))
                .foregroundColor(.primary.opacity(0.85))
                .lineLimit(6)
            if status.isPending {
                HStack(spacing: 6) {
                    FeedPillButton(
                        label: String(localized: "feed.exitplan.bypass", defaultValue: "Bypass"),
                        symbolName: "bolt",
                        style: .action
                    ) { onApprove(.bypassPermissions) }
                    FeedPillButton(
                        label: String(localized: "feed.exitplan.autoaccept", defaultValue: "Auto-accept"),
                        symbolName: "wand.and.stars",
                        style: .action
                    ) { onApprove(.autoAccept) }
                    FeedPillButton(
                        label: String(localized: "feed.exitplan.manual", defaultValue: "Manual"),
                        symbolName: "hand.raised",
                        style: .action
                    ) { onApprove(.manual) }
                    Spacer(minLength: 4)
                    FeedPillButton(
                        label: String(localized: "feed.exitplan.deny", defaultValue: "Deny"),
                        symbolName: "xmark.circle",
                        tint: .red,
                        style: .action
                    ) { onApprove(.deny) }
                }
            }
        }
    }
}

private struct QuestionActionArea: View {
    let prompt: String
    let options: [WorkstreamQuestionOption]
    let multiSelect: Bool
    let status: WorkstreamStatus
    let onReply: ([String]) -> Void

    @State private var selectedIds: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !prompt.isEmpty {
                Text(prompt)
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.9))
            }
            if options.isEmpty {
                Text(String(localized: "feed.question.noOptions",
                            defaultValue: "Agent provided no options."))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                ForEach(options, id: \.id) { option in
                    Button {
                        if multiSelect {
                            if selectedIds.contains(option.id) { selectedIds.remove(option.id) }
                            else { selectedIds.insert(option.id) }
                        } else {
                            selectedIds = [option.id]
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: selectedIds.contains(option.id)
                                ? (multiSelect ? "checkmark.square.fill" : "largecircle.fill.circle")
                                : (multiSelect ? "square" : "circle"))
                                .font(.system(size: 11))
                                .foregroundColor(selectedIds.contains(option.id) ? .accentColor : .secondary)
                                .frame(width: 12, height: 12)
                            Text(option.label)
                                .font(.system(size: 12))
                                .foregroundColor(.primary.opacity(0.9))
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if status.isPending {
                HStack {
                    Spacer()
                    FeedPillButton(
                        label: String(localized: "feed.question.submit", defaultValue: "Submit"),
                        symbolName: "paperplane",
                        tint: selectedIds.isEmpty ? .secondary : .accentColor,
                        style: .action
                    ) { onReply(Array(selectedIds)) }
                    .disabled(selectedIds.isEmpty)
                    .opacity(selectedIds.isEmpty ? 0.5 : 1)
                }
            }
        }
    }
}

private struct TelemetryActionArea: View {
    let snapshot: FeedItemSnapshot

    var body: some View {
        if !summary.isEmpty {
            Text(summary)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.85))
                .lineLimit(3)
                .truncationMode(.tail)
        }
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
            return ""
        }
    }
}

// MARK: - Pill button (matches `GroupingButton` in SessionIndexView)

private struct FeedPillButton: View {
    let label: String
    let symbolName: String?
    var isSelected: Bool = false
    var tint: Color = .primary
    let action: () -> Void

    @State private var isHovered: Bool = false

    init(
        label: String,
        symbolName: String? = nil,
        isSelected: Bool = false,
        tint: Color = .primary,
        style: Style = .filter,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.symbolName = symbolName
        self.isSelected = isSelected
        self.tint = tint
        self.style = style
        self.action = action
    }

    /// Distinguishes the two button contexts: filter bar (toggleable,
    /// flat until selected/hovered) versus action buttons inside a feed
    /// card (CTA-style with a resting fill + bold label).
    enum Style { case filter, action }
    var style: Style = .filter

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbolName {
                    Image(systemName: symbolName)
                        .font(.system(size: style == .action ? 11 : 10, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: style == .action ? 12 : 11, weight: style == .action ? .semibold : .medium))
            }
            .foregroundColor(foregroundColor)
            .padding(.horizontal, style == .action ? 10 : 6)
            .padding(.vertical, style == .action ? 5 : 3)
            .background(
                RoundedRectangle(cornerRadius: style == .action ? 6 : 4, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: style == .action ? 6 : 4, style: .continuous)
                    .stroke(borderColor, lineWidth: style == .action ? 1 : 0)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(label)
    }

    private var foregroundColor: Color {
        if tint == .red { return .red }
        if tint == .accentColor { return .accentColor }
        if tint == .secondary { return .secondary }
        if tint != .primary { return tint }
        return isSelected ? .primary : .secondary
    }

    private var backgroundFill: Color {
        if isSelected { return Color.primary.opacity(0.12) }
        if style == .action {
            if tint == .red {
                return isHovered ? Color.red.opacity(0.16) : Color.red.opacity(0.08)
            }
            return isHovered ? Color.primary.opacity(0.10) : Color.primary.opacity(0.06)
        }
        if isHovered {
            return tint == .red
                ? Color.red.opacity(0.10)
                : Color.primary.opacity(0.05)
        }
        return Color.clear
    }

    private var borderColor: Color {
        guard style == .action else { return .clear }
        if tint == .red {
            return Color.red.opacity(isHovered ? 0.35 : 0.18)
        }
        return Color.primary.opacity(isHovered ? 0.18 : 0.10)
    }
}

/// Dashed separator between pending items and resolved ones.
private struct ResolvedDivider: View {
    var body: some View {
        HStack(spacing: 8) {
            line
            Text(String(localized: "feed.divider.resolved", defaultValue: "Resolved"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(.secondary.opacity(0.7))
            line
        }
        .padding(.vertical, 2)
    }

    private var line: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }
}

// MARK: - Kind → SF Symbol

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
