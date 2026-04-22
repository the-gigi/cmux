import CoreGraphics
import CoreText

public struct CodexTrajectoryBlockStyle {
    public var font: CTFont
    public var foregroundColor: CGColor
    public var backgroundColor: CGColor?

    public init(font: CTFont, foregroundColor: CGColor, backgroundColor: CGColor? = nil) {
        self.font = font
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
    }
}

public struct CodexTrajectoryTheme {
    public var identifier: String
    public var contentInsets: CodexTrajectoryInsets
    public var stylesByKind: [CodexTrajectoryBlockKind: CodexTrajectoryBlockStyle]
    public var fallbackStyle: CodexTrajectoryBlockStyle

    public init(
        identifier: String,
        contentInsets: CodexTrajectoryInsets = CodexTrajectoryInsets(top: 6, left: 8, bottom: 6, right: 8),
        stylesByKind: [CodexTrajectoryBlockKind: CodexTrajectoryBlockStyle],
        fallbackStyle: CodexTrajectoryBlockStyle
    ) {
        self.identifier = identifier
        self.contentInsets = contentInsets
        self.stylesByKind = stylesByKind
        self.fallbackStyle = fallbackStyle
    }

    public func style(for kind: CodexTrajectoryBlockKind) -> CodexTrajectoryBlockStyle {
        stylesByKind[kind] ?? fallbackStyle
    }

    public static func defaultLight(
        textSize: CGFloat = 13,
        monospacedSize: CGFloat = 12
    ) -> CodexTrajectoryTheme {
        let textFont = CTFontCreateUIFontForLanguage(.system, textSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, textSize, nil)
        let monospacedFont = CTFontCreateUIFontForLanguage(.userFixedPitch, monospacedSize, nil)
            ?? CTFontCreateWithName("Menlo" as CFString, monospacedSize, nil)
        let primary = CGColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1)
        let muted = CGColor(red: 0.32, green: 0.32, blue: 0.32, alpha: 1)
        let error = CGColor(red: 0.72, green: 0.08, blue: 0.08, alpha: 1)
        let commandBackground = CGColor(red: 0.96, green: 0.96, blue: 0.95, alpha: 1)
        let fallback = CodexTrajectoryBlockStyle(font: textFont, foregroundColor: primary)

        return CodexTrajectoryTheme(
            identifier: "default-light-\(textSize)-\(monospacedSize)",
            stylesByKind: [
                .userText: CodexTrajectoryBlockStyle(font: textFont, foregroundColor: primary),
                .assistantText: CodexTrajectoryBlockStyle(font: textFont, foregroundColor: primary),
                .commandOutput: CodexTrajectoryBlockStyle(
                    font: monospacedFont,
                    foregroundColor: primary,
                    backgroundColor: commandBackground
                ),
                .toolCall: CodexTrajectoryBlockStyle(font: monospacedFont, foregroundColor: muted),
                .fileChange: CodexTrajectoryBlockStyle(font: monospacedFont, foregroundColor: primary),
                .approvalRequest: CodexTrajectoryBlockStyle(font: textFont, foregroundColor: primary),
                .status: CodexTrajectoryBlockStyle(font: textFont, foregroundColor: muted),
                .stderr: CodexTrajectoryBlockStyle(font: monospacedFont, foregroundColor: error),
                .systemEvent: CodexTrajectoryBlockStyle(font: textFont, foregroundColor: muted),
            ],
            fallbackStyle: fallback
        )
    }
}
