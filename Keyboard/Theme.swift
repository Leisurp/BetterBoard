import UIKit

/// Colours for light / dark keyboards (matched to the iOS 26+ keyboard).
struct Theme {
    let isDark: Bool

    var keyColor: UIColor { isDark ? UIColor(white: 0.285, alpha: 1) : .white }
    var keyPressedColor: UIColor { isDark ? UIColor(white: 0.42, alpha: 1) : UIColor(white: 0.80, alpha: 1) }
    var labelColor: UIColor { isDark ? .white : .black }
    var hintColor: UIColor { isDark ? UIColor(white: 0.66, alpha: 1) : UIColor(white: 0.45, alpha: 1) }
    var accentColor: UIColor { UIColor(red: 0.204, green: 0.471, blue: 0.965, alpha: 1) }
    var popupColor: UIColor { isDark ? UIColor(white: 0.36, alpha: 1) : .white }
    var separatorColor: UIColor { isDark ? UIColor(white: 1, alpha: 0.18) : UIColor(white: 0, alpha: 0.15) }
    var keyShadowColor: UIColor { isDark ? .clear : UIColor(white: 0, alpha: 0.28) }
    /// Active (shifted) shift key.
    var shiftActiveColor: UIColor { isDark ? .white : .white }
    var shiftActiveIconColor: UIColor { .black }
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
