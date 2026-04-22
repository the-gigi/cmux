#if DEBUG
import AppKit
import SwiftUI

enum FeedButtonDebugVisualStyle: String, CaseIterable, Identifiable {
    case solid
    case glass
    case outline
    case flat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .solid:
            return String(localized: "feed.buttonDebug.style.solid", defaultValue: "Solid")
        case .glass:
            return String(localized: "feed.buttonDebug.style.glass", defaultValue: "Raycast Glass")
        case .outline:
            return String(localized: "feed.buttonDebug.style.outline", defaultValue: "Outline")
        case .flat:
            return String(localized: "feed.buttonDebug.style.flat", defaultValue: "Flat")
        }
    }
}

enum FeedButtonDebugColorRole: String {
    case background
    case hoverBackground
    case foreground
}

enum FeedButtonDebugSettings {
    static let styleKey = "feed.button.debug.style"
    static let compactCornerRadiusKey = "feed.button.debug.compactCornerRadius"
    static let mediumCornerRadiusKey = "feed.button.debug.mediumCornerRadius"
    static let compactHorizontalPaddingKey = "feed.button.debug.compactHorizontalPadding"
    static let mediumHorizontalPaddingKey = "feed.button.debug.mediumHorizontalPadding"
    static let compactVerticalPaddingKey = "feed.button.debug.compactVerticalPadding"
    static let mediumVerticalPaddingKey = "feed.button.debug.mediumVerticalPadding"
    static let glassTintOpacityKey = "feed.button.debug.glassTintOpacity"
    static let borderWidthKey = "feed.button.debug.borderWidth"
    static let generationKey = "feed.button.debug.generation"

    private static let defaults = UserDefaults.standard

    static var visualStyle: FeedButtonDebugVisualStyle {
        FeedButtonDebugVisualStyle(
            rawValue: defaults.string(forKey: styleKey) ?? FeedButtonDebugVisualStyle.solid.rawValue
        ) ?? .solid
    }

    static var compactCornerRadius: Double {
        double(forKey: compactCornerRadiusKey, defaultValue: 5)
    }

    static var mediumCornerRadius: Double {
        double(forKey: mediumCornerRadiusKey, defaultValue: 6)
    }

    static var compactHorizontalPadding: Double {
        double(forKey: compactHorizontalPaddingKey, defaultValue: 8)
    }

    static var mediumHorizontalPadding: Double {
        double(forKey: mediumHorizontalPaddingKey, defaultValue: 12)
    }

    static var compactVerticalPadding: Double {
        double(forKey: compactVerticalPaddingKey, defaultValue: 4)
    }

    static var mediumVerticalPadding: Double {
        double(forKey: mediumVerticalPaddingKey, defaultValue: 5)
    }

    static var glassTintOpacity: Double {
        double(forKey: glassTintOpacityKey, defaultValue: 0.42)
    }

    static var borderWidth: Double {
        double(forKey: borderWidthKey, defaultValue: 0.9)
    }

    static func color(for kind: FeedButton.Kind, role: FeedButtonDebugColorRole) -> Color? {
        guard let raw = defaults.string(forKey: colorKey(kind: kind, role: role)),
              let nsColor = NSColor(hex: raw)
        else {
            return nil
        }
        return Color(nsColor: nsColor)
    }

    static func setColor(
        _ color: Color,
        for kind: FeedButton.Kind,
        role: FeedButtonDebugColorRole
    ) {
        defaults.set(NSColor(color).hexString(), forKey: colorKey(kind: kind, role: role))
        bumpGeneration()
    }

    static func defaultColor(
        for kind: FeedButton.Kind,
        role: FeedButtonDebugColorRole
    ) -> Color {
        Color(nsColor: NSColor(hex: defaultHex(kind: kind, role: role)) ?? .systemBlue)
    }

    static func applyRaycastGlassPreset() {
        defaults.set(FeedButtonDebugVisualStyle.glass.rawValue, forKey: styleKey)
        defaults.set(7.0, forKey: compactCornerRadiusKey)
        defaults.set(8.0, forKey: mediumCornerRadiusKey)
        defaults.set(9.0, forKey: compactHorizontalPaddingKey)
        defaults.set(12.0, forKey: mediumHorizontalPaddingKey)
        defaults.set(4.5, forKey: compactVerticalPaddingKey)
        defaults.set(6.0, forKey: mediumVerticalPaddingKey)
        defaults.set(0.38, forKey: glassTintOpacityKey)
        defaults.set(0.8, forKey: borderWidthKey)
        bumpGeneration()
    }

