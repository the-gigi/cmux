import AppKit
import CMUXWorkstream
import Observation
import SwiftUI

/// Mode shown in the right sidebar (the panel toggled by ⌘⌥B).
enum RightSidebarMode: String, CaseIterable {
    case files
    case sessions
    case feed

    var label: String {
        switch self {
        case .files: return String(localized: "rightSidebar.mode.files", defaultValue: "Files")
        case .sessions: return String(localized: "rightSidebar.mode.sessions", defaultValue: "Sessions")
        case .feed: return String(localized: "rightSidebar.mode.feed", defaultValue: "Feed")
        }
    }

    var symbolName: String {
        switch self {
        case .files: return "folder"
        case .sessions: return "bubble.left.and.text.bubble.right"
        case .feed: return "dot.radiowaves.left.and.right"
        }
    }
}

/// Right sidebar root view. Hosts a segmented mode picker plus the active panel.
struct RightSidebarPanelView: View {
    @ObservedObject var fileExplorerStore: FileExplorerStore
    @ObservedObject var fileExplorerState: FileExplorerState
    @ObservedObject var sessionIndexStore: SessionIndexStore
    let onResumeSession: ((SessionEntry) -> Void)?

    // Re-reading the observable store inside modeBar causes SwiftUI to
    // track the pending count so the badge updates live when hooks push
    // new items.
    private var feedPendingCount: Int {
        FeedCoordinator.shared.store?.pending.count ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            modeBar
            Divider()
            contentForMode
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var modeBar: some View {
        HStack(spacing: 4) {
            ForEach(RightSidebarMode.allCases, id: \.rawValue) { mode in
                ModeBarButton(
                    mode: mode,
                    isSelected: fileExplorerState.mode == mode,
                    badgeCount: mode == .feed ? feedPendingCount : 0
                ) {
                    if fileExplorerState.mode != mode {
                        fileExplorerState.mode = mode
                        if mode == .sessions {
                            sessionIndexStore.setCurrentDirectoryIfChanged(sessionIndexDirectory)
                            if sessionIndexStore.entries.isEmpty {
                                sessionIndexStore.reload()
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .frame(height: 31)
    }

    @ViewBuilder
    private var contentForMode: some View {
        switch fileExplorerState.mode {
        case .files:
            FileExplorerPanelView(store: fileExplorerStore, state: fileExplorerState)
        case .sessions:
            SessionIndexView(store: sessionIndexStore, onResume: onResumeSession)
                .onAppear {
                    sessionIndexStore.setCurrentDirectoryIfChanged(sessionIndexDirectory)
                }
        case .feed:
            FeedPanelView()
        }
    }

    private var sessionIndexDirectory: String? {
        fileExplorerStore.rootPath.isEmpty ? nil : fileExplorerStore.rootPath
    }
}

private struct ModeBarButton: View {
    let mode: RightSidebarMode
    let isSelected: Bool
    var badgeCount: Int = 0
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: mode.symbolName)
                    .font(.system(size: 11, weight: .medium))
                Text(mode.label)
                    .font(.system(size: 11, weight: .medium))
                if badgeCount > 0 {
                    pendingChip
                }
            }
            .foregroundColor(isSelected ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(backgroundColor)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(helpText)
    }

    private var helpText: String {
        if badgeCount > 0 {
            return String(
                localized: "rightSidebar.mode.pendingHelp",
                defaultValue: "\(mode.label) · \(badgeCount) pending"
            )
        }
        return mode.label
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.primary.opacity(0.10)
        }
        if isHovered {
            return Color.primary.opacity(0.05)
        }
        return Color.clear
    }

    /// Subtle inline count chip that sits after the label instead of
    /// floating a red capsule over the icon. Tinted orange (the "needs
    /// attention" color used elsewhere in the Feed) and sized to match
    /// the label's typography.
    private var pendingChip: some View {
        let countText = badgeCount > 9 ? "9+" : String(badgeCount)
        return Text(countText)
            .font(.system(size: 10, weight: .bold).monospacedDigit())
            .foregroundColor(.orange)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.orange.opacity(0.20))
            )
    }
}
