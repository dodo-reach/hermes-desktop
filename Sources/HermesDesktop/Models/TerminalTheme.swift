import AppKit
import SwiftUI

enum TerminalThemeStyle: String, Codable, Equatable {
    case system
    case graphite
    case evergreen
    case dusk
    case paper
    case harbor
    case ember
    case custom
}

struct TerminalThemeHSB: Equatable, Hashable {
    let hue: Double
    let saturation: Double
    let brightness: Double
}

struct TerminalThemeColor: Codable, Equatable, Hashable {
    let red: Double
    let green: Double
    let blue: Double
    let hexString: String
    let hsb: TerminalThemeHSB

    // Backward-compatible wire format: only the raw RGB channels are encoded.
    // Derived values (hexString, hsb) are recomputed on decode so previously
    // persisted themes keep loading after the model gains cached properties.
    private enum CodingKeys: String, CodingKey {
        case red, green, blue
    }

    init(red: Double, green: Double, blue: Double) {
        let r = Self.clamp(red)
        let g = Self.clamp(green)
        let b = Self.clamp(blue)
        self.red = r
        self.green = g
        self.blue = b
        self.hexString = String(
            format: "#%06X",
            (Self.rgbComponent(r) << 16) | (Self.rgbComponent(g) << 8) | Self.rgbComponent(b)
        )
        self.hsb = Self.computeHSB(red: r, green: g, blue: b)
    }

