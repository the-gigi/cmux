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

struct RightSidebarFocusRequest: Equatable {
    let generation: Int
    let windowNumber: Int?
    let mode: RightSidebarMode?
}

enum RightSidebarFocusRequestCenter {
    static let notificationName = Notification.Name("cmux.rightSidebarFocusRequested")

    private static var generation = 0
    private static var latestRequest: RightSidebarFocusRequest?

    static func requestFocus(mode: RightSidebarMode?, in window: NSWindow?) {
        generation &+= 1
        let request = RightSidebarFocusRequest(
            generation: generation,
            windowNumber: window?.windowNumber,
            mode: mode
        )
        latestRequest = request

        var userInfo: [AnyHashable: Any] = ["generation": request.generation]
        if let windowNumber = request.windowNumber {
            userInfo["windowNumber"] = windowNumber
        }
        if let mode = request.mode {
            userInfo["mode"] = mode.rawValue
        }
        NotificationCenter.default.post(name: notificationName, object: nil, userInfo: userInfo)
    }

    static func request(from notification: Notification) -> RightSidebarFocusRequest? {
        guard let generation = notification.userInfo?["generation"] as? Int else { return nil }
        let rawMode = notification.userInfo?["mode"] as? String
        return RightSidebarFocusRequest(
            generation: generation,
            windowNumber: notification.userInfo?["windowNumber"] as? Int,
            mode: rawMode.flatMap(RightSidebarMode.init(rawValue:))
        )
    }

    static func latestRequest(for window: NSWindow?) -> RightSidebarFocusRequest? {
        guard let latestRequest else { return nil }
        if let targetWindowNumber = latestRequest.windowNumber {
            guard window?.windowNumber == targetWindowNumber else { return nil }
        }
        return latestRequest
    }

    static func modeShortcut(for event: NSEvent) -> RightSidebarMode? {
        guard event.type == .keyDown else { return nil }
        if KeyboardShortcutSettings.shortcut(for: .switchRightSidebarToFiles).matches(event: event) {
            return .files
        }
        if KeyboardShortcutSettings.shortcut(for: .switchRightSidebarToSessions).matches(event: event) {
            return .sessions
        }
        if KeyboardShortcutSettings.shortcut(for: .switchRightSidebarToFeed).matches(event: event) {
            return .feed
        }
        return nil
    }

    static func focusedModeShortcut(for event: NSEvent, in window: NSWindow?) -> RightSidebarMode? {
        guard ownsKeyboardFocus(in: window) else { return nil }
        return modeShortcut(for: event)
    }

    static func isRightSidebarFocusResponder(_ responder: NSResponder, in window: NSWindow?) -> Bool {
        guard let window else { return false }
        if RightSidebarKeyboardFocusView.isFocusHost(responder, in: window) {
            return true
        }
        if responder is FileExplorerNSOutlineView ||
            responder is SessionIndexKeyboardFocusView ||
            responder is FeedKeyboardFocusView {
            return true
        }
        return false
    }

