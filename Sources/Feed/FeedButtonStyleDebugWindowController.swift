#if DEBUG
import AppKit
import SwiftUI

enum FeedButtonDebugVisualStyle: String, CaseIterable, Identifiable {
    case solid
    case glass
    case liquid
    case halo
    case command
    case outline
    case flat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .solid:
            return String(localized: "feed.buttonDebug.style.solid", defaultValue: "Solid")
        case .glass:
            return String(localized: "feed.buttonDebug.style.glass", defaultValue: "Raycast Glass")
        case .liquid:
            return String(localized: "feed.buttonDebug.style.liquid", defaultValue: "Liquid")
        case .halo:
            return String(localized: "feed.buttonDebug.style.halo", defaultValue: "Halo")
        case .command:
            return String(localized: "feed.buttonDebug.style.command", defaultValue: "Command")
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
        apply(.raycastGlass)
    }

    static func apply(_ preset: FeedButtonDebugPreset) {
        defaults.set(preset.style.rawValue, forKey: styleKey)
        defaults.set(preset.compactCornerRadius, forKey: compactCornerRadiusKey)
        defaults.set(preset.mediumCornerRadius, forKey: mediumCornerRadiusKey)
        defaults.set(preset.compactHorizontalPadding, forKey: compactHorizontalPaddingKey)
        defaults.set(preset.mediumHorizontalPadding, forKey: mediumHorizontalPaddingKey)
        defaults.set(preset.compactVerticalPadding, forKey: compactVerticalPaddingKey)
        defaults.set(preset.mediumVerticalPadding, forKey: mediumVerticalPaddingKey)
        defaults.set(preset.glassTintOpacity, forKey: glassTintOpacityKey)
        defaults.set(preset.borderWidth, forKey: borderWidthKey)

        for kind in FeedButton.Kind.allCases {
            if let palette = preset.palette(for: kind) {
                setColorHex(palette.background, for: kind, role: .background)
                setColorHex(palette.hoverBackground, for: kind, role: .hoverBackground)
                setColorHex(palette.foreground, for: kind, role: .foreground)
            } else {
                defaults.removeObject(forKey: colorKey(kind: kind, role: .background))
                defaults.removeObject(forKey: colorKey(kind: kind, role: .hoverBackground))
                defaults.removeObject(forKey: colorKey(kind: kind, role: .foreground))
            }
        }
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

    private static func setColorHex(
        _ hex: String,
        for kind: FeedButton.Kind,
        role: FeedButtonDebugColorRole
    ) {
        defaults.set(hex, forKey: colorKey(kind: kind, role: role))
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

struct FeedButtonDebugPalette {
    let background: String
    let hoverBackground: String
    let foreground: String
}

enum FeedButtonDebugPreset: String, CaseIterable, Identifiable {
    case solidClassic
    case raycastGlass
    case liquidCapsule
    case frostedOutline
    case haloGlow
    case commandDark
    case minimalFlat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .solidClassic:
            return String(localized: "feed.buttonDebug.preset.solidClassic", defaultValue: "Solid Classic")
        case .raycastGlass:
            return String(localized: "feed.buttonDebug.preset.raycastGlass", defaultValue: "Raycast Glass")
        case .liquidCapsule:
            return String(localized: "feed.buttonDebug.preset.liquidCapsule", defaultValue: "Liquid Capsule")
        case .frostedOutline:
            return String(localized: "feed.buttonDebug.preset.frostedOutline", defaultValue: "Frosted Outline")
        case .haloGlow:
            return String(localized: "feed.buttonDebug.preset.haloGlow", defaultValue: "Halo Glow")
        case .commandDark:
            return String(localized: "feed.buttonDebug.preset.commandDark", defaultValue: "Command Dark")
        case .minimalFlat:
            return String(localized: "feed.buttonDebug.preset.minimalFlat", defaultValue: "Minimal Flat")
        }
    }

    var style: FeedButtonDebugVisualStyle {
        switch self {
        case .solidClassic: return .solid
        case .raycastGlass: return .glass
        case .liquidCapsule: return .liquid
        case .frostedOutline: return .outline
        case .haloGlow: return .halo
        case .commandDark: return .command
        case .minimalFlat: return .flat
        }
    }

    var compactCornerRadius: Double {
        switch self {
        case .solidClassic, .minimalFlat: return 5.0
        case .raycastGlass, .frostedOutline: return 7.0
        case .liquidCapsule: return 12.0
        case .haloGlow, .commandDark: return 8.0
        }
    }

    var mediumCornerRadius: Double {
        switch self {
        case .solidClassic, .minimalFlat: return 6.0
        case .raycastGlass, .frostedOutline, .commandDark: return 8.0
        case .liquidCapsule: return 14.0
        case .haloGlow: return 9.0
        }
    }

    var compactHorizontalPadding: Double {
        switch self {
        case .minimalFlat: return 7.0
        case .raycastGlass, .frostedOutline, .commandDark: return 9.0
        case .liquidCapsule: return 10.0
        case .haloGlow: return 9.5
        case .solidClassic: return 8.0
        }
    }

    var mediumHorizontalPadding: Double {
        switch self {
        case .minimalFlat: return 10.0
        case .liquidCapsule: return 15.0
        case .haloGlow: return 13.0
        case .solidClassic, .raycastGlass, .frostedOutline, .commandDark: return 12.0
        }
    }

    var compactVerticalPadding: Double {
        switch self {
        case .minimalFlat: return 3.5
        case .liquidCapsule, .haloGlow: return 5.0
        case .raycastGlass, .frostedOutline, .commandDark: return 4.5
        case .solidClassic: return 4.0
        }
    }

    var mediumVerticalPadding: Double {
        switch self {
        case .minimalFlat: return 4.5
        case .liquidCapsule: return 6.5
        case .raycastGlass, .haloGlow: return 6.0
        case .frostedOutline, .commandDark: return 5.5
        case .solidClassic: return 5.0
        }
    }

    var glassTintOpacity: Double {
        switch self {
        case .solidClassic: return 0.42
        case .raycastGlass: return 0.38
        case .liquidCapsule: return 0.30
        case .frostedOutline: return 0.18
        case .haloGlow: return 0.34
        case .commandDark: return 0.24
        case .minimalFlat: return 0.12
        }
    }

    var borderWidth: Double {
        switch self {
        case .solidClassic, .raycastGlass, .commandDark: return 0.8
        case .liquidCapsule: return 0.7
        case .frostedOutline: return 1.2
        case .haloGlow: return 0.9
        case .minimalFlat: return 0.5
        }
    }

    func palette(for kind: FeedButton.Kind) -> FeedButtonDebugPalette? {
        switch self {
        case .solidClassic, .raycastGlass:
            return nil
        case .liquidCapsule:
            return liquidPalette(for: kind)
        case .frostedOutline:
            return frostedPalette(for: kind)
        case .haloGlow:
            return haloPalette(for: kind)
        case .commandDark:
            return commandPalette(for: kind)
        case .minimalFlat:
            return minimalPalette(for: kind)
        }
    }

    private func liquidPalette(for kind: FeedButton.Kind) -> FeedButtonDebugPalette {
        switch kind {
        case .ghost: return .init(background: "#607080", hoverBackground: "#77889A", foreground: "#F8FAFC")
        case .soft: return .init(background: "#566270", hoverBackground: "#6B7887", foreground: "#F7F7F2")
        case .dark: return .init(background: "#1F252D", hoverBackground: "#303844", foreground: "#FFFFFF")
        case .light: return .init(background: "#EAF0F5", hoverBackground: "#FFFFFF", foreground: "#17202A")
        case .primary: return .init(background: "#2F7EE8", hoverBackground: "#4C97FF", foreground: "#FFFFFF")
        case .success: return .init(background: "#28A66A", hoverBackground: "#37C57F", foreground: "#FFFFFF")
        case .warning: return .init(background: "#E1823F", hoverBackground: "#F39B4F", foreground: "#FFFFFF")
        case .destructive: return .init(background: "#C9434B", hoverBackground: "#E3555D", foreground: "#FFFFFF")
        }
    }

    private func frostedPalette(for kind: FeedButton.Kind) -> FeedButtonDebugPalette {
        switch kind {
        case .ghost: return .init(background: "#A7B0B8", hoverBackground: "#C2CAD1", foreground: "#EEF2F5")
        case .soft: return .init(background: "#808B95", hoverBackground: "#9AA5AF", foreground: "#F5F7F8")
        case .dark: return .init(background: "#31373D", hoverBackground: "#464E57", foreground: "#FFFFFF")
        case .light: return .init(background: "#E8ECEF", hoverBackground: "#FFFFFF", foreground: "#161A1D")
        case .primary: return .init(background: "#6AA7F2", hoverBackground: "#87BBFF", foreground: "#FFFFFF")
        case .success: return .init(background: "#62B984", hoverBackground: "#7FD39D", foreground: "#FFFFFF")
        case .warning: return .init(background: "#DB9A62", hoverBackground: "#F0B076", foreground: "#FFFFFF")
        case .destructive: return .init(background: "#CA6868", hoverBackground: "#E37A7A", foreground: "#FFFFFF")
        }
    }

    private func haloPalette(for kind: FeedButton.Kind) -> FeedButtonDebugPalette {
        switch kind {
        case .ghost: return .init(background: "#6877A8", hoverBackground: "#7F8FCC", foreground: "#FFFFFF")
        case .soft: return .init(background: "#646E86", hoverBackground: "#7B86A0", foreground: "#FFFFFF")
        case .dark: return .init(background: "#1C2030", hoverBackground: "#2C3248", foreground: "#FFFFFF")
        case .light: return .init(background: "#EFF2FA", hoverBackground: "#FFFFFF", foreground: "#111827")
        case .primary: return .init(background: "#3E7BFF", hoverBackground: "#5D93FF", foreground: "#FFFFFF")
        case .success: return .init(background: "#20A86B", hoverBackground: "#2FC881", foreground: "#FFFFFF")
        case .warning: return .init(background: "#F08A30", hoverBackground: "#FFA14C", foreground: "#FFFFFF")
        case .destructive: return .init(background: "#D33F55", hoverBackground: "#EE5870", foreground: "#FFFFFF")
        }
    }

    private func commandPalette(for kind: FeedButton.Kind) -> FeedButtonDebugPalette {
        switch kind {
        case .ghost: return .init(background: "#222932", hoverBackground: "#313B47", foreground: "#E8EDF2")
        case .soft: return .init(background: "#2B3139", hoverBackground: "#3A434E", foreground: "#EEF1F4")
        case .dark: return .init(background: "#121417", hoverBackground: "#20242A", foreground: "#FFFFFF")
        case .light: return .init(background: "#D9DEE3", hoverBackground: "#F1F4F7", foreground: "#101317")
        case .primary: return .init(background: "#245EBD", hoverBackground: "#3173DE", foreground: "#FFFFFF")
        case .success: return .init(background: "#1D8051", hoverBackground: "#299C64", foreground: "#FFFFFF")
        case .warning: return .init(background: "#BE6930", hoverBackground: "#D97D3C", foreground: "#FFFFFF")
        case .destructive: return .init(background: "#A9363F", hoverBackground: "#C44550", foreground: "#FFFFFF")
        }
    }

    private func minimalPalette(for kind: FeedButton.Kind) -> FeedButtonDebugPalette {
        switch kind {
        case .ghost: return .init(background: "#6B7280", hoverBackground: "#808896", foreground: "#E5E7EB")
        case .soft: return .init(background: "#505762", hoverBackground: "#626B78", foreground: "#F3F4F6")
        case .dark: return .init(background: "#1F2933", hoverBackground: "#2D3742", foreground: "#FFFFFF")
        case .light: return .init(background: "#F3F4F6", hoverBackground: "#FFFFFF", foreground: "#111827")
        case .primary: return .init(background: "#426BB0", hoverBackground: "#527CC4", foreground: "#FFFFFF")
        case .success: return .init(background: "#3B8F61", hoverBackground: "#49A875", foreground: "#FFFFFF")
        case .warning: return .init(background: "#B87333", hoverBackground: "#C98342", foreground: "#FFFFFF")
        case .destructive: return .init(background: "#A64040", hoverBackground: "#BA4D4D", foreground: "#FFFFFF")
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
                .pickerStyle(.menu)

                Text(String(localized: "feed.buttonDebug.variations", defaultValue: "Variations"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 132), spacing: 8, alignment: .leading),
                    ],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(FeedButtonDebugPreset.allCases) { preset in
                        Button {
                            applyPreset(preset)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: preset == activePreset ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 11, weight: .medium))
                                Text(preset.label)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.82)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(preset == activePreset
                                          ? Color.accentColor.opacity(0.18)
                                          : Color.primary.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(
                                        preset == activePreset
                                            ? Color.accentColor.opacity(0.5)
                                            : Color.primary.opacity(0.08),
                                        lineWidth: 0.8
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
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

    private var activePreset: FeedButtonDebugPreset? {
        FeedButtonDebugPreset.allCases.first { preset in
            styleRaw == preset.style.rawValue
                && compactCornerRadius == preset.compactCornerRadius
                && mediumCornerRadius == preset.mediumCornerRadius
                && compactHorizontalPadding == preset.compactHorizontalPadding
                && mediumHorizontalPadding == preset.mediumHorizontalPadding
                && compactVerticalPadding == preset.compactVerticalPadding
                && mediumVerticalPadding == preset.mediumVerticalPadding
                && glassTintOpacity == preset.glassTintOpacity
                && borderWidth == preset.borderWidth
        }
    }

    private func applyPreset(_ preset: FeedButtonDebugPreset) {
        FeedButtonDebugSettings.apply(preset)
        styleRaw = preset.style.rawValue
        compactCornerRadius = preset.compactCornerRadius
        mediumCornerRadius = preset.mediumCornerRadius
        compactHorizontalPadding = preset.compactHorizontalPadding
        mediumHorizontalPadding = preset.mediumHorizontalPadding
        compactVerticalPadding = preset.compactVerticalPadding
        mediumVerticalPadding = preset.mediumVerticalPadding
        glassTintOpacity = preset.glassTintOpacity
        borderWidth = preset.borderWidth
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