    static func reset() {
        let keys = [
            styleKey,
            compactCornerRadiusKey,
            mediumCornerRadiusKey,
            compactHorizontalPaddingKey,
            mediumHorizontalPaddingKey,
            compactVerticalPaddingKey,
            mediumVerticalPaddingKey,
            glassTintOpacityKey,
            borderWidthKey,
        ]
        for key in keys {
            defaults.removeObject(forKey: key)
        }
        for kind in FeedButton.Kind.allCases {
            for role in [
                FeedButtonDebugColorRole.background,
                .hoverBackground,
                .foreground,
            ] {
                defaults.removeObject(forKey: colorKey(kind: kind, role: role))
            }
        }
        bumpGeneration()
    }

    static func bumpGeneration() {
        defaults.set(defaults.integer(forKey: generationKey) + 1, forKey: generationKey)
    }

    private static func double(forKey key: String, defaultValue: Double) -> Double {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.double(forKey: key)
    }

    private static func colorKey(kind: FeedButton.Kind, role: FeedButtonDebugColorRole) -> String {
        "feed.button.debug.color.\(kind.rawValue).\(role.rawValue)"
    }

    private static func defaultHex(
        kind: FeedButton.Kind,
        role: FeedButtonDebugColorRole
    ) -> String {
        switch role {
        case .background:
            switch kind {
            case .ghost: return "#1F2933"
            case .soft: return "#3D4148"
            case .dark: return "#1F1F1F"
            case .light: return "#F3F4F6"
            case .primary: return "#3D7AE0"
            case .success: return "#2E9E59"
            case .warning: return "#EA894A"
            case .destructive: return "#BF3838"
            }
        case .hoverBackground:
            switch kind {
            case .ghost: return "#2E3744"
            case .soft: return "#4B515A"
            case .dark: return "#2B2B2B"
            case .light: return "#FFFFFF"
            case .primary: return "#478CF2"
            case .success: return "#38B86B"
            case .warning: return "#F28C2E"
            case .destructive: return "#D94747"
            }
        case .foreground:
            switch kind {
            case .light: return "#111111"
            case .ghost, .soft: return "#EDEDED"
            default: return "#FFFFFF"
            }
        }
    }
}

extension FeedButton.Kind: CaseIterable, Identifiable {
    static var allCases: [FeedButton.Kind] {
        [.ghost, .soft, .dark, .light, .primary, .success, .warning, .destructive]
    }

    var id: String { rawValue }

    var debugLabel: String {
        switch self {
        case .ghost:
            return String(localized: "feed.buttonDebug.kind.ghost", defaultValue: "Ghost")
        case .soft:
            return String(localized: "feed.buttonDebug.kind.soft", defaultValue: "Soft")
        case .dark:
            return String(localized: "feed.buttonDebug.kind.dark", defaultValue: "Dark")
        case .light:
            return String(localized: "feed.buttonDebug.kind.light", defaultValue: "Light")
        case .primary:
            return String(localized: "feed.buttonDebug.kind.primary", defaultValue: "Primary")
        case .success:
            return String(localized: "feed.buttonDebug.kind.success", defaultValue: "Success")
        case .warning:
            return String(localized: "feed.buttonDebug.kind.warning", defaultValue: "Warning")
        case .destructive:
            return String(localized: "feed.buttonDebug.kind.destructive", defaultValue: "Destructive")
        }
    }
}

final class FeedButtonStyleDebugWindowController: NSWindowController, NSWindowDelegate {
    static let shared = FeedButtonStyleDebugWindowController()