    private static func ownsKeyboardFocus(in window: NSWindow?) -> Bool {
        guard let window, let responder = window.firstResponder else { return false }
        return isRightSidebarFocusResponder(responder, in: window)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RightSidebarKeyboardFocusBridge { request in
                handleFocusRequest(request)
            }
            .frame(width: 1, height: 1)
        )
        .accessibilityIdentifier("RightSidebar")
    }

    private var modeBar: some View {
        HStack(spacing: 4) {
            ForEach(RightSidebarMode.allCases, id: \.rawValue) { mode in
                ModeBarButton(
                    mode: mode,
                    isSelected: fileExplorerState.mode == mode,
                    badgeCount: mode == .feed ? feedPendingCount : 0
                ) {
                    selectMode(mode)
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

    @discardableResult
    private func handleFocusRequest(_ request: RightSidebarFocusRequest) -> Bool {
        let targetMode = request.mode ?? fileExplorerState.mode
        selectMode(targetMode)
        return focusMode(targetMode, windowNumber: request.windowNumber)
    }

    private func selectMode(_ mode: RightSidebarMode) {
        if fileExplorerState.mode != mode {
            fileExplorerState.mode = mode
        }
        if mode == .sessions {
            sessionIndexStore.setCurrentDirectoryIfChanged(sessionIndexDirectory)
            if sessionIndexStore.entries.isEmpty {
                sessionIndexStore.reload()
            }
        }
    }

    @discardableResult
    private func focusMode(_ mode: RightSidebarMode, windowNumber: Int?) -> Bool {
        let window = windowNumber.flatMap { NSApp.window(withWindowNumber: $0) }
            ?? NSApp.keyWindow
            ?? NSApp.mainWindow
        switch mode {
        case .files:
            if FileExplorerContainerView.focus(in: window) {
                return true
            }
            FileExplorerFocusRequestCenter.requestFocus(in: window)
            return RightSidebarKeyboardFocusView.focusHost(in: window)
        case .sessions:
            SessionIndexFocusRequestCenter.requestFocus(in: window)
            return SessionIndexKeyboardFocusView.focusHost(in: window) ||
                RightSidebarKeyboardFocusView.focusHost(in: window)
        case .feed:
            FeedFocusRequestCenter.requestFirstItemFocus(in: window)
            return FeedKeyboardFocusView.focusHost(in: window)
        }
    }
}

private struct RightSidebarKeyboardFocusBridge: NSViewRepresentable {
    let onFocusRequest: (RightSidebarFocusRequest) -> Bool

    func makeNSView(context: Context) -> RightSidebarKeyboardFocusView {
        let view = RightSidebarKeyboardFocusView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        view.onFocusRequest = onFocusRequest
        return view
    }

    func updateNSView(_ nsView: RightSidebarKeyboardFocusView, context: Context) {
        nsView.onFocusRequest = onFocusRequest
        nsView.replayPendingFocusRequestIfNeeded()
    }
}

private final class RightSidebarKeyboardFocusView: NSView {
    private static let hosts = NSMapTable<NSWindow, RightSidebarKeyboardFocusView>(
        keyOptions: .weakMemory,
        valueOptions: .weakMemory
    )

    var onFocusRequest: ((RightSidebarFocusRequest) -> Bool)?
    private var focusRequestObserver: NSObjectProtocol?
    private var handledFocusRequestGeneration = 0

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    deinit {
        if let focusRequestObserver {
            NotificationCenter.default.removeObserver(focusRequestObserver)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        Self.hosts.setObject(self, forKey: window)
        installFocusRequestObserverIfNeeded()
        replayPendingFocusRequestIfNeeded()
    }

    override func keyDown(with event: NSEvent) {
        if let mode = RightSidebarFocusRequestCenter.modeShortcut(for: event) {
            RightSidebarFocusRequestCenter.requestFocus(mode: mode, in: window)
            return
        }
        if event.keyCode == 53 {
            window?.makeFirstResponder(nil)
            return
        }
        if let characters = event.charactersIgnoringModifiers, !characters.isEmpty {
            return
        }
        super.keyDown(with: event)
    }

    static func focusHost(in window: NSWindow?) -> Bool {
        guard let window, let host = hosts.object(forKey: window) else { return false }
        guard host.cmuxCanAcceptRightSidebarKeyboardFocus else { return false }
        return window.makeFirstResponder(host)
    }

    static func isFocusHost(_ responder: NSResponder, in window: NSWindow?) -> Bool {
        guard let window, let host = hosts.object(forKey: window) else { return false }
        return responder === host
    }

    private func installFocusRequestObserverIfNeeded() {
        guard focusRequestObserver == nil else { return }
        focusRequestObserver = NotificationCenter.default.addObserver(
            forName: RightSidebarFocusRequestCenter.notificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let request = RightSidebarFocusRequestCenter.request(from: notification),
                  self.shouldHandleFocusRequest(request)
            else { return }
            self.handleFocusRequest(request)
        }
    }

    fileprivate func replayPendingFocusRequestIfNeeded() {
        guard let request = RightSidebarFocusRequestCenter.latestRequest(for: window),
              shouldHandleFocusRequest(request) else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.shouldHandleFocusRequest(request) else { return }
            self.handleFocusRequest(request)
        }
    }

    private func handleFocusRequest(_ request: RightSidebarFocusRequest) {
        guard handledFocusRequestGeneration != request.generation else { return }
        guard cmuxCanAcceptRightSidebarKeyboardFocus else { return }
        if onFocusRequest?(request) == true {
            handledFocusRequestGeneration = request.generation
        }
    }

    private func shouldHandleFocusRequest(_ request: RightSidebarFocusRequest) -> Bool {
        if let windowNumber = request.windowNumber {
            return window?.windowNumber == windowNumber
        }
        return window != nil
    }
}

extension NSView {
    var cmuxCanAcceptRightSidebarKeyboardFocus: Bool {
        guard window != nil, !isHiddenOrHasHiddenAncestor else { return false }
        var view: NSView? = self
        while let current = view {
            if current.bounds.width <= 0.5 || current.bounds.height <= 0.5 {
                return false
            }
            view = current.superview
        }
        return true
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
                    .lineLimit(1)
                    .truncationMode(.tail)
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
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
            .foregroundColor(.orange)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.orange.opacity(0.20))
            )
            .fixedSize(horizontal: true, vertical: true)
            .layoutPriority(2)
    }
}
