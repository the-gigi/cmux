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
    @StateObject private var viewModel = FeedPanelViewModel()

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()
            FeedListView(filter: filter, items: viewModel.items)
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

/// Bridges the `@Observable` WorkstreamStore to a Combine `@Published`
/// snapshot so SwiftUI reliably re-renders the Feed panel on every
/// mutation. This is the documented pattern for observing an
/// Observable from outside SwiftUI's implicit body-tracking (singleton
/// access + optional chain breaks the implicit path in our case).
///
/// Re-arms `withObservationTracking` after every change so the next
/// mutation also fires. Also retries mounting the observation if the
/// store isn't yet installed (launch-time ordering).
@MainActor
final class FeedPanelViewModel: ObservableObject {
    @Published private(set) var items: [WorkstreamItem] = []

    init() {
        arm()
    }

    private func arm() {
        if FeedCoordinator.shared.store == nil {
            // Store not yet installed. Retry shortly — install happens
            // synchronously in applicationDidFinishLaunching but the
            // view might be constructed slightly earlier in the same
            // runloop tick on edge cases.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.arm()
            }
            return
        }
        withObservationTracking {
            items = FeedCoordinator.shared.store?.items ?? []
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.arm()
            }
        }
    }
}

/// Inner list view. Isolated so the outer panel's `@State` changes don't
/// invalidate rows unnecessarily. Receives items as a plain value so
/// its body never touches the live store — the parent owns the
/// observation.
private struct FeedListView: View {
    let filter: FeedPanelView.Filter
    let items: [WorkstreamItem]

    var body: some View {
        let visible = filtered(items)
        if visible.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    let pending = visible.filter { $0.status.isPending }
                    let rest = visible.filter { !$0.status.isPending }
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
    }

    private func filtered(_ items: [WorkstreamItem]) -> [WorkstreamItem] {
        let base: [WorkstreamItem]
        switch filter {
        case .actionable:
            base = items.filter { $0.kind.isActionable }
        case .all:
            base = items
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
    let approveExitPlan: (UUID, WorkstreamExitPlanMode, String?) -> Void
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
            approveExitPlan: { itemId, mode, feedback in
                Task { @MainActor in
                    FeedCoordinator.shared.deliverReply(
                        requestId: Self.requestId(for: itemId) ?? itemId.uuidString,
                        decision: .exitPlan(mode, feedback: feedback)
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
            case .question(let rid, _): return rid
            default: return nil
            }
        }
    }
}

// MARK: - Row (matches SessionIndexView row aesthetic)

struct FeedItemRow: View {
    let snapshot: FeedItemSnapshot
    let actions: FeedRowActions

    @State private var isHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            chipHeader
            if let echo = promptEcho, !echo.isEmpty {
                Text(echo)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
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

    private var promptEcho: String? {
        switch snapshot.payload {
        case .permissionRequest(_, let toolName, _, _):
            return "You: \(toolName) request from \(snapshot.source.rawValue.capitalized)"
        case .exitPlan:
            return nil
        case .question:
            return nil
        default:
            return nil
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

    /// Vibe-Island-inspired header: kind icon + project/path title on
    /// the left, chip row on the right (agent, cmux, time, optional
    /// jump indicator).
    private var chipHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: snapshot.kind.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(kindTint)
                .frame(width: 16, height: 16)
            Text(headerTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                chip(
                    text: snapshot.source.rawValue.capitalized,
                    fg: sourceChipForeground,
                    bg: sourceChipBackground
                )
                chip(
                    text: "cmux",
                    fg: .secondary,
                    bg: Color.primary.opacity(0.10)
                )
                chip(
                    text: relativeTimeChip(snapshot.createdAt),
                    fg: .secondary,
                    bg: Color.primary.opacity(0.10),
                    mono: true
                )
                if canJump {
                    jumpChip
                }
            }
        }
    }

    private var headerTitle: String {
        if let title = snapshot.title, !title.isEmpty {
            if let cwd = snapshot.cwd, !cwd.isEmpty {
                return "\(cwdShort(cwd)) · \(title)"
            }
            return title
        }
        if let cwd = snapshot.cwd, !cwd.isEmpty {
            return "\(cwdShort(cwd)) · \(kindLabel.capitalized)"
        }
        return kindLabel.capitalized
    }

    private func cwdShort(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }

    private var canJump: Bool {
        return true
    }

    private var jumpChip: some View {
        HStack(spacing: 2) {
            Text("⌘G")
                .font(.system(size: 10, weight: .semibold).monospaced())
            Image(systemName: "arrow.up.forward")
                .font(.system(size: 8, weight: .semibold))
        }
        .foregroundColor(.blue)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.blue.opacity(0.15))
        )
    }

    private func chip(text: String, fg: Color, bg: Color, mono: Bool = false) -> some View {
        Text(text)
            .font(mono
                  ? .system(size: 10, weight: .semibold).monospacedDigit()
                  : .system(size: 10, weight: .semibold))
            .foregroundColor(fg)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(bg)
            )
    }

