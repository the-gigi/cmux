import CoreGraphics
import CoreText
import Foundation

public struct CodexTrajectoryTextRange: Codable, Hashable, Sendable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = max(0, location)
        self.length = max(0, length)
    }

    public var upperBound: Int {
        location + length
    }
}

public struct CodexTrajectoryLayoutConfiguration: Hashable, Sendable {
    public var width: CGFloat
    public var pageLineLimit: Int
    public var maximumPageCharacters: Int

    public init(
        width: CGFloat,
        pageLineLimit: Int = 240,
        maximumPageCharacters: Int = 16_384
    ) {
        self.width = max(1, width)
        self.pageLineLimit = max(1, pageLineLimit)
        self.maximumPageCharacters = max(1, maximumPageCharacters)
    }
}

public struct CodexTrajectoryLayoutPage: Hashable {
    public var blockID: String
    public var blockKind: CodexTrajectoryBlockKind
    public var pageIndex: Int
    public var textRange: CodexTrajectoryTextRange
    public var measuredSize: CGSize
    public var lineCount: Int

    public init(
        blockID: String,
        blockKind: CodexTrajectoryBlockKind,
        pageIndex: Int,
        textRange: CodexTrajectoryTextRange,
        measuredSize: CGSize,
        lineCount: Int
    ) {
        self.blockID = blockID
        self.blockKind = blockKind
        self.pageIndex = pageIndex
        self.textRange = textRange
        self.measuredSize = measuredSize
        self.lineCount = lineCount
    }
}

public struct CodexTrajectoryBlockLayout: Hashable {
    public var blockID: String
    public var pages: [CodexTrajectoryLayoutPage]
    public var totalHeight: CGFloat

    public init(blockID: String, pages: [CodexTrajectoryLayoutPage]) {
        self.blockID = blockID
        self.pages = pages
        self.totalHeight = pages.reduce(0) { $0 + $1.measuredSize.height }
    }
}

public struct CodexTrajectoryLayoutEngine {
    public init() {}

    public func layout(
        block: CodexTrajectoryBlock,
        configuration: CodexTrajectoryLayoutConfiguration,
        theme: CodexTrajectoryTheme
    ) -> CodexTrajectoryBlockLayout {
        let displayText = block.displayText.isEmpty ? " " : block.displayText
        let ranges = pageRanges(
            in: displayText,
            pageLineLimit: configuration.pageLineLimit,
            maximumPageCharacters: configuration.maximumPageCharacters
        )
        let style = theme.style(for: block.kind)
        let textWidth = max(1, configuration.width - theme.contentInsets.left - theme.contentInsets.right)

        let pages = ranges.enumerated().map { pageIndex, range in
            let text = displayText.codexTrajectorySubstring(in: range)
            let measured = measure(
                text: text.isEmpty ? " " : text,
                style: style,
                width: textWidth,
                insets: theme.contentInsets
            )
            return CodexTrajectoryLayoutPage(
                blockID: block.id,
                blockKind: block.kind,
                pageIndex: pageIndex,
                textRange: range,
                measuredSize: measured,
                lineCount: max(1, text.filter { $0 == "\n" }.count + 1)
            )
        }

        return CodexTrajectoryBlockLayout(blockID: block.id, pages: pages)
    }

    private func measure(
        text: String,
        style: CodexTrajectoryBlockStyle,
        width: CGFloat,
        insets: CodexTrajectoryInsets
    ) -> CGSize {
        let attributed = makeAttributedString(text: text, style: style)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
            nil
        )
        let lineHeight = ceil(CTFontGetAscent(style.font) + CTFontGetDescent(style.font) + CTFontGetLeading(style.font))
        return CGSize(
            width: width + insets.left + insets.right,
            height: max(lineHeight, ceil(suggested.height)) + insets.top + insets.bottom
        )
    }

    private func pageRanges(
        in text: String,
        pageLineLimit: Int,
        maximumPageCharacters: Int
    ) -> [CodexTrajectoryTextRange] {
        guard !text.isEmpty else {
            return [CodexTrajectoryTextRange(location: 0, length: 0)]
        }

        var ranges: [CodexTrajectoryTextRange] = []
        var start = 0
        var current = 0
        var lines = 1
        var characters = 0

        for character in text {
            current += 1
            characters += 1
            if character == "\n" {
                lines += 1
            }

            if lines >= pageLineLimit || characters >= maximumPageCharacters {
                ranges.append(CodexTrajectoryTextRange(location: start, length: current - start))
                start = current
                lines = 1
                characters = 0
            }
        }

        if start < current {
            ranges.append(CodexTrajectoryTextRange(location: start, length: current - start))
        }

        return ranges
    }
}

func makeAttributedString(text: String, style: CodexTrajectoryBlockStyle) -> CFAttributedString {
    let attributes: [CFString: Any] = [
        kCTFontAttributeName: style.font,
        kCTForegroundColorAttributeName: style.foregroundColor,
    ]
    return CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attributes as CFDictionary)
}

extension String {
    func codexTrajectorySubstring(in range: CodexTrajectoryTextRange) -> String {
        guard range.length > 0 else { return "" }
        let lower = index(startIndex, offsetBy: range.location, limitedBy: endIndex) ?? endIndex
        let upper = index(lower, offsetBy: range.length, limitedBy: endIndex) ?? endIndex
        return String(self[lower..<upper])
    }
}