    init(hex: Int) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }

    init(hue: Double, saturation: Double, brightness: Double) {
        let hue = Self.clamp(hue)
        let saturation = Self.clamp(saturation)
        let brightness = Self.clamp(brightness)
        let sector = hue * 6
        let wholeSector = Int(floor(sector))
        let fractionalSector = sector - Double(wholeSector)
        let low = brightness * (1 - saturation)
        let falling = brightness * (1 - saturation * fractionalSector)
        let rising = brightness * (1 - saturation * (1 - fractionalSector))

        switch wholeSector % 6 {
        case 0:
            self.init(red: brightness, green: rising, blue: low)
        case 1:
            self.init(red: falling, green: brightness, blue: low)
        case 2:
            self.init(red: low, green: brightness, blue: rising)
        case 3:
            self.init(red: low, green: falling, blue: brightness)
        case 4:
            self.init(red: rising, green: low, blue: brightness)
        default:
            self.init(red: brightness, green: low, blue: falling)
        }
    }

    init?(hexString: String) {
        let rawValue = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = rawValue.hasPrefix("#") ? String(rawValue.dropFirst()) : rawValue

        guard trimmed.count == 6, let value = Int(trimmed, radix: 16) else {
            return nil
        }

        self.init(hex: value)
    }

    init(nsColor: NSColor) {
        let resolved = nsColor.usingColorSpace(.deviceRGB) ?? NSColor.black
        self.init(
            red: Double(resolved.redComponent),
            green: Double(resolved.greenComponent),
            blue: Double(resolved.blueComponent)
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            red: try container.decode(Double.self, forKey: .red),
            green: try container.decode(Double.self, forKey: .green),
            blue: try container.decode(Double.self, forKey: .blue)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(red, forKey: .red)
        try container.encode(green, forKey: .green)
        try container.encode(blue, forKey: .blue)
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
        // Use the static sRGB initializer rather than Color(nsColor:) so the
        // SwiftUI color box is value-comparable and not re-resolved on every
        // body re-evaluation. Color(nsColor:) is a dynamic, appearance-aware
        // wrapper that creates a new storage instance each access, which
        // prevented SwiftUI from short-circuiting unchanged cells in the
        // 200-swatch color matrix in Settings.
        Color(red: red, green: green, blue: blue)
    }

    private static func computeHSB(red: Double, green: Double, blue: Double) -> TerminalThemeHSB {
        let maxComponent = max(red, green, blue)
        let minComponent = min(red, green, blue)
        let delta = maxComponent - minComponent
        let brightness = maxComponent
        let saturation = maxComponent == 0 ? 0 : delta / maxComponent

        let rawHue: Double
        if delta == 0 {
            rawHue = 0
        } else if maxComponent == red {
            rawHue = ((green - blue) / delta) / 6
        } else if maxComponent == green {
            rawHue = (((blue - red) / delta) + 2) / 6
        } else {
            rawHue = (((red - green) / delta) + 4) / 6
        }

        let normalizedHue = rawHue < 0 ? rawHue + 1 : rawHue
        return TerminalThemeHSB(
            hue: normalizedHue,
            saturation: saturation,
            brightness: brightness
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func rgbComponent(_ value: Double) -> Int {
        min(max(Int((clamp(value) * 255).rounded()), 0), 255)
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
    let backgroundImagePath: String?
}

struct TerminalThemePreference: Codable, Equatable {
    var style: TerminalThemeStyle = .system
    var customBackgroundColor: TerminalThemeColor?
    var customForegroundColor: TerminalThemeColor?
    var paletteStyle: TerminalThemeStyle?
    var backgroundImagePath: String?

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
                isCustom: false,
                backgroundImagePath: backgroundImagePath
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
                isCustom: true,
                backgroundImagePath: backgroundImagePath
            )
        case .graphite, .evergreen, .dusk, .paper, .harbor, .ember:
            let preset = Self.preset(for: style) ?? Self.graphitePreset
            return TerminalThemeAppearance(
                style: preset.style,
                name: preset.name,
                backgroundColor: preset.backgroundColor,
                foregroundColor: preset.foregroundColor,
                ansiPalette: preset.ansiPalette,
                paletteStyle: preset.style,
                isCustom: false,
                backgroundImagePath: backgroundImagePath
            )
        }
    }

    func selectingPreset(_ style: TerminalThemeStyle) -> TerminalThemePreference {
        var pref = TerminalThemePreference(style: style)
        pref.backgroundImagePath = backgroundImagePath
        return pref
    }

    func updatingBackgroundColor(_ color: TerminalThemeColor) -> TerminalThemePreference {
        let appearance = resolvedAppearance
        return TerminalThemePreference(
            style: .custom,
            customBackgroundColor: color,
            customForegroundColor: appearance.foregroundColor,
            paletteStyle: appearance.paletteStyle,
            backgroundImagePath: backgroundImagePath
        )
    }

    func updatingForegroundColor(_ color: TerminalThemeColor) -> TerminalThemePreference {
        let appearance = resolvedAppearance
        return TerminalThemePreference(
            style: .custom,
            customBackgroundColor: appearance.backgroundColor,
            customForegroundColor: color,
            paletteStyle: appearance.paletteStyle,
            backgroundImagePath: backgroundImagePath
        )
    }

    func updatingPaletteStyle(_ style: TerminalThemeStyle) -> TerminalThemePreference {
        let appearance = resolvedAppearance
        return TerminalThemePreference(
            style: .custom,
            customBackgroundColor: appearance.backgroundColor,
            customForegroundColor: appearance.foregroundColor,
            paletteStyle: style,
            backgroundImagePath: backgroundImagePath
        )
    }

    func settingCustomColors(backgroundColor: TerminalThemeColor, foregroundColor: TerminalThemeColor) -> TerminalThemePreference {
        let appearance = resolvedAppearance
        return TerminalThemePreference(
            style: .custom,
            customBackgroundColor: backgroundColor,
            customForegroundColor: foregroundColor,
            paletteStyle: appearance.paletteStyle,
            backgroundImagePath: backgroundImagePath
        )
    }

    static let quickPresets: [TerminalThemePreset] = [
        graphitePreset,
        evergreenPreset,
        duskPreset,
        paperPreset,
        auberginePreset,
        porcelainPreset
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

    private static let auberginePreset = TerminalThemePreset(
        style: .harbor,
        name: "Aubergine",
        summary: "Deep plum terminal with clear cyan, gold, and violet accents.",
        backgroundColor: TerminalThemeColor(hex: 0x17111F),
        foregroundColor: TerminalThemeColor(hex: 0xEFE7FF),
        ansiPalette: palette([
            0x241C30, 0xD06C7C, 0x84B979, 0xD8B767,
            0x82A7E8, 0xC08DE0, 0x73C7C6, 0xD8D0E6,
            0x645572, 0xE58A98, 0x9DD491, 0xE6CA82,
            0x9BBDF2, 0xD2A6EC, 0x8DDEDC, 0xFCF8FF
        ])
    )

    private static let porcelainPreset = TerminalThemePreset(
        style: .ember,
        name: "Porcelain",
        summary: "Cool light theme with crisp graphite text and measured color.",
        backgroundColor: TerminalThemeColor(hex: 0xF7F9FC),
        foregroundColor: TerminalThemeColor(hex: 0x253040),
        ansiPalette: palette([
            0x2E3646, 0xB84E5F, 0x4F8A6B, 0x9B7228,
            0x3F73B8, 0x7C5BA6, 0x2D8794, 0xE1E7F0,
            0x5B6575, 0xC96575, 0x69A37F, 0xB88B3F,
            0x5D8BD0, 0x9874BC, 0x4AA0AA, 0xFFFFFF
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