    private var sourceChipForeground: Color {
        switch snapshot.source {
        case .claude: return Color(red: 0.92, green: 0.54, blue: 0.29)
        case .codex: return .green
        case .opencode: return .blue
        case .cursor: return .purple
        default: return .secondary
        }
    }

    private var sourceChipBackground: Color {
        return sourceChipForeground.opacity(0.18)
    }

    private func relativeTimeChip(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "<1m" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86_400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86_400))d"
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
                onApprove: { mode, feedback in
                    actions.approveExitPlan(snapshot.id, mode, feedback)
                }
            )
        case .question(_, let questions):
            QuestionActionArea(
                questions: questions,
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
        case .exitPlan(let m, let feedback):
            if let feedback, !feedback.isEmpty {
                return String(localized: "feed.badge.refined", defaultValue: "Refined")
            }
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
    let onApprove: (WorkstreamExitPlanMode, String?) -> Void

    @State private var feedback: String = ""

    private var trimmedFeedback: String {
        feedback.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var hasFeedback: Bool { !trimmedFeedback.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlanBodyView(plan: plan)
            if status.isPending {
                TextField(
                    String(
                        localized: "feed.exitplan.feedback.placeholder",
                        defaultValue: "Tell Claude what to change…"
                    ),
                    text: $feedback,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .lineLimit(2...5)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(hasFeedback ? 0.25 : 0.10), lineWidth: 1)
                )
                HStack(spacing: 6) {
                    PlanCTAButton(
                        label: hasFeedback
                            ? String(localized: "feed.exitplan.refine",
                                     defaultValue: "Send feedback")
                            : String(localized: "feed.exitplan.manual",
                                     defaultValue: "Manually Approve"),
                        role: hasFeedback ? .refine : .neutral
                    ) {
                        // When there's feedback, hand it back with .manual
                        // as a placeholder mode; the hook translates
                        // "feedback non-empty" into block+reason regardless
                        // of mode.
                        onApprove(.manual, hasFeedback ? trimmedFeedback : nil)
                    }
                    PlanCTAButton(
                        label: String(localized: "feed.exitplan.autoaccept",
                                      defaultValue: "Auto-accept Edits"),
                        role: .orange,
                        dimmed: hasFeedback
                    ) {
                        onApprove(.autoAccept, hasFeedback ? trimmedFeedback : nil)
                    }
                    PlanCTAButton(
                        label: String(localized: "feed.exitplan.bypass",
                                      defaultValue: "Bypass Permissions"),
                        role: .red,
                        dimmed: hasFeedback
                    ) {
                        onApprove(.bypassPermissions, hasFeedback ? trimmedFeedback : nil)
                    }
                }
            }
        }
    }
}

