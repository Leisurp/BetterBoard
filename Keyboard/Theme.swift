import UIKit

/// The keyboard themes you can pick in settings.
enum ThemeStyle: Int, CaseIterable {
    case system = 0, light, dark, black, ocean, forest, sunset, lavender, rose, mint

    var title: String {
        switch self {
        case .system: return "Default"
        case .light: return "Light"
        case .dark: return "Dark"
        case .black: return "Black"
        case .ocean: return "Ocean"
        case .forest: return "Forest"
        case .sunset: return "Sunset"
        case .lavender: return "Lavender"
        case .rose: return "Rose"
        case .mint: return "Mint"
        }
    }
}

private func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> UIColor {
    UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

/// Keyboard colours. The default theme matches Apple's keyboard (iOS 26+) and
/// follows light / dark mode; the others have their own background.
struct Theme {
    let style: ThemeStyle
    let isDark: Bool
    let keyBorders: Bool

    /// Behind the keys. nil = iOS's own keyboard background.
    let background: UIColor?
    let keyColor: UIColor
    let keyPressedColor: UIColor
    let labelColor: UIColor
    let hintColor: UIColor
    let accentColor: UIColor
    let popupColor: UIColor
    let separatorColor: UIColor
    let keyShadowColor: UIColor
    /// Active (shifted) shift key.
    let shiftActiveColor: UIColor
    let shiftActiveIconColor: UIColor

    /// Apple's colours (also used before settings are read).
    init(isDark: Bool) {
        self.init(style: .system, systemIsDark: isDark, keyBorders: true)
    }

    init(style: ThemeStyle, systemIsDark: Bool, keyBorders: Bool) {
        self.style = style
        self.keyBorders = keyBorders
        let blue = rgb(0x3478F6)

        // (background, key, pressed, label, accent, dark?)
        let palette: (bg: UIColor?, key: UIColor, pressed: UIColor, label: UIColor, accent: UIColor, dark: Bool)
        switch style {
        case .system:
            palette = systemIsDark
                ? (nil, UIColor(white: 0.285, alpha: 1), UIColor(white: 0.42, alpha: 1), .white, blue, true)
                : (nil, .white, UIColor(white: 0.80, alpha: 1), .black, blue, false)
        case .light:
            palette = (rgb(0xD1D3D9), .white, UIColor(white: 0.80, alpha: 1), .black, blue, false)
        case .dark:
            palette = (rgb(0x2B2B2E), rgb(0x48484C), rgb(0x67676C), .white, blue, true)
        case .black:
            palette = (.black, rgb(0x1C1C1E), rgb(0x3A3A3C), .white, blue, true)
        case .ocean:
            palette = (rgb(0x1B3553), rgb(0x2D5584), rgb(0x4672A4), .white, rgb(0x4FC3F7), true)
        case .forest:
            palette = (rgb(0x1D3628), rgb(0x2E5540), rgb(0x45745A), .white, rgb(0x66BB6A), true)
        case .sunset:
            palette = (rgb(0x5E2A33), rgb(0x8A4048), rgb(0xA95A5F), .white, rgb(0xFFA94D), true)
        case .lavender:
            palette = (rgb(0xE4DAF4), .white, rgb(0xCDBDEB), rgb(0x2D1F4A), rgb(0x7E57C2), false)
        case .rose:
            palette = (rgb(0xF6D9E1), .white, rgb(0xEBB8C6), rgb(0x4A1F2B), rgb(0xE0457B), false)
        case .mint:
            palette = (rgb(0xD3F0E3), .white, rgb(0xA8DCC5), rgb(0x143D2C), rgb(0x1E9E8A), false)
        }

        isDark = palette.dark
        background = palette.bg
        keyColor = keyBorders ? palette.key : .clear
        keyPressedColor = palette.pressed
        labelColor = palette.label
        hintColor = palette.label.withAlphaComponent(palette.dark ? 0.62 : 0.55)
        accentColor = palette.accent
        popupColor = palette.dark ? palette.pressed : palette.key
        separatorColor = palette.label.withAlphaComponent(palette.dark ? 0.18 : 0.15)
        keyShadowColor = (palette.dark || !keyBorders) ? .clear : UIColor(white: 0, alpha: 0.28)
        shiftActiveColor = keyBorders ? .white : palette.label.withAlphaComponent(0.25)
        shiftActiveIconColor = keyBorders ? .black : palette.label
    }

    /// Two themes look the same.
    func matches(_ other: Theme) -> Bool {
        style == other.style && isDark == other.isDark && keyBorders == other.keyBorders
    }
}

enum Touch {
    /// iOS ignores touches on fully transparent pixels of a keyboard extension, so
    /// taps in the gaps between keys (and on the empty bar) were silently dropped.
    /// A barely-visible fill makes every point of the keyboard touchable.
    static let touchableBackground = UIColor(white: 0.5, alpha: 0.02)
}

/// Sizes in points. Measured from an iPhone 17 Pro Max (440 pt wide) screenshot.
enum Metrics {
    static let sideMargin: CGFloat = 6.5
    static let keyGap: CGFloat = 6.5
    static let keyHeight: CGFloat = 44
    static let rowGap: CGFloat = 11.5
    static let cornerRadius: CGFloat = 8.5
    // Measured against Apple's iOS 27 keyboard. iOS adds ~16 pt of its own
    // padding above third-party keyboards, so the bar is shorter than Apple's.
    static let topInset: CGFloat = 6.5
    static let bottomInset: CGFloat = 6.5
    static let barHeight: CGFloat = 30

    static let letterFontSize: CGFloat = 25
    static let labelFontSize: CGFloat = 18
    static let hintFontSize: CGFloat = 11
    static let iconPointSize: CGFloat = 19
    static let popupFontSize: CGFloat = 38
}
