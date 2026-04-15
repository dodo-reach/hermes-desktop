import AppKit
import SwiftUI

enum TerminalThemeStyle: String, Codable, Equatable {
    case system
    case graphite
    case evergreen
    case dusk
    case paper
    case custom
}

struct TerminalThemeColor: Codable, Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
    }

    init(hex: Int) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }

    init(nsColor: NSColor) {
        let resolved = nsColor.usingColorSpace(.deviceRGB) ?? NSColor.black
        self.init(
            red: Double(resolved.redComponent),
            green: Double(resolved.greenComponent),
            blue: Double(resolved.blueComponent)
        )
    }

    var nsColor: NSColor {
        NSColor(
            deviceRed: red,
            green: green,
            blue: blue,
            alpha: 1
        )
    }

    var swiftUIColor: Color {
        Color(nsColor: nsColor)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

struct TerminalThemePreset: Identifiable, Equatable {
    let style: TerminalThemeStyle
    let name: String
    let summary: String
    let backgroundColor: TerminalThemeColor
    let foregroundColor: TerminalThemeColor
    let ansiPalette: [TerminalThemeColor]

    var id: String {
        style.rawValue
    }
}

struct TerminalThemeAppearance: Equatable {
    let style: TerminalThemeStyle
    let name: String
    let backgroundColor: TerminalThemeColor
    let foregroundColor: TerminalThemeColor
    let ansiPalette: [TerminalThemeColor]
    let paletteStyle: TerminalThemeStyle
    let isCustom: Bool
}

struct TerminalThemePreference: Codable, Equatable {
    var style: TerminalThemeStyle = .system
    var customBackgroundColor: TerminalThemeColor?
    var customForegroundColor: TerminalThemeColor?
    var paletteStyle: TerminalThemeStyle?

    static let defaultValue = TerminalThemePreference()

    var resolvedAppearance: TerminalThemeAppearance {
        switch style {
        case .system:
            return TerminalThemeAppearance(
                style: .system,
                name: "System",
                backgroundColor: TerminalThemeColor(nsColor: NSColor.textBackgroundColor),
                foregroundColor: TerminalThemeColor(nsColor: NSColor.textColor),
                ansiPalette: Self.systemPalette,
                paletteStyle: .system,
                isCustom: false
            )
        case .custom:
            let basePreset = Self.preset(for: paletteStyle ?? .graphite) ?? Self.graphitePreset
            return TerminalThemeAppearance(
                style: .custom,
                name: "Custom",
                backgroundColor: customBackgroundColor ?? basePreset.backgroundColor,
                foregroundColor: customForegroundColor ?? basePreset.foregroundColor,
                ansiPalette: basePreset.ansiPalette,
                paletteStyle: basePreset.style,
                isCustom: true
            )
        case .graphite, .evergreen, .dusk, .paper:
            let preset = Self.preset(for: style) ?? Self.graphitePreset
            return TerminalThemeAppearance(
                style: preset.style,
                name: preset.name,
                backgroundColor: preset.backgroundColor,
                foregroundColor: preset.foregroundColor,
                ansiPalette: preset.ansiPalette,
                paletteStyle: preset.style,
                isCustom: false
            )
        }
    }

    func selectingPreset(_ style: TerminalThemeStyle) -> TerminalThemePreference {
        TerminalThemePreference(style: style)
    }

    func updatingBackgroundColor(_ color: TerminalThemeColor) -> TerminalThemePreference {
        let appearance = resolvedAppearance
        return TerminalThemePreference(
            style: .custom,
            customBackgroundColor: color,
            customForegroundColor: appearance.foregroundColor,
            paletteStyle: appearance.paletteStyle
        )
    }

    func updatingForegroundColor(_ color: TerminalThemeColor) -> TerminalThemePreference {
        let appearance = resolvedAppearance
        return TerminalThemePreference(
            style: .custom,
            customBackgroundColor: appearance.backgroundColor,
            customForegroundColor: color,
            paletteStyle: appearance.paletteStyle
        )
    }

    static let quickPresets: [TerminalThemePreset] = [
        graphitePreset,
        evergreenPreset,
        duskPreset,
        paperPreset
    ]

    private static func preset(for style: TerminalThemeStyle) -> TerminalThemePreset? {
        quickPresets.first(where: { $0.style == style })
    }

    private static let graphitePreset = TerminalThemePreset(
        style: .graphite,
        name: "Graphite",
        summary: "Neutral dark theme with high contrast and quiet ANSI accents.",
        backgroundColor: TerminalThemeColor(hex: 0x12161D),
        foregroundColor: TerminalThemeColor(hex: 0xE7ECF3),
        ansiPalette: palette([
            0x1F2430, 0xC7746E, 0x88B976, 0xD6B97A,
            0x78A6D8, 0xB18AD0, 0x6EC5C8, 0xCFD6E3,
            0x596273, 0xE08D86, 0x9FD58A, 0xE4CA91,
            0x93B8E4, 0xC7A3E1, 0x8BD9DA, 0xF4F7FB
        ])
    )

    private static let evergreenPreset = TerminalThemePreset(
        style: .evergreen,
        name: "Evergreen",
        summary: "Deep forest backdrop with calm greens and warm highlights.",
        backgroundColor: TerminalThemeColor(hex: 0x0F1714),
        foregroundColor: TerminalThemeColor(hex: 0xDBE8E1),
        ansiPalette: palette([
            0x16211D, 0xC97973, 0x73B181, 0xD5B66A,
            0x6D98C4, 0xAA86BF, 0x63BEB0, 0xC6D5CE,
            0x4F635B, 0xE49790, 0x8ED09D, 0xE9CB88,
            0x8CB4D6, 0xC39BD3, 0x7FD6C8, 0xEFF7F3
        ])
    )

    private static let duskPreset = TerminalThemePreset(
        style: .dusk,
        name: "Dusk",
        summary: "Cool navy tones that stay readable for long SSH sessions.",
        backgroundColor: TerminalThemeColor(hex: 0x101726),
        foregroundColor: TerminalThemeColor(hex: 0xDDE7F7),
        ansiPalette: palette([
            0x1A2235, 0xD06E79, 0x86B97B, 0xD5BA79,
            0x7AA2D8, 0xB390D2, 0x70C0D0, 0xCCD7EA,
            0x55627E, 0xE48A95, 0xA1D191, 0xE6CD90,
            0x97B9E8, 0xC9A5E3, 0x89D9E4, 0xF4F8FD
        ])
    )

    private static let paperPreset = TerminalThemePreset(
        style: .paper,
        name: "Paper",
        summary: "Light, editorial theme for daytime work and quiet rooms.",
        backgroundColor: TerminalThemeColor(hex: 0xF5F1E8),
        foregroundColor: TerminalThemeColor(hex: 0x2F3743),
        ansiPalette: palette([
            0x3C4657, 0xB44A56, 0x4E8B67, 0xA77720,
            0x416EA9, 0x8758A6, 0x2E8B92, 0xD9D2C4,
            0x6D7482, 0xCD6571, 0x66A07C, 0xBF9147,
            0x5C86BE, 0xA072BD, 0x53A6AD, 0xFFFDF8
        ])
    )

    private static let systemPalette = palette([
        0x000000, 0xC23621, 0x25BC24, 0xADAD27,
        0x492EE1, 0xD338D3, 0x33BBC8, 0xCBCCCD,
        0x818383, 0xFC391F, 0x31E722, 0xEAEC23,
        0x5833FF, 0xF935F8, 0x14F0F0, 0xE9EBEB
    ])

    private static func palette(_ hexValues: [Int]) -> [TerminalThemeColor] {
        hexValues.map(TerminalThemeColor.init(hex:))
    }
}