/// Renders plan text as a stack of small structured sections. Looks for
/// lines formatted like `**Context**` / `# Approach` / `- item` and
/// renders them with matching emphasis. Everything else renders as
/// prose so we never drop content.
private struct PlanBodyView: View {
    let plan: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let text):
                    Text(text)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary.opacity(0.95))
                        .padding(.top, 2)
                case .paragraph(let text):
                    Text(text)
                        .font(.system(size: 12))
                        .foregroundColor(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                case .numbered(let items):
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 6) {
                                Text("\(item.index).")
                                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                    .foregroundColor(.secondary)
                                Text(item.text)
                                    .font(.system(size: 12))
                                    .foregroundColor(.primary.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                case .bulleted(let items):
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 6) {
                                Text("·")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Color.blue.opacity(0.8))
                                Text(item)
                                    .font(.system(size: 12))
                                    .foregroundColor(.primary.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private enum Block {
        case heading(String)
        case paragraph(String)
        case numbered([NumberedItem])
        case bulleted([String])
    }

    private struct NumberedItem {
        let index: Int
        let text: String
    }

    private var blocks: [Block] {
        var out: [Block] = []
        var buffer: [String] = []
        func flushParagraph() {
            guard !buffer.isEmpty else { return }
            let joined = buffer.joined(separator: " ")
            out.append(.paragraph(joined))
            buffer = []
        }
        var numbered: [NumberedItem] = []
        func flushNumbered() {
            if !numbered.isEmpty {
                out.append(.numbered(numbered))
                numbered = []
            }
        }
        var bulleted: [String] = []
        func flushBulleted() {
            if !bulleted.isEmpty {
                out.append(.bulleted(bulleted))
                bulleted = []
            }
        }

        for rawLine in plan.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph(); flushNumbered(); flushBulleted()
                continue
            }
            // **Bold heading** or ## heading or "Word:" on its own line
            if line.hasPrefix("**") && line.hasSuffix("**") && line.count > 4 {
                flushParagraph(); flushNumbered(); flushBulleted()
                out.append(.heading(String(line.dropFirst(2).dropLast(2))))
                continue
            }
            if line.hasPrefix("## ") {
                flushParagraph(); flushNumbered(); flushBulleted()
                out.append(.heading(String(line.dropFirst(3))))
                continue
            }
            if line.hasPrefix("# ") {
                flushParagraph(); flushNumbered(); flushBulleted()
                out.append(.heading(String(line.dropFirst(2))))
                continue
            }
            if line.hasSuffix(":") && line.count <= 40
               && !line.contains(" ") == false && line.split(separator: " ").count <= 4
            {
                flushParagraph(); flushNumbered(); flushBulleted()
                out.append(.heading(line))
                continue
            }
            // Numbered list
            if let match = line.range(
                of: #"^(\d+)\.\s+(.+)$"#,
                options: .regularExpression
            ) {
                flushParagraph(); flushBulleted()
                let text = String(line[match])
                if let dotIdx = text.firstIndex(of: ".") {
                    let numStr = String(text[text.startIndex..<dotIdx])
                    let content = String(text[text.index(after: dotIdx)...])
                        .trimmingCharacters(in: .whitespaces)
                    numbered.append(NumberedItem(
                        index: Int(numStr) ?? (numbered.count + 1),
                        text: content
                    ))
                }
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("• ") || line.hasPrefix("* ") {
                flushParagraph(); flushNumbered()
                let text = String(line.dropFirst(2))
                bulleted.append(text)
                continue
            }
            buffer.append(line)
        }
        flushParagraph(); flushNumbered(); flushBulleted()
        return out
    }
}

/// Full-width color-coded CTA for plan-mode decisions.
private struct PlanCTAButton: View {
    enum Role { case neutral, orange, red, refine }
    let label: String
    let role: Role
    var dimmed: Bool = false
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(fill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(border, lineWidth: 1)
                )
                .opacity(dimmed ? 0.55 : 1.0)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var foreground: Color {
        switch role {
        case .neutral: return .primary
        case .refine: return .white
        case .orange: return .white
        case .red: return .white
        }
    }

    private var fill: Color {
        switch role {
        case .neutral:
            return isHovered ? Color.primary.opacity(0.16) : Color.primary.opacity(0.10)
        case .refine:
            return isHovered
                ? Color(red: 0.28, green: 0.55, blue: 0.95)
                : Color(red: 0.24, green: 0.48, blue: 0.88)
        case .orange:
            return isHovered
                ? Color(red: 0.95, green: 0.55, blue: 0.18)
                : Color(red: 0.92, green: 0.54, blue: 0.29)
        case .red:
            return isHovered
                ? Color(red: 0.85, green: 0.28, blue: 0.28)
                : Color(red: 0.75, green: 0.22, blue: 0.22)
        }
    }

    private var border: Color {
        switch role {
        case .neutral: return Color.primary.opacity(0.18)
        case .refine: return Color.black.opacity(0.18)
        case .orange: return Color.black.opacity(0.15)
        case .red: return Color.black.opacity(0.20)
        }
    }
}

private struct QuestionActionArea: View {
    let questions: [WorkstreamQuestionPrompt]
    let status: WorkstreamStatus
    let onReply: ([String]) -> Void

