#if DEBUG
import AppKit
import SwiftUI

enum FeedButtonDebugVisualStyle: String, CaseIterable, Identifiable {
    case solid
    case glass
    case nativeGlass
    case nativeProminentGlass
    case liquid
    case halo
    case command
    case commandLight
    case outline
    case flat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .solid:
            return String(localized: "feed.buttonDebug.style.solid", defaultValue: "Solid")
        case .glass:
            return String(localized: "feed.buttonDebug.style.glass", defaultValue: "Raycast Glass")
        case .nativeGlass:
            return String(localized: "feed.buttonDebug.style.nativeGlass", defaultValue: "Native Glass")
        case .nativeProminentGlass:
            return String(localized: "feed.buttonDebug.style.nativeProminentGlass", defaultValue: "Prominent Glass")
        case .liquid:
            return String(localized: "feed.buttonDebug.style.liquid", defaultValue: "Liquid")
        case .halo:
            return String(localized: "feed.buttonDebug.style.halo", defaultValue: "Halo")
        case .command:
            return String(localized: "feed.buttonDebug.style.command", defaultValue: "Command")
        case .commandLight:
            return String(localized: "feed.buttonDebug.style.commandLight", defaultValue: "Command Light")
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
    case nativeGlass
    case nativeProminentGlass
    case liquidCapsule
    case frostedOutline
    case haloGlow
    case commandDark
    case commandLight
    case clearGlass
    case compactGlass
    case nativeBlue
    case liquidMono
    case softHalo
    case hairlineGlass
    case minimalFlat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .solidClassic:
            return String(localized: "feed.buttonDebug.preset.solidClassic", defaultValue: "Solid Classic")
        case .raycastGlass:
            return String(localized: "feed.buttonDebug.preset.raycastGlass", defaultValue: "Raycast Glass")
        case .nativeGlass:
            return String(localized: "feed.buttonDebug.preset.nativeGlass", defaultValue: "Native Glass")
        case .nativeProminentGlass:
            return String(localized: "feed.buttonDebug.preset.nativeProminentGlass", defaultValue: "Prominent Glass")
        case .liquidCapsule:
            return String(localized: "feed.buttonDebug.preset.liquidCapsule", defaultValue: "Liquid Capsule")
        case .frostedOutline:
            return String(localized: "feed.buttonDebug.preset.frostedOutline", defaultValue: "Frosted Outline")
        case .haloGlow:
            return String(localized: "feed.buttonDebug.preset.haloGlow", defaultValue: "Halo Glow")
        case .commandDark:
            return String(localized: "feed.buttonDebug.preset.commandDark", defaultValue: "Command Dark")
        case .commandLight:
            return String(localized: "feed.buttonDebug.preset.commandLight", defaultValue: "Command Light")
        case .clearGlass:
            return String(localized: "feed.buttonDebug.preset.clearGlass", defaultValue: "Clear Glass")
        case .compactGlass:
            return String(localized: "feed.buttonDebug.preset.compactGlass", defaultValue: "Compact Glass")
        case .nativeBlue:
            return String(localized: "feed.buttonDebug.preset.nativeBlue", defaultValue: "Native Blue")
        case .liquidMono:
            return String(localized: "feed.buttonDebug.preset.liquidMono", defaultValue: "Liquid Mono")
        case .softHalo:
            return String(localized: "feed.buttonDebug.preset.softHalo", defaultValue: "Soft Halo")
        case .hairlineGlass:
            return String(localized: "feed.buttonDebug.preset.hairlineGlass", defaultValue: "Hairline Glass")
        case .minimalFlat:
            return String(localized: "feed.buttonDebug.preset.minimalFlat", defaultValue: "Minimal Flat")
        }
    }

    var style: FeedButtonDebugVisualStyle {
        switch self {
        case .solidClassic: return .solid
        case .raycastGlass: return .glass
        case .nativeGlass: return .nativeGlass
        case .nativeProminentGlass: return .nativeProminentGlass
        case .liquidCapsule: return .liquid
        case .frostedOutline: return .outline
        case .haloGlow: return .halo
        case .commandDark: return .command
        case .commandLight: return .commandLight
        case .clearGlass: return .nativeGlass
        case .compactGlass: return .glass
        case .nativeBlue: return .nativeGlass
        case .liquidMono: return .liquid
        case .softHalo: return .halo
        case .hairlineGlass: return .outline
        case .minimalFlat: return .flat
        }
    }

    var compactCornerRadius: Double {
        switch self {
        case .solidClassic, .minimalFlat: return 5.0
        case .raycastGlass, .frostedOutline: return 7.0
        case .nativeGlass: return 9.0
        case .nativeProminentGlass: return 10.0
        case .liquidCapsule: return 12.0
        case .haloGlow, .commandDark, .commandLight: return 8.0
        case .clearGlass, .nativeBlue, .softHalo: return 9.0
        case .compactGlass: return 6.0
        case .liquidMono: return 11.0
        case .hairlineGlass: return 6.0
        }
    }

    var mediumCornerRadius: Double {
        switch self {
        case .solidClassic, .minimalFlat: return 6.0
        case .raycastGlass, .frostedOutline, .commandDark: return 8.0
        case .nativeGlass: return 10.0
        case .nativeProminentGlass: return 11.0
        case .liquidCapsule: return 14.0
        case .haloGlow: return 9.0
        case .commandLight: return 8.0
        case .clearGlass, .nativeBlue, .softHalo: return 10.0
        case .compactGlass: return 7.0
        case .liquidMono: return 13.0
        case .hairlineGlass: return 7.0
        }
    }

    var compactHorizontalPadding: Double {
        switch self {
        case .minimalFlat: return 7.0
        case .raycastGlass, .frostedOutline, .commandDark: return 9.0
        case .nativeGlass: return 9.5
        case .nativeProminentGlass: return 10.0
        case .liquidCapsule: return 10.0
        case .haloGlow: return 9.5
        case .commandLight, .clearGlass, .nativeBlue, .softHalo: return 9.5
        case .compactGlass: return 8.0
        case .liquidMono: return 10.5
        case .hairlineGlass: return 8.5
        case .solidClassic: return 8.0
        }
    }

    var mediumHorizontalPadding: Double {
        switch self {
        case .minimalFlat: return 10.0
        case .nativeGlass: return 13.0
        case .nativeProminentGlass: return 14.0
        case .liquidCapsule: return 15.0
        case .haloGlow: return 13.0
        case .solidClassic, .raycastGlass, .frostedOutline, .commandDark: return 12.0
        case .commandLight: return 12.0
        case .clearGlass, .nativeBlue, .softHalo: return 13.0
        case .compactGlass: return 11.0
        case .liquidMono: return 14.0
        case .hairlineGlass: return 11.0
        }
    }

    var compactVerticalPadding: Double {
        switch self {
        case .minimalFlat: return 3.5
        case .nativeGlass: return 5.0
        case .nativeProminentGlass: return 5.5
        case .liquidCapsule, .haloGlow: return 5.0
        case .raycastGlass, .frostedOutline, .commandDark: return 4.5
        case .commandLight, .clearGlass, .nativeBlue, .softHalo: return 4.5
        case .compactGlass: return 2.5
        case .liquidMono: return 5.0
        case .hairlineGlass: return 4.0
        case .solidClassic: return 4.0
        }
    }

    var mediumVerticalPadding: Double {
        switch self {
        case .minimalFlat: return 4.5
        case .nativeGlass: return 6.0
        case .nativeProminentGlass: return 6.5
        case .liquidCapsule: return 6.5
        case .raycastGlass, .haloGlow: return 6.0
        case .frostedOutline, .commandDark: return 5.5
        case .commandLight, .clearGlass, .nativeBlue, .softHalo: return 5.5
        case .compactGlass: return 3.5
        case .liquidMono: return 6.0
        case .hairlineGlass: return 5.0
        case .solidClassic: return 5.0
        }
    }

    var glassTintOpacity: Double {
        switch self {
        case .solidClassic: return 0.42
        case .raycastGlass: return 0.38
        case .nativeGlass: return 0.22
        case .nativeProminentGlass: return 0.46
        case .liquidCapsule: return 0.30
        case .frostedOutline: return 0.18
        case .haloGlow: return 0.34
        case .commandDark: return 0.24
        case .commandLight: return 0.18
        case .clearGlass: return 0.08
        case .compactGlass: return 0.24
        case .nativeBlue: return 0.34
        case .liquidMono: return 0.20
        case .softHalo: return 0.18
        case .hairlineGlass: return 0.10
        case .minimalFlat: return 0.12
        }
    }

    var borderWidth: Double {
        switch self {
        case .solidClassic, .raycastGlass, .commandDark: return 0.8
        case .nativeGlass: return 0.6
        case .nativeProminentGlass: return 0.7
        case .liquidCapsule: return 0.7
        case .frostedOutline: return 1.2
        case .haloGlow: return 0.9
        case .commandLight: return 0.8
        case .clearGlass, .nativeBlue: return 0.6
        case .compactGlass: return 0.7
        case .liquidMono, .softHalo: return 0.8
        case .hairlineGlass: return 0.7
        case .minimalFlat: return 0.5
        }
    }

    func palette(for kind: FeedButton.Kind) -> FeedButtonDebugPalette? {
        switch self {
        case .solidClassic, .raycastGlass, .nativeGlass:
            return nil
        case .nativeProminentGlass:
            return nativeProminentPalette(for: kind)
        case .liquidCapsule:
            return liquidPalette(for: kind)
        case .frostedOutline:
            return frostedPalette(for: kind)
        case .haloGlow:
            return haloPalette(for: kind)
        case .commandDark:
            return commandPalette(for: kind)
        case .commandLight:
            return commandLightPalette(for: kind)
        case .clearGlass:
            return clearGlassPalette(for: kind)
        case .compactGlass:
            return compactGlassPalette(for: kind)
        case .nativeBlue:
            return nativeBluePalette(for: kind)
        case .liquidMono:
            return liquidMonoPalette(for: kind)
        case .softHalo:
            return softHaloPalette(for: kind)
        case .hairlineGlass:
            return hairlineGlassPalette(for: kind)
        case .minimalFlat:
            return minimalPalette(for: kind)
        }
    }

    private func nativeProminentPalette(for kind: FeedButton.Kind) -> FeedButtonDebugPalette {
        switch kind {
        case .ghost: return .init(background: "#76869A", hoverBackground: "#8C9DB2", foreground: "#FFFFFF")
        case .soft: return .init(background: "#65717E", hoverBackground: "#7A8795", foreground: "#FFFFFF")
        case .dark: return .init(background: "#1B2027", hoverBackground: "#2A3039", foreground: "#FFFFFF")
        case .light: return .init(background: "#EEF2F6", hoverBackground: "#FFFFFF", foreground: "#111827")
        case .primary: return .init(background: "#2E78E6", hoverBackground: "#4A91FF", foreground: "#FFFFFF")
        case .success: return .init(background: "#239D66", hoverBackground: "#30B978", foreground: "#FFFFFF")
        case .warning: return .init(background: "#DA7C38", hoverBackground: "#F09046", foreground: "#FFFFFF")
        case .destructive: return .init(background: "#BF3F4A", hoverBackground: "#D9515C", foreground: "#FFFFFF")
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

    private func commandLightPalette(for kind: FeedButton.Kind) -> FeedButtonDebugPalette {
        switch kind {
        case .ghost: return .init(background: "#E7EDF3", hoverBackground: "#F4F7FA", foreground: "#1B2430")
        case .soft: return .init(background: "#DDE5ED", hoverBackground: "#EAF0F5", foreground: "#1C2430")
        case .dark: return .init(background: "#48525F", hoverBackground: "#5A6675", foreground: "#FFFFFF")
        case .light: return .init(background: "#F5F7FA", hoverBackground: "#FFFFFF", foreground: "#111827")
        case .primary: return .init(background: "#D9E8FF", hoverBackground: "#E6F1FF", foreground: "#123B6D")
        case .success: return .init(background: "#D8F0E2", hoverBackground: "#E7F8EE", foreground: "#155234")
        case .warning: return .init(background: "#F5E2CE", hoverBackground: "#FAECDD", foreground: "#70421C")
        case .destructive: return .init(background: "#F2D7DA", hoverBackground: "#F8E5E7", foreground: "#7A1E28")
        }
    }

    private func clearGlassPalette(for kind: FeedButton.Kind) -> FeedButtonDebugPalette {
        switch kind {
        case .ghost: return .init(background: "#CBD5DF", hoverBackground: "#E2E8EF", foreground: "#111827")
        case .soft: return .init(background: "#D2D8DF", hoverBackground: "#E7EBEF", foreground: "#111827")
        case .dark: return .init(background: "#5B6572", hoverBackground: "#6F7A89", foreground: "#FFFFFF")
        case .light: return .init(background: "#F8FAFC", hoverBackground: "#FFFFFF", foreground: "#111827")
        case .primary: return .init(background: "#CFE2FF", hoverBackground: "#E0EDFF", foreground: "#133A66")
        case .success: return .init(background: "#D6F1E2", hoverBackground: "#E6F8EE", foreground: "#145234")
        case .warning: return .init(background: "#F4E1CF", hoverBackground: "#FAECDF", foreground: "#6B401E")
        case .destructive: return .init(background: "#F1D6DB", hoverBackground: "#F8E5E9", foreground: "#751D2A")
        }
    }

    private func compactGlassPalette(for kind: FeedButton.Kind) -> FeedButtonDebugPalette {
        switch kind {
        case .ghost: return .init(background: "#AAB4BF", hoverBackground: "#C1CAD4", foreground: "#F8FAFC")
        case .soft: return .init(background: "#7B858F", hoverBackground: "#909BA7", foreground: "#FFFFFF")
        case .dark: return .init(background: "#262C34", hoverBackground: "#373F4A", foreground: "#FFFFFF")
        case .light: return .init(background: "#EEF2F6", hoverBackground: "#FFFFFF", foreground: "#111827")
        case .primary: return .init(background: "#4E8EE8", hoverBackground: "#68A1F4", foreground: "#FFFFFF")
        case .success: return .init(background: "#47A876", hoverBackground: "#5DC08C", foreground: "#FFFFFF")
        case .warning: return .init(background: "#D99050", hoverBackground: "#EDA261", foreground: "#FFFFFF")
        case .destructive: return .init(background: "#C95E68", hoverBackground: "#DD737D", foreground: "#FFFFFF")
        }
    }

    private func nativeBluePalette(for kind: FeedButton.Kind) -> FeedButtonDebugPalette {
        switch kind {
        case .ghost: return .init(background: "#8CB7E8", hoverBackground: "#A8C9F0", foreground: "#F8FBFF")
        case .soft: return .init(background: "#7799C4", hoverBackground: "#8EADD4", foreground: "#FFFFFF")
        case .dark: return .init(background: "#1B3356", hoverBackground: "#294A78", foreground: "#FFFFFF")
        case .light: return .init(background: "#EAF3FF", hoverBackground: "#FFFFFF", foreground: "#0F2E52")
        case .primary: return .init(background: "#2C79E4", hoverBackground: "#4992FA", foreground: "#FFFFFF")
        case .success: return .init(background: "#299A82", hoverBackground: "#36B99C", foreground: "#FFFFFF")
        case .warning: return .init(background: "#D68A45", hoverBackground: "#F09D55", foreground: "#FFFFFF")
        case .destructive: return .init(background: "#C64D67", hoverBackground: "#DD5E79", foreground: "#FFFFFF")
        }
    }

    private func liquidMonoPalette(for kind: FeedButton.Kind) -> FeedButtonDebugPalette {
        switch kind {
        case .ghost: return .init(background: "#88919A", hoverBackground: "#A1A9B1", foreground: "#F8FAFC")
        case .soft: return .init(background: "#6D747C", hoverBackground: "#828A93", foreground: "#FFFFFF")
        case .dark: return .init(background: "#252A30", hoverBackground: "#343B43", foreground: "#FFFFFF")
        case .light: return .init(background: "#ECEFF2", hoverBackground: "#FFFFFF", foreground: "#111827")
        case .primary: return .init(background: "#607D9F", hoverBackground: "#7492B6", foreground: "#FFFFFF")
        case .success: return .init(background: "#607F70", hoverBackground: "#749685", foreground: "#FFFFFF")
        case .warning: return .init(background: "#8C785F", hoverBackground: "#A08D73", foreground: "#FFFFFF")
        case .destructive: return .init(background: "#87656A", hoverBackground: "#9C777D", foreground: "#FFFFFF")
        }
    }

    private func softHaloPalette(for kind: FeedButton.Kind) -> FeedButtonDebugPalette {
        switch kind {
        case .ghost: return .init(background: "#B4C0D5", hoverBackground: "#C7D2E6", foreground: "#FFFFFF")
        case .soft: return .init(background: "#9DA8BA", hoverBackground: "#B2BDCE", foreground: "#FFFFFF")
        case .dark: return .init(background: "#303848", hoverBackground: "#434D60", foreground: "#FFFFFF")
        case .light: return .init(background: "#F1F4FA", hoverBackground: "#FFFFFF", foreground: "#111827")
        case .primary: return .init(background: "#7EAAED", hoverBackground: "#96BCF5", foreground: "#FFFFFF")
        case .success: return .init(background: "#7AC49A", hoverBackground: "#91D8AD", foreground: "#FFFFFF")
        case .warning: return .init(background: "#E0A676", hoverBackground: "#F0BA8A", foreground: "#FFFFFF")
        case .destructive: return .init(background: "#D7868D", hoverBackground: "#EA9CA3", foreground: "#FFFFFF")
        }
    }

    private func hairlineGlassPalette(for kind: FeedButton.Kind) -> FeedButtonDebugPalette {
        switch kind {
        case .ghost: return .init(background: "#9CA3AF", hoverBackground: "#C1C7D0", foreground: "#E5E7EB")
        case .soft: return .init(background: "#7B838E", hoverBackground: "#9AA2AD", foreground: "#F3F4F6")
        case .dark: return .init(background: "#30343A", hoverBackground: "#454A52", foreground: "#FFFFFF")
        case .light: return .init(background: "#EEF0F3", hoverBackground: "#FFFFFF", foreground: "#111827")
        case .primary: return .init(background: "#73A7EC", hoverBackground: "#8DB9F5", foreground: "#FFFFFF")
        case .success: return .init(background: "#72BE92", hoverBackground: "#88D2A6", foreground: "#FFFFFF")
        case .warning: return .init(background: "#D69B6F", hoverBackground: "#EAB083", foreground: "#FFFFFF")
        case .destructive: return .init(background: "#CE7E84", hoverBackground: "#E19399", foreground: "#FFFFFF")
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

private struct FeedButtonDebugPresetSection: Identifiable {
    let id: String
    let label: String
    let presets: [FeedButtonDebugPreset]

    static var all: [FeedButtonDebugPresetSection] {
        [
            FeedButtonDebugPresetSection(
                id: "base",
                label: String(localized: "feed.buttonDebug.section.base", defaultValue: "Base"),
                presets: [.solidClassic, .minimalFlat]
            ),
            FeedButtonDebugPresetSection(
                id: "native",
                label: String(localized: "feed.buttonDebug.section.nativeGlass", defaultValue: "Native Glass"),
                presets: [.nativeGlass, .nativeProminentGlass, .clearGlass, .nativeBlue]
            ),
            FeedButtonDebugPresetSection(
                id: "command",
                label: String(localized: "feed.buttonDebug.section.command", defaultValue: "Command"),
                presets: [.commandDark, .commandLight]
            ),
            FeedButtonDebugPresetSection(
                id: "material",
                label: String(localized: "feed.buttonDebug.section.material", defaultValue: "Material"),
                presets: [
                    .raycastGlass,
                    .compactGlass,
                    .liquidCapsule,
                    .liquidMono,
                    .frostedOutline,
                    .haloGlow,
                    .softHalo,
                    .hairlineGlass,
                ]
            ),
        ]
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
        Group {
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 8) {
                    previewRailContent
                }
            } else {
                previewRailContent
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var previewRailContent: some View {
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

                ForEach(FeedButtonDebugPresetSection.all) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(
                            columns: [
                                GridItem(.adaptive(minimum: 132), spacing: 8, alignment: .leading),
                            ],
                            alignment: .leading,
                            spacing: 8
                        ) {
                            ForEach(section.presets) { preset in
                                presetButton(preset)
                            }
                        }
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

    private func presetButton(_ preset: FeedButtonDebugPreset) -> some View {
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
