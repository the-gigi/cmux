import SwiftUI
import Foundation

/// View that renders the appropriate panel view based on panel type
struct PanelContentView: View {
    let panel: any Panel
    let paneId: PaneID
    let isFocused: Bool
    let isSelectedInPane: Bool
    let isVisibleInUI: Bool
    let portalPriority: Int
    let isSplit: Bool
    let appearance: PanelAppearance
    let hasUnreadNotification: Bool
    let onFocus: () -> Void
    let onRequestPanelFocus: () -> Void
    let onTriggerFlash: () -> Void

    var body: some View {
        switch panel.panelType {
        case .terminal:
            Color.clear
                .onAppear {
                    assertionFailure("Terminal panels should render via the AppKit split host")
                }
        case .browser:
            Color.clear
                .onAppear {
                    assertionFailure("Browser panels should render via the AppKit split host")
                }
        case .markdown:
            if let markdownPanel = panel as? MarkdownPanel {
                MarkdownPanelView(
                    panel: markdownPanel,
                    isFocused: isFocused,
                    isVisibleInUI: isVisibleInUI,
                    portalPriority: portalPriority,
                    onRequestPanelFocus: onRequestPanelFocus
                )
            }
        }
    }
}