    // Per-question selections keyed by question id.
    @State private var selections: [String: Set<String>] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerLine
            ForEach(Array(questions.enumerated()), id: \.offset) { idx, q in
                questionBlock(index: idx + 1, question: q)
            }
            if status.isPending {
                submitCTA
            }
        }
    }

    private var headerLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 12))
                .foregroundColor(.blue)
            Text("\(questions.first.map { _ in "Question" } ?? "Question")")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.blue)
            Text("(\(questions.count) \(questions.count == 1 ? "question" : "questions"))")
                .font(.system(size: 11))
                .foregroundColor(.blue.opacity(0.7))
        }
    }

    private func questionBlock(index: Int, question: WorkstreamQuestionPrompt) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Text("\(index).")
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundColor(.blue)
                Text(question.prompt)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if question.multiSelect {
                HStack(spacing: 4) {
                    Image(systemName: "checklist")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Multi-select")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.3)
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.orange.opacity(0.18))
                )
            }
            if question.options.isEmpty {
                Text(String(localized: "feed.question.noOptions",
                            defaultValue: "Agent provided no options."))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                WrapHStack(spacing: 6) {
                    ForEach(question.options, id: \.id) { option in
                        optionPill(questionId: question.id, option: option, multi: question.multiSelect)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func optionPill(
        questionId: String,
        option: WorkstreamQuestionOption,
        multi: Bool
    ) -> some View {
        let selected = selections[questionId]?.contains(option.id) == true
        return Button {
            var current = selections[questionId] ?? []
            if multi {
                if current.contains(option.id) { current.remove(option.id) }
                else { current.insert(option.id) }
            } else {
                current = [option.id]
            }
            selections[questionId] = current
        } label: {
            Text(option.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(selected ? .primary : .primary.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(selected
                                ? Color.accentColor.opacity(0.55)
                                : Color.primary.opacity(0.10),
                                lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var allAnswered: Bool {
        for q in questions where (selections[q.id]?.isEmpty ?? true) {
            return false
        }
        return true
    }

    private var submitCTA: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                // Flatten every question's selections into a single
                // array, prefixed with the question id so the agent
                // receives `["q0:minimal", "q1:reload_tagged"]`.
                var out: [String] = []
                for q in questions {
                    if let set = selections[q.id] {
                        for id in set { out.append("\(q.id):\(id)") }
                    }
                }
                onReply(out)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                    Text(String(localized: "feed.question.submitAll", defaultValue: "Submit All Answers"))
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(allAnswered ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(allAnswered ? Color.primary.opacity(0.14) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(allAnswered ? 0.22 : 0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(!allAnswered)

            if !allAnswered {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(String(localized: "feed.question.answerAll",
                                defaultValue: "Please answer all questions"))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.orange)
            }
        }
    }
}

/// Minimal wrapping HStack that flows its children into multiple rows.
private struct WrapHStack<Content: View>: View {
    let spacing: CGFloat
    let content: () -> Content

    init(spacing: CGFloat = 4, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        FlowLayout(spacing: spacing) {
            content()
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                totalHeight += currentRowHeight + spacing
                totalWidth = max(totalWidth, currentX - spacing)
                currentX = 0
                currentRowHeight = 0
            }
            currentX += size.width + spacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
        totalHeight += currentRowHeight
        totalWidth = max(totalWidth, currentX - spacing)
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct TelemetryActionArea: View {
    let snapshot: FeedItemSnapshot

    var body: some View {
        if case .todos(let todos) = snapshot.payload {
            TodoListBody(todos: todos)
        } else if !summary.isEmpty {
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
        default:
            return ""
        }
    }
}

private struct TodoListBody: View {
    let todos: [WorkstreamTaskTodo]

    @State private var expanded = false

    private var done: [WorkstreamTaskTodo] { todos.filter { $0.state == .completed } }
    private var inProgress: [WorkstreamTaskTodo] { todos.filter { $0.state == .inProgress } }
    private var pending: [WorkstreamTaskTodo] { todos.filter { $0.state == .pending } }

    private var visibleDone: [WorkstreamTaskTodo] {
        expanded ? done : Array(done.prefix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Tasks")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary.opacity(0.9))
                Text(summaryLabel)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(inProgress, id: \.id) { row($0) }
                ForEach(pending, id: \.id) { row($0) }
                ForEach(visibleDone, id: \.id) { row($0) }
                if done.count > visibleDone.count {
                    Button {
                        expanded.toggle()
                    } label: {
                        Text("… +\(done.count - visibleDone.count) completed")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                            .padding(.leading, 22)
                    }
                    .buttonStyle(.plain)
                }
                if expanded && done.count > 2 {
                    Button { expanded = false } label: {
                        Text("Collapse")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                            .padding(.leading, 22)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var summaryLabel: String {
        let d = done.count, ip = inProgress.count, p = pending.count
        var parts: [String] = []
        if d > 0 { parts.append("\(d) done") }
        if ip > 0 { parts.append("\(ip) in progress") }
        if p > 0 { parts.append("\(p) open") }
        return "(" + parts.joined(separator: ", ") + ")"
    }

    @ViewBuilder
    private func row(_ todo: WorkstreamTaskTodo) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol(for: todo.state))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color(for: todo.state))
                .frame(width: 14, height: 14)
            Text(todo.content)
                .font(.system(size: 12))
                .foregroundColor(todo.state == .completed
                    ? .secondary.opacity(0.7)
                    : .primary.opacity(0.9))
                .strikethrough(todo.state == .completed, color: .secondary.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    private func symbol(for state: WorkstreamTaskTodo.State) -> String {
        switch state {
        case .completed: return "checkmark.square.fill"
        case .inProgress: return "circle.inset.filled"
        case .pending: return "square"
        }
    }

    private func color(for state: WorkstreamTaskTodo.State) -> Color {
        switch state {
        case .completed: return .secondary.opacity(0.7)
        case .inProgress: return .blue
        case .pending: return .secondary
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
