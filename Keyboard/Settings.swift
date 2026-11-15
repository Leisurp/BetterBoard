import UIKit

/// Keyboard settings, stored in the extension's own UserDefaults
/// (no App Groups / Full Access needed).
final class KeyboardSettings {
    static let shared = KeyboardSettings()

    enum HeightSize: Int, CaseIterable {
        case short = 0, normal = 1, tall = 2

        var title: String {
            switch self {
            case .short: return "Short"
            case .normal: return "Normal"
            case .tall: return "Tall"
            }
        }

        var scale: CGFloat {
            switch self {
            case .short: return 0.88
            case .normal: return 1.0
            case .tall: return 1.12
            }
        }
    }

    private let defaults = UserDefaults.standard

    private enum Key {
        static let holdForSymbols = "holdForSymbols"
        static let longPressDelayMs = "longPressDelayMs"
        static let showHints = "showHints"
        static let keyPopup = "keyPopup"
        static let numberRow = "numberRow"
        static let heightSize = "heightSize"
        static let autocorrect = "autocorrect"
        static let autocap = "autocap"
        static let doubleSpacePeriod = "doubleSpacePeriod"
        static let capsLock = "capsLock"
        static let nextWord = "nextWord"
        static let emojiSuggestions = "emojiSuggestions"
    }

    private init() {
        defaults.register(defaults: [
            Key.holdForSymbols: true,
            Key.longPressDelayMs: 300,
            Key.showHints: true,
            Key.keyPopup: true,
            Key.numberRow: false,
            Key.heightSize: HeightSize.normal.rawValue,
            Key.autocorrect: true,
            Key.autocap: true,
            Key.doubleSpacePeriod: true,
            Key.capsLock: true,
            Key.nextWord: true,
            Key.emojiSuggestions: true,
        ])
    }

    /// Show predicted next words before you start typing (Gboard "Next-word suggestions").
    var nextWord: Bool {
        get { defaults.bool(forKey: Key.nextWord) }
        set { defaults.set(newValue, forKey: Key.nextWord) }
    }

    /// Show emoji for words in the suggestion bar (Gboard "Show emoji suggestions").
    var emojiSuggestions: Bool {
        get { defaults.bool(forKey: Key.emojiSuggestions) }
        set { defaults.set(newValue, forKey: Key.emojiSuggestions) }
    }

    var holdForSymbols: Bool {
        get { defaults.bool(forKey: Key.holdForSymbols) }
        set { defaults.set(newValue, forKey: Key.holdForSymbols) }
    }

    /// Milliseconds a key must be held before it switches to its symbol.
    var longPressDelayMs: Int {
        get { min(max(defaults.integer(forKey: Key.longPressDelayMs), 100), 1000) }
        set { defaults.set(min(max(newValue, 100), 1000), forKey: Key.longPressDelayMs) }
    }

    var showHints: Bool {
        get { defaults.bool(forKey: Key.showHints) }
        set { defaults.set(newValue, forKey: Key.showHints) }
    }

    var keyPopup: Bool {
        get { defaults.bool(forKey: Key.keyPopup) }
        set { defaults.set(newValue, forKey: Key.keyPopup) }
    }

    var numberRow: Bool {
        get { defaults.bool(forKey: Key.numberRow) }
        set { defaults.set(newValue, forKey: Key.numberRow) }
    }

    var heightSize: HeightSize {
        get { HeightSize(rawValue: defaults.integer(forKey: Key.heightSize)) ?? .normal }
        set { defaults.set(newValue.rawValue, forKey: Key.heightSize) }
    }

    var autocorrect: Bool {
        get { defaults.bool(forKey: Key.autocorrect) }
        set { defaults.set(newValue, forKey: Key.autocorrect) }
    }

    var autocap: Bool {
        get { defaults.bool(forKey: Key.autocap) }
        set { defaults.set(newValue, forKey: Key.autocap) }
    }

    var doubleSpacePeriod: Bool {
        get { defaults.bool(forKey: Key.doubleSpacePeriod) }
        set { defaults.set(newValue, forKey: Key.doubleSpacePeriod) }
    }

    var capsLock: Bool {
        get { defaults.bool(forKey: Key.capsLock) }
        set { defaults.set(newValue, forKey: Key.capsLock) }
    }
}