    private init() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 650),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.title = String(
            localized: "feed.buttonDebug.windowTitle",
            defaultValue: "Feed Button Style"
        )
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("cmux.feedButtonStyleDebug")
        window.minSize = NSSize(width: 460, height: 520)
        window.center()
        window.contentView = NSHostingView(rootView: FeedButtonStyleDebugView())
        AppDelegate.shared?.applyWindowDecorations(to: window)
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct FeedButtonStyleDebugView: View {
    @AppStorage(FeedButtonDebugSettings.styleKey)
    private var styleRaw = FeedButtonDebugVisualStyle.solid.rawValue
    @AppStorage(FeedButtonDebugSettings.compactCornerRadiusKey)
    private var compactCornerRadius = 5.0
    @AppStorage(FeedButtonDebugSettings.mediumCornerRadiusKey)
    private var mediumCornerRadius = 6.0
    @AppStorage(FeedButtonDebugSettings.compactHorizontalPaddingKey)
    private var compactHorizontalPadding = 8.0
    @AppStorage(FeedButtonDebugSettings.mediumHorizontalPaddingKey)
    private var mediumHorizontalPadding = 12.0
    @AppStorage(FeedButtonDebugSettings.compactVerticalPaddingKey)
    private var compactVerticalPadding = 4.0
    @AppStorage(FeedButtonDebugSettings.mediumVerticalPaddingKey)
    private var mediumVerticalPadding = 5.0
    @AppStorage(FeedButtonDebugSettings.glassTintOpacityKey)
    private var glassTintOpacity = 0.42
    @AppStorage(FeedButtonDebugSettings.borderWidthKey)
    private var borderWidth = 0.9
    @State private var selectedKind: FeedButton.Kind = .primary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                previewRail
                styleControls
                kindPicker
                colorControls
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .onChange(of: styleRaw) { _, _ in FeedButtonDebugSettings.bumpGeneration() }
        .onChange(of: compactCornerRadius) { _, _ in FeedButtonDebugSettings.bumpGeneration() }
        .onChange(of: mediumCornerRadius) { _, _ in FeedButtonDebugSettings.bumpGeneration() }
        .onChange(of: compactHorizontalPadding) { _, _ in FeedButtonDebugSettings.bumpGeneration() }
        .onChange(of: mediumHorizontalPadding) { _, _ in FeedButtonDebugSettings.bumpGeneration() }
        .onChange(of: compactVerticalPadding) { _, _ in FeedButtonDebugSettings.bumpGeneration() }
        .onChange(of: mediumVerticalPadding) { _, _ in FeedButtonDebugSettings.bumpGeneration() }
        .onChange(of: glassTintOpacity) { _, _ in FeedButtonDebugSettings.bumpGeneration() }
        .onChange(of: borderWidth) { _, _ in FeedButtonDebugSettings.bumpGeneration() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "feed.buttonDebug.title", defaultValue: "Feed Buttons"))
                    .font(.system(size: 17, weight: .semibold))
                Text(
                    String(
                        localized: "feed.buttonDebug.subtitle",
                        defaultValue: "Tune every Feed button kind live."
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(String(localized: "feed.buttonDebug.reset", defaultValue: "Reset")) {
                FeedButtonDebugSettings.reset()
                styleRaw = FeedButtonDebugVisualStyle.solid.rawValue
                compactCornerRadius = 5.0
                mediumCornerRadius = 6.0
                compactHorizontalPadding = 8.0
                mediumHorizontalPadding = 12.0
                compactVerticalPadding = 4.0
                mediumVerticalPadding = 5.0
                glassTintOpacity = 0.42
                borderWidth = 0.9
            }
        }
    }

    private var previewRail: some View {
        HStack(spacing: 8) {
            ForEach(FeedButton.Kind.allCases) { kind in
                FeedButton(
                    label: kind.debugLabel,
                    kind: kind,
                    size: kind == .ghost ? .compact : .medium,
                    isSelected: selectedKind == kind
                ) {
                    selectedKind = kind
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var styleControls: some View {
        GroupBox(String(localized: "feed.buttonDebug.style", defaultValue: "Style")) {
            VStack(alignment: .leading, spacing: 10) {
                Picker(
                    String(localized: "feed.buttonDebug.style", defaultValue: "Style"),
                    selection: $styleRaw
                ) {
                    ForEach(FeedButtonDebugVisualStyle.allCases) { style in
                        Text(style.label).tag(style.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Button(
                    String(
                        localized: "feed.buttonDebug.applyRaycastGlass",
                        defaultValue: "Apply Raycast Glass"
                    )
                ) {
                    FeedButtonDebugSettings.applyRaycastGlassPreset()
                    styleRaw = FeedButtonDebugVisualStyle.glass.rawValue
                    compactCornerRadius = 7.0
                    mediumCornerRadius = 8.0
                    compactHorizontalPadding = 9.0
                    mediumHorizontalPadding = 12.0
                    compactVerticalPadding = 4.5
                    mediumVerticalPadding = 6.0
                    glassTintOpacity = 0.38
                    borderWidth = 0.8
                }

                debugSlider(
                    title: String(localized: "feed.buttonDebug.compactRadius", defaultValue: "Compact radius"),
                    value: $compactCornerRadius,
                    range: 2...14,
                    suffix: "px"
                )
                debugSlider(
                    title: String(localized: "feed.buttonDebug.mediumRadius", defaultValue: "Medium radius"),
                    value: $mediumCornerRadius,
                    range: 2...16,
                    suffix: "px"
                )
                debugSlider(
                    title: String(localized: "feed.buttonDebug.horizontalPadding", defaultValue: "Horizontal padding"),
                    value: $mediumHorizontalPadding,
                    range: 6...18,
                    suffix: "px"
                )
                debugSlider(
                    title: String(localized: "feed.buttonDebug.compactHorizontalPadding", defaultValue: "Compact horizontal padding"),
                    value: $compactHorizontalPadding,
                    range: 5...14,
                    suffix: "px"
                )
                debugSlider(
                    title: String(localized: "feed.buttonDebug.compactVerticalPadding", defaultValue: "Compact vertical padding"),
                    value: $compactVerticalPadding,
                    range: 2...9,
                    suffix: "px"
                )
                debugSlider(
                    title: String(localized: "feed.buttonDebug.mediumVerticalPadding", defaultValue: "Medium vertical padding"),
                    value: $mediumVerticalPadding,
                    range: 3...11,
                    suffix: "px"
                )
                debugSlider(
                    title: String(localized: "feed.buttonDebug.glassTint", defaultValue: "Glass tint"),
                    value: $glassTintOpacity,
                    range: 0.05...0.9,
                    suffix: "%"
                )
                debugSlider(
                    title: String(localized: "feed.buttonDebug.borderWidth", defaultValue: "Border"),
                    value: $borderWidth,
                    range: 0.5...2.5,
                    suffix: "px"
                )
            }
            .padding(.vertical, 4)
        }
    }

    private var kindPicker: some View {
        GroupBox(String(localized: "feed.buttonDebug.kind", defaultValue: "Button Kind")) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(FeedButton.Kind.allCases) { kind in
                    HStack(spacing: 8) {
                        Image(systemName: selectedKind == kind ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedKind == kind ? Color.accentColor : Color.secondary)
                            .frame(width: 15)
                        Text(kind.debugLabel)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        FeedButton(label: kind.debugLabel, kind: kind, size: .compact) {
                            selectedKind = kind
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedKind = kind }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var colorControls: some View {
        GroupBox(String(localized: "feed.buttonDebug.colors", defaultValue: "Colors")) {
            VStack(alignment: .leading, spacing: 10) {
                ColorPicker(
                    String(localized: "feed.buttonDebug.background", defaultValue: "Background"),
                    selection: colorBinding(for: selectedKind, role: .background),
                    supportsOpacity: false
                )
                ColorPicker(
                    String(localized: "feed.buttonDebug.hover", defaultValue: "Hover"),
                    selection: colorBinding(for: selectedKind, role: .hoverBackground),
                    supportsOpacity: false
                )
                ColorPicker(
                    String(localized: "feed.buttonDebug.foreground", defaultValue: "Foreground"),
                    selection: colorBinding(for: selectedKind, role: .foreground),
                    supportsOpacity: false
                )
                HStack {
                    Text(String(localized: "feed.buttonDebug.preview", defaultValue: "Preview"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    FeedButton(label: selectedKind.debugLabel, kind: selectedKind, size: .medium) {}
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func colorBinding(
        for kind: FeedButton.Kind,
        role: FeedButtonDebugColorRole
    ) -> Binding<Color> {
        Binding(
            get: {
                FeedButtonDebugSettings.color(for: kind, role: role)
                    ?? FeedButtonDebugSettings.defaultColor(for: kind, role: role)
            },
            set: { newValue in
                FeedButtonDebugSettings.setColor(newValue, for: kind, role: role)
            }
        )
    }

    private func debugSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        suffix: String
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11))
                .frame(width: 150, alignment: .leading)
            Slider(value: value, in: range)
            Text(sliderValue(value.wrappedValue, suffix: suffix))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    private func sliderValue(_ value: Double, suffix: String) -> String {
        if suffix == "%" {
            return String(format: "%.0f%%", value * 100)
        }
        return String(format: "%.1f%@", value, suffix)
    }
}
#endif
