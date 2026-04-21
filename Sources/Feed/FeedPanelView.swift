import AppKit
import CMUXWorkstream
import SwiftUI

private extension WorkstreamPermissionMode {
    var displayLabel: String {
        switch self {
        case .once:
            return String(localized: "feed.permission.mode.once", defaultValue: "once")
        case .always:
            return String(localized: "feed.permission.mode.always", defaultValue: "always")
        case .all:
            return String(localized: "feed.permission.mode.all", defaultValue: "all tools")
        case .bypass:
            return String(localized: "feed.permission.mode.bypass", defaultValue: "bypass")
        case .deny:
            return String(localized: "feed.permission.mode.deny", defaultValue: "denied")
        }
    }
}

private extension WorkstreamExitPlanMode {
    var displayLabel: String {
        switch self {
        case .bypassPermissions:
            return String(localized: "feed.exitplan.mode.bypass", defaultValue: "bypass")
        case .autoAccept:
            return String(localized: "feed.exitplan.mode.autoAccept", defaultValue: "auto-accept")
        case .manual:
            return String(localized: "feed.exitplan.mode.manual", defaultValue: "manual")
        case .deny:
            return String(localized: "feed.exitplan.mode.deny", defaultValue: "denied")
        }
    }
}

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
        case activity
        var id: String { rawValue }
        var label: String {
            switch self {
            case .actionable:
                return String(localized: "feed.filter.actionable", defaultValue: "Actionable")
            case .activity:
                return String(localized: "feed.filter.activity", defaultValue: "Activity")
            }
        }
        var symbolName: String {
            switch self {
            case .actionable: return "exclamationmark.circle"
            case .activity: return "checklist"
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
                FeedButton(
                    label: f.label,
                    leadingIcon: f.symbolName,
                    kind: .ghost,
                    size: .compact,
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
        let lastPromptByWorkstream = Self.lastPromptByWorkstream(items)
        if visible.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Single chronological stream — resolved cards stay
                    // where they are instead of jumping to a "Resolved"
                    // section. Each card's own header already says
                    // Submitted / Resolved, so position doesn't need to
                    // double-encode the state. Rows are separated by a
                    // thin 1-px divider (matches Sessions panel).
                    ForEach(Array(visible.enumerated()), id: \.element.id) { idx, item in
                        FeedItemRow(
                            snapshot: FeedItemSnapshot(
                                item: item,
                                userPromptEcho: lastPromptByWorkstream[item.workstreamId]
                            ),
                            actions: FeedRowActions.bound()
                        )
                        if idx < visible.count - 1 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.08))
                                .frame(maxWidth: .infinity)
                                .frame(height: 1)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    /// Walks the full items list (not just the filtered visible set),
    /// ordered by createdAt, and records the most recent user-prompt
    /// text per workstreamId. Rows consult this dict to show a
    /// "You: …" echo line at the top of their card.
    private static func lastPromptByWorkstream(_ items: [WorkstreamItem]) -> [String: String] {
        var out: [String: String] = [:]
        let sorted = items.sorted { $0.createdAt < $1.createdAt }
        for item in sorted {
            if case .userPrompt(let text) = item.payload, !text.isEmpty {
                out[item.workstreamId] = text
            }
        }
        return out
    }

    private func filtered(_ items: [WorkstreamItem]) -> [WorkstreamItem] {
        let base: [WorkstreamItem]
        switch filter {
        case .actionable:
            base = items.filter { $0.kind.isActionable }
        case .activity:
            // Actionable kinds + todos + stop. Tool use, user prompts,
            // assistant messages, session markers, and raw
            // notifications are intentionally excluded — they're too
            // noisy for a sidebar and already visible in the agent's
            // terminal or the cmux notification system. Stop events
            // render a "reply to Claude" textbox so the user can
            // nudge Claude without switching focus to the terminal.
            base = items.filter { item in
                item.kind.isActionable
                    || item.kind == .todos
                    || item.kind == .stop
            }
        }
        // Newest first. Status isn't a sort key — resolved items stay
        // in the chronological slot where they arrived so the user's
        // mental map of "this was the second request I got" doesn't
        // get shuffled when they answer it.
        return base.sorted { $0.createdAt > $1.createdAt }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text(filter == .actionable
                 ? String(localized: "feed.empty.actionable.title",
                          defaultValue: "No pending decisions")
                 : String(localized: "feed.empty.activity.title",
                          defaultValue: "No activity yet"))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text(filter == .actionable
                 ? String(localized: "feed.empty.actionable.subtitle",
                          defaultValue: "Permission, plan, and question requests from AI agents will appear here.")
                 : String(localized: "feed.empty.activity.subtitle",
                          defaultValue: "Agent decisions and todo-list updates will appear here."))
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
    /// Most recent user-prompt text in the same workstream, attached
    /// by the list view so every card can show a "You: …" echo for
    /// context, even when the agent payload doesn't carry it directly.
    let userPromptEcho: String?

    init(item: WorkstreamItem, userPromptEcho: String? = nil) {
        self.id = item.id
        self.workstreamId = item.workstreamId
        self.source = item.source
        self.kind = item.kind
        self.title = item.title
        self.cwd = item.cwd
        self.createdAt = item.createdAt
        self.status = item.status
        self.payload = item.payload
        self.userPromptEcho = userPromptEcho
    }
}

/// Closure bundle; binds to `FeedCoordinator` by default.
struct FeedRowActions {
    let approvePermission: (UUID, WorkstreamPermissionMode) -> Void
    let replyQuestion: (UUID, [String]) -> Void
    let approveExitPlan: (UUID, WorkstreamExitPlanMode, String?) -> Void
    let jump: (String) -> Void
    /// Types the user's reply into the agent's terminal surface and
    /// presses Return. Used by Stop-kind cards so the user can nudge
    /// Claude without switching focus to the terminal.
    let sendText: (String, String) -> Void

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
            },
            sendText: { workstreamId, text in
                Task { @MainActor in
                    FeedCoordinator.shared.sendTextToWorkstream(
                        workstreamId: workstreamId,
                        text: text
                    )
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            chipHeader
            if let echo = promptEcho, !echo.isEmpty {
                Text(echo)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            actionArea
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isResolvedOrExpired ? 0.6 : 1.0)
        .contentShape(Rectangle())
        .help(helpText)
        // Single-tap on the card background focuses the agent's
        // cmux terminal and flashes the terminal's own ring (same
        // visual as cmd+shift+H). The flash happens on the terminal
        // surface, not on this card — so the user's eye is pulled
        // to the terminal contents they're jumping to.
        .onTapGesture {
            actions.jump(snapshot.workstreamId)
        }
    }

    private var promptEcho: String? {
        // Prefer the real user prompt attached by the list view (walks
        // the same workstream for the most recent .userPrompt
        // telemetry). Falls back to the older synthesized text for
        // permission cards only, so new sessions without a prompt echo
        // still say something useful in that specific case.
        if let echo = snapshot.userPromptEcho,
           !echo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return String(localized: "feed.promptEcho", defaultValue: "You: \(echo)")
        }
        if case .permissionRequest(_, let toolName, _, _) = snapshot.payload {
            return String(
                localized: "feed.promptEcho.permission",
                defaultValue: "You: \(toolName) request from \(snapshot.source.rawValue.capitalized)"
            )
        }
        return nil
    }

    private var isResolvedOrExpired: Bool {
        switch snapshot.status {
        case .pending: return false
        case .telemetry: return false
        case .resolved, .expired: return true
        }
    }

    /// Vibe-Island-inspired header: kind icon + project/path title on
    /// the left, chip row on the right (agent, cmux, time, optional
    /// jump indicator).
    private var chipHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: snapshot.kind.symbolName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(kindTint)
                .frame(width: 14, height: 14)
            Text(headerTitle)
                .font(.system(size: 12, weight: .medium))
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
                jumpChip
            }
        }
    }

    private var headerTitle: String {
        // Prefer the user prompt as the card title — it's the most
        // useful context ("fun · make a plan and ask me for permissions")
        // rather than the raw tool name ("~/fun · AskUserQuestion").
        let promptLine = snapshot.userPromptEcho?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !promptLine.isEmpty {
            if let cwd = snapshot.cwd, !cwd.isEmpty {
                return "\(cwdBasename(cwd)) · \(promptLine)"
            }
            return promptLine
        }
        if let title = snapshot.title, !title.isEmpty {
            if let cwd = snapshot.cwd, !cwd.isEmpty {
                return "\(cwdBasename(cwd)) · \(title)"
            }
            return title
        }
        if let cwd = snapshot.cwd, !cwd.isEmpty {
            return "\(cwdBasename(cwd)) · \(kindLabel.capitalized)"
        }
        return kindLabel.capitalized
    }

    /// Last path component only — `fun` instead of `~/fun` or the full
    /// absolute path. Matches the Vibe-Island mockup's compact header.
    private func cwdBasename(_ path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        let name = (trimmed as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }

    private var canJump: Bool {
        return true
    }

    private var jumpChip: some View {
        HStack(spacing: 2) {
            Text("^G")
                .font(.system(size: 10, weight: .medium).monospaced())
            Image(systemName: "arrow.up.forward")
                .font(.system(size: 8, weight: .medium))
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
                  ? .system(size: 10, weight: .medium).monospacedDigit()
                  : .system(size: 10, weight: .medium))
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
        case .permissionRequest:
            return String(localized: "feed.kind.permission", defaultValue: "PERMISSION")
        case .exitPlan:
            return String(localized: "feed.kind.plan", defaultValue: "PLAN")
        case .question:
            return String(localized: "feed.kind.question.upper", defaultValue: "QUESTION")
        case .toolUse:
            return String(localized: "feed.kind.toolUse", defaultValue: "TOOL USE")
        case .toolResult:
            return String(localized: "feed.kind.toolResult", defaultValue: "TOOL RESULT")
        case .userPrompt:
            return String(localized: "feed.kind.prompt", defaultValue: "PROMPT")
        case .assistantMessage:
            return String(localized: "feed.kind.message", defaultValue: "MESSAGE")
        case .sessionStart:
            return String(localized: "feed.kind.sessionStart.upper", defaultValue: "SESSION START")
        case .sessionEnd:
            return String(localized: "feed.kind.sessionEnd.upper", defaultValue: "SESSION END")
        case .stop:
            return String(localized: "feed.kind.stop", defaultValue: "STOP")
        case .todos:
            return String(localized: "feed.kind.todos", defaultValue: "TODOS")
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
                onApprove: { mode in
                    actions.approvePermission(snapshot.id, mode)
                }
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
                onReply: { selections in
                    actions.replyQuestion(snapshot.id, selections)
                }
            )
        case .stop:
            StopActionArea(
                workstreamId: snapshot.workstreamId,
                onSend: { text in actions.sendText(snapshot.workstreamId, text) }
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
            return "\(snapshot.source.rawValue.capitalized) · \(String(localized: "feed.kind.exitPlan", defaultValue: "Exit plan"))"
        case .question:
            return "\(snapshot.source.rawValue.capitalized) · \(String(localized: "feed.kind.question", defaultValue: "Question"))"
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
        let submitted = String(localized: "feed.badge.submitted", defaultValue: "Submitted")
        switch decision {
        case .permission(let m):
            return "\(submitted) · \(m.displayLabel)"
        case .exitPlan(let m, let feedback):
            if let feedback, !feedback.isEmpty {
                return "\(submitted) · " + String(localized: "feed.badge.refined", defaultValue: "refined")
            }
            return "\(submitted) · \(m.displayLabel)"
        case .question:
            return submitted
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
        VStack(alignment: .leading, spacing: 10) {
            toolLabel
            codeBlock
            if status.isPending {
                HStack(spacing: 6) {
                    FeedButton(
                        label: String(localized: "feed.permission.deny", defaultValue: "Deny"),
                        kind: .dark, size: .medium, fullWidth: true
                    ) { onApprove(.deny) }
                    FeedButton(
                        label: String(localized: "feed.permission.once", defaultValue: "Allow Once"),
                        kind: .light, size: .medium, fullWidth: true
                    ) { onApprove(.once) }
                    FeedButton(
                        label: String(localized: "feed.permission.always", defaultValue: "Always Allow"),
                        kind: .primary, size: .medium, fullWidth: true
                    ) { onApprove(.always) }
                    FeedButton(
                        label: String(localized: "feed.permission.bypass", defaultValue: "Bypass"),
                        kind: .destructive, size: .medium, fullWidth: true
                    ) { onApprove(.bypass) }
                }
            } else if let badge = submittedBadge {
                FeedButton(
                    label: badge,
                    leadingIcon: "checkmark",
                    kind: .success,
                    size: .medium,
                    fullWidth: true,
                    dimmed: true
                ) {}
            }
        }
    }

    private var submittedBadge: String? {
        guard case .resolved(let decision, _) = status else { return nil }
        let submitted = String(localized: "feed.badge.submitted", defaultValue: "Submitted")
        if case .permission(let mode) = decision {
            return "\(submitted) · \(mode.displayLabel)"
        }
        return submitted
    }

    private var toolLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.orange)
            Text(toolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.orange)
        }
    }

    private var codeBlock: some View {
        let preview = PermissionInputPreview(
            toolName: toolName,
            toolInputJSON: toolInputJSON
        )
        return VStack(alignment: .leading, spacing: 6) {
            if let primary = preview.primary {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let sigil = preview.sigil {
                        Text(sigil)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                    Text(primary)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.95))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let secondary = preview.secondary, !secondary.isEmpty {
                Text(secondary)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }
}

/// Pulls a human-readable command + description out of an agent's
/// tool_input JSON. Handles Bash (`command` + `description`), Write /
/// Edit / Read (`file_path`), and falls back to the raw JSON.
private struct PermissionInputPreview {
    let sigil: String?
    let primary: String?
    let secondary: String?

    init(toolName: String, toolInputJSON: String) {
        let dict = (try? JSONSerialization.jsonObject(
            with: Data(toolInputJSON.utf8)
        )) as? [String: Any] ?? [:]

        switch toolName.lowercased() {
        case "bash":
            self.sigil = "$"
            self.primary = (dict["command"] as? String) ?? toolInputJSON
            self.secondary = (dict["description"] as? String)
        case "write", "edit", "multiedit":
            self.sigil = nil
            self.primary = (dict["file_path"] as? String) ?? toolInputJSON
            if toolName.lowercased() == "write" {
                let content = (dict["content"] as? String) ?? ""
                let preview = content.split(separator: "\n").first.map(String.init) ?? ""
                self.secondary = preview.isEmpty ? nil : preview
            } else {
                self.secondary = nil
            }
        case "read":
            self.sigil = nil
            self.primary = (dict["file_path"] as? String) ?? toolInputJSON
            self.secondary = nil
        default:
            self.sigil = nil
            self.primary = toolInputJSON == "{}" ? nil : toolInputJSON
            self.secondary = nil
        }
    }
}

/// Single DRY button primitive used across every actionable card
/// (permission / plan / question / filter pills / option pills).
/// Replaces the old PermissionCTAButton / PlanCTAButton /
/// FeedPillButton trio so styling is defined in exactly one place.
struct FeedButton: View {
    enum Kind {
        /// Transparent pill that lights up on hover/selection. Used
        /// for filter bar pills and single-select option pills.
        case ghost
        /// Soft neutral fill (e.g. "Manually Approve", disabled Submit).
        case soft
        /// Dark background with white text (Deny).
        case dark
        /// Light background with black text (Allow Once).
        case light
        /// Solid blue (Always Allow, Send feedback, active Submit).
        case primary
        /// Solid green (checked multi-select option, confirmations).
        case success
        /// Solid orange (Auto-accept Edits).
        case warning
        /// Solid red (Bypass, destructive deny).
        case destructive
    }

    enum Size {
        case compact  // filter bar / option pills
        case medium   // full-width CTAs
    }

    let label: String
    var leadingIcon: String? = nil
    var trailingIcon: String? = nil
    var kind: Kind = .ghost
    var size: Size = .compact
    var fullWidth: Bool = false
    var isSelected: Bool = false
    var dimmed: Bool = false
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button {
            // `dimmed` doubles as the disabled signal — swallow the
            // click at the primitive so upstream action closures don't
            // have to re-check.
            guard !dimmed else { return }
            action()
        } label: {
            HStack(spacing: iconSpacing) {
                if let leadingIcon {
                    Image(systemName: leadingIcon)
                        .font(.system(size: iconSize, weight: .medium))
                }
                Text(label)
                    .font(.system(size: labelSize, weight: .medium))
                if let trailingIcon {
                    Image(systemName: trailingIcon)
                        .font(.system(size: iconSize, weight: .medium))
                }
            }
            .foregroundColor(foreground)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundFill)
            )
            .opacity(dimmed ? 0.55 : 1.0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            // Only swap the cursor when the button is disabled —
            // enabled buttons keep the default arrow so the Feed
            // feels like the rest of the app. Pop on mouseout so a
            // stale "not allowed" cursor doesn't stick.
            if dimmed, hovering {
                NSCursor.operationNotAllowed.push()
            } else if dimmed, !hovering {
                NSCursor.pop()
            }
        }
        .help(label)
    }

    // MARK: - Style resolution

    private var labelSize: CGFloat { size == .compact ? 10.5 : 11 }
    private var iconSize: CGFloat { size == .compact ? 9 : 10 }
    private var iconSpacing: CGFloat { size == .compact ? 3 : 5 }
    private var cornerRadius: CGFloat { size == .compact ? 5 : 6 }
    private var horizontalPadding: CGFloat { size == .compact ? 8 : 12 }
    private var verticalPadding: CGFloat { size == .compact ? 4 : 5 }

    private var foreground: Color {
        switch kind {
        case .ghost:
            return isSelected ? .primary : .primary.opacity(0.85)
        case .soft: return .primary
        case .dark: return .white
        case .light: return .black
        case .primary: return .white
        case .success: return .white
        case .warning: return .white
        case .destructive: return .white
        }
    }

    private var backgroundFill: Color {
        switch kind {
        case .ghost:
            if isSelected { return Color.primary.opacity(0.12) }
            if isHovered { return Color.primary.opacity(0.06) }
            return Color.clear
        case .soft:
            return isHovered ? Color.primary.opacity(0.16) : Color.primary.opacity(0.10)
        case .dark:
            return isHovered ? Color.black.opacity(0.85) : Color.black.opacity(0.75)
        case .light:
            return isHovered ? Color.white.opacity(0.96) : Color.white.opacity(0.88)
        case .primary:
            return isHovered
                ? Color(red: 0.28, green: 0.55, blue: 0.95)
                : Color(red: 0.24, green: 0.48, blue: 0.88)
        case .success:
            return isHovered
                ? Color(red: 0.22, green: 0.72, blue: 0.42)
                : Color(red: 0.18, green: 0.62, blue: 0.35)
        case .warning:
            return isHovered
                ? Color(red: 0.95, green: 0.55, blue: 0.18)
                : Color(red: 0.92, green: 0.54, blue: 0.29)
        case .destructive:
            return isHovered
                ? Color(red: 0.85, green: 0.28, blue: 0.28)
                : Color(red: 0.75, green: 0.22, blue: 0.22)
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
                    FeedButton(
                        label: hasFeedback
                            ? String(localized: "feed.exitplan.refine",
                                     defaultValue: "Send feedback")
                            : String(localized: "feed.exitplan.manual",
                                     defaultValue: "Manually Approve"),
                        kind: hasFeedback ? .primary : .soft,
                        size: .medium, fullWidth: true
                    ) {
                        // Feedback always wins over mode; hook translates
                        // non-empty feedback into block+reason.
                        onApprove(.manual, hasFeedback ? trimmedFeedback : nil)
                    }
                    FeedButton(
                        label: String(localized: "feed.exitplan.autoaccept",
                                      defaultValue: "Auto-accept Edits"),
                        kind: .warning,
                        size: .medium, fullWidth: true,
                        dimmed: hasFeedback
                    ) {
                        onApprove(.autoAccept, hasFeedback ? trimmedFeedback : nil)
                    }
                    FeedButton(
                        label: String(localized: "feed.exitplan.bypass",
                                      defaultValue: "Bypass Permissions"),
                        kind: .destructive,
                        size: .medium, fullWidth: true,
                        dimmed: hasFeedback
                    ) {
                        onApprove(.bypassPermissions, hasFeedback ? trimmedFeedback : nil)
                    }
                }
            } else if let badge = submittedBadge {
                FeedButton(
                    label: badge,
                    leadingIcon: "checkmark",
                    kind: .success,
                    size: .medium,
                    fullWidth: true,
                    dimmed: true
                ) {}
            }
        }
    }

    private var submittedBadge: String? {
        guard case .resolved(let decision, _) = status else { return nil }
        let submitted = String(localized: "feed.badge.submitted", defaultValue: "Submitted")
        switch decision {
        case .exitPlan(let mode, let feedback):
            if let feedback, !feedback.isEmpty {
                return "\(submitted) · " + String(
                    localized: "feed.badge.refined", defaultValue: "refined"
                )
            }
            return "\(submitted) · \(mode.displayLabel)"
        default:
            return submitted
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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.95))
                        .padding(.top, 2)
                case .paragraph(let text):
                    Text(text)
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                case .numbered(let items):
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 5) {
                                Text("\(item.index).")
                                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                                    .foregroundColor(.secondary)
                                Text(item.text)
                                    .font(.system(size: 11))
                                    .foregroundColor(.primary.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                case .bulleted(let items):
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 5) {
                                Text("·")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Color.blue.opacity(0.8))
                                Text(item)
                                    .font(.system(size: 11))
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

private struct QuestionActionArea: View {
    let questions: [WorkstreamQuestionPrompt]
    let status: WorkstreamStatus
    let onReply: ([String]) -> Void

    // Per-question selections keyed by question id.
    @State private var selections: [String: Set<String>] = [:]
    // Per-question "Type something…" free-form answers. When
    // non-empty, wins over preset option selections for that
    // question — mirrors Claude's TUI fallback.
    @State private var freeTexts: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerLine
            if shouldRenderLongForm, let q = questions.first {
                longFormBlock(question: q)
            } else {
                ForEach(Array(questions.enumerated()), id: \.offset) { idx, q in
                    questionBlock(index: idx + 1, question: q)
                }
            }
            submitCTA
        }
    }

    private var shouldRenderLongForm: Bool {
        // Long-form: single question whose options carry descriptions
        // (e.g. Claude's AskUserQuestion with `header` + per-option
        // detail). Multi-option list with a bigger rich-text card per
        // option, click-to-select.
        guard questions.count == 1, let q = questions.first else { return false }
        return q.options.contains { $0.description?.isEmpty == false }
    }

    private var headerLine: some View {
        HStack(spacing: 5) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 10))
                .foregroundColor(.blue)
            Text(String(localized: "feed.question.header", defaultValue: "Claude's Question"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.blue)
            if questions.count > 1 {
                Text(String(
                    localized: "feed.question.count",
                    defaultValue: "(\(questions.count) questions)"
                ))
                    .font(.system(size: 10))
                    .foregroundColor(.blue.opacity(0.7))
            }
        }
    }

    /// Long-form rendering: single question with rich options. Each
    /// option becomes a tappable card with numbered index, title, and
    /// description. Selecting immediately submits (no separate Submit
    /// button required).
    @ViewBuilder
    private func longFormBlock(question: WorkstreamQuestionPrompt) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header = question.header, !header.isEmpty {
                Text("[\(header)] ")
                    .foregroundColor(.blue)
                + Text(question.prompt)
                    .foregroundColor(.primary.opacity(0.95))
            } else if !question.prompt.isEmpty {
                Text(question.prompt)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.95))
            }
            ForEach(Array(question.options.enumerated()), id: \.offset) { idx, option in
                longFormOptionCard(
                    questionId: question.id,
                    index: idx + 1,
                    option: option
                )
            }
            if status.isPending {
                freeFormField(questionId: question.id)
            }
        }
    }

    private func longFormOptionCard(
        questionId: String,
        index: Int,
        option: WorkstreamQuestionOption
    ) -> some View {
        Button {
            guard status.isPending else { return }
            // Long-form is always single-select, and selecting submits
            // immediately because there's no separate Submit button.
            // Selections carry human-readable labels (not ids) so the
            // hook can paste them straight into the agent's reply.
            onReply([option.label])
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text("\(index)")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color(red: 0.24, green: 0.48, blue: 0.88))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                    if let description = option.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!status.isPending)
    }

    private func questionBlock(index: Int, question: WorkstreamQuestionPrompt) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 5) {
                Text("\(index).")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundColor(.blue)
                Text(question.prompt)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if question.multiSelect {
                HStack(spacing: 3) {
                    Image(systemName: "checklist")
                        .font(.system(size: 8, weight: .medium))
                    Text(String(localized: "feed.question.multiSelect", defaultValue: "Multi-select"))
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.3)
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.orange.opacity(0.18))
                )
            }
            if question.options.isEmpty {
                Text(String(localized: "feed.question.noOptions",
                            defaultValue: "Agent provided no options."))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            } else {
                WrapHStack(spacing: 6) {
                    ForEach(question.options, id: \.id) { option in
                        optionPill(questionId: question.id, option: option, multi: question.multiSelect)
                    }
                }
            }
            if status.isPending {
                freeFormField(questionId: question.id)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    /// "Type something…" free-form text field — mirrors Claude's TUI
    /// option 4 (custom answer). When non-empty it wins over the
    /// preset option selection for that question on submit.
    private func freeFormField(questionId: String) -> some View {
        let binding = Binding<String>(
            get: { freeTexts[questionId] ?? "" },
            set: { freeTexts[questionId] = $0 }
        )
        return TextField(
            String(localized: "feed.question.typeSomething",
                   defaultValue: "Type something…"),
            text: binding,
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(.system(size: 11))
        .lineLimit(1...4)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }

    private func optionPill(
        questionId: String,
        option: WorkstreamQuestionOption,
        multi: Bool
    ) -> some View {
        let selected = selections[questionId]?.contains(option.id) == true
        let leading: String? = multi
            ? (selected ? "checkmark.square.fill" : "square")
            : nil
        let selectedKind: FeedButton.Kind = multi ? .success : .primary
        return FeedButton(
            label: option.label,
            leadingIcon: leading,
            kind: selected ? selectedKind : .soft,
            size: .compact,
            dimmed: !status.isPending
        ) {
            guard status.isPending else { return }
            var current = selections[questionId] ?? []
            if multi {
                if current.contains(option.id) { current.remove(option.id) }
                else { current.insert(option.id) }
            } else {
                current = [option.id]
            }
            selections[questionId] = current
        }
    }

    /// One answer string per question: the user's free-form text if
    /// they typed any, otherwise the labels of the selected options
    /// joined by ", ". Questions with no answer are omitted entirely
    /// so the agent doesn't see "question 2: <empty>".
    private var composedAnswers: [String] {
        var out: [String] = []
        for q in questions {
            let freeText = (freeTexts[q.id] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !freeText.isEmpty {
                out.append(freeText)
                continue
            }
            guard let ids = selections[q.id], !ids.isEmpty else { continue }
            let labels = q.options
                .filter { ids.contains($0.id) }
                .map(\.label)
            if !labels.isEmpty {
                out.append(labels.joined(separator: ", "))
            }
        }
        return out
    }

    private var hasAnyAnswer: Bool { !composedAnswers.isEmpty }

    private var canSubmitEmptyAnswer: Bool {
        !questions.isEmpty && questions.allSatisfy { $0.options.isEmpty }
    }

    private var submitCTA: some View {
        let isPending = status.isPending
        let enabled = isPending && (hasAnyAnswer || canSubmitEmptyAnswer)
        return FeedButton(
            label: isPending
                ? String(localized: "feed.question.submitAll",
                         defaultValue: "Submit All Answers")
                : String(localized: "feed.badge.submitted",
                         defaultValue: "Submitted"),
            leadingIcon: isPending ? "checkmark.circle.fill" : "checkmark",
            kind: enabled ? .primary : (isPending ? .soft : .success),
            size: .medium,
            fullWidth: true,
            dimmed: !enabled
        ) {
            // Selections carry human-readable answer strings (one per
            // answered question) so the hook can feed them straight
            // back to the agent as the user's reply.
            onReply(composedAnswers)
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

/// Renders a Stop event (Claude finished a turn and is waiting for
/// the next user prompt). Shows a text field + Send button that
/// types the reply into the agent's terminal surface and presses
/// Return — so the user can reply without switching focus.
private struct StopActionArea: View {
    let workstreamId: String
    let onSend: (String) -> Void

    @State private var reply: String = ""

    private var trimmed: String {
        reply.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canSend: Bool { !trimmed.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(String(localized: "feed.stop.label", defaultValue: "Claude finished — reply to continue"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            TextField(
                String(localized: "feed.stop.placeholder", defaultValue: "Reply to Claude…"),
                text: $reply,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .lineLimit(1...5)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(canSend ? 0.25 : 0.10), lineWidth: 1)
            )
            .onSubmit {
                if canSend {
                    onSend(trimmed)
                    reply = ""
                }
            }
            FeedButton(
                label: String(localized: "feed.stop.send", defaultValue: "Send to Claude"),
                leadingIcon: "arrow.up.circle.fill",
                kind: canSend ? .primary : .soft,
                size: .medium,
                fullWidth: true,
                dimmed: !canSend
            ) {
                onSend(trimmed)
                reply = ""
            }
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
            let status = err
                ? String(localized: "feed.telemetry.error", defaultValue: "error")
                : String(localized: "feed.telemetry.ok", defaultValue: "ok")
            return "\(name) \(status) \(json)"
        case .userPrompt(let text), .assistantMessage(let text):
            return text
        case .sessionStart:
            return String(localized: "feed.telemetry.sessionStart", defaultValue: "session start")
        case .sessionEnd:
            return String(localized: "feed.telemetry.sessionEnd", defaultValue: "session end")
        case .stop(let reason):
            let label = String(localized: "feed.telemetry.stop", defaultValue: "stop")
            guard let reason, !reason.isEmpty else { return label }
            return "\(label) \(reason)"
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
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(String(localized: "feed.todos.title", defaultValue: "Tasks"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.9))
                Text(summaryLabel)
                    .font(.system(size: 10))
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
                        Text(String(
                            localized: "feed.todos.moreCompleted",
                            defaultValue: "... +\(done.count - visibleDone.count) completed"
                        ))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                            .padding(.leading, 22)
                    }
                    .buttonStyle(.plain)
                }
                if expanded && done.count > 2 {
                    Button { expanded = false } label: {
                        Text(String(localized: "feed.todos.collapse", defaultValue: "Collapse"))
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
        if d > 0 {
            parts.append(String(localized: "feed.todos.summary.done", defaultValue: "\(d) done"))
        }
        if ip > 0 {
            parts.append(String(localized: "feed.todos.summary.inProgress", defaultValue: "\(ip) in progress"))
        }
        if p > 0 {
            parts.append(String(localized: "feed.todos.summary.open", defaultValue: "\(p) open"))
        }
        return "(" + parts.joined(separator: ", ") + ")"
    }

    @ViewBuilder
    private func row(_ todo: WorkstreamTaskTodo) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol(for: todo.state))
                .font(.system(size: 11, weight: .medium))
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
        case .inProgress: return "circle.fill"
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

/// Dashed separator between pending items and resolved ones.
private struct ResolvedDivider: View {
    var body: some View {
        HStack(spacing: 8) {
            line
            Text(String(localized: "feed.divider.resolved", defaultValue: "Resolved"))
                .font(.system(size: 10, weight: .medium))
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
        case .todos: return "checklist"
        }
    }
}
