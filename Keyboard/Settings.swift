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
        static let keySound = "keySound"
        static let vibrate = "vibrate"
        static let keyBorders = "keyBorders"
        static let theme = "theme"
        static let autoSpace = "autoSpace"
        static let soundVolume = "soundVolume"
        static let vibrationStrength = "vibrationStrength"
        static let blockOffensive = "blockOffensive"
        static let showSuggestions = "showSuggestions"
        static let learnWords = "learnWords"
        static let phrasePredictions = "phrasePredictions"
        static let emojiPanel = "emojiPanel"
        static let pasteSuggestion = "pasteSuggestion"
        static let topRowNumbers = "topRowNumbers"
        static let clipboardAutoDelete = "clipboardAutoDelete"
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
            Key.keySound: false,
            Key.vibrate: false,
            Key.keyBorders: true,
            Key.theme: ThemeStyle.system.rawValue,
            Key.autoSpace: false,
            Key.soundVolume: 0.6,
            Key.vibrationStrength: 0.6,
            Key.blockOffensive: true,
            Key.showSuggestions: true,
            Key.learnWords: true,
            Key.phrasePredictions: true,
            Key.emojiPanel: true,
            Key.pasteSuggestion: true,
            Key.topRowNumbers: true,
            Key.clipboardAutoDelete: false,
        ])
    }

    /// Hold q–p for 1–0 (Gboard). Off = the symbols % \ | = [ ] < > { }.
    var topRowNumbers: Bool {
        get { defaults.bool(forKey: Key.topRowNumbers) }
        set { defaults.set(newValue, forKey: Key.topRowNumbers) }
    }

    /// Delete unpinned clipboard items after an hour (Gboard).
    var clipboardAutoDelete: Bool {
        get { defaults.bool(forKey: Key.clipboardAutoDelete) }
        set { defaults.set(newValue, forKey: Key.clipboardAutoDelete) }
    }

    /// Key click volume, 0...1.
    var soundVolume: Double {
        get { min(max(defaults.double(forKey: Key.soundVolume), 0), 1) }
        set { defaults.set(min(max(newValue, 0), 1), forKey: Key.soundVolume) }
    }

    /// Key vibration strength, 0...1.
    var vibrationStrength: Double {
        get { min(max(defaults.double(forKey: Key.vibrationStrength), 0), 1) }
        set { defaults.set(min(max(newValue, 0), 1), forKey: Key.vibrationStrength) }
    }

    /// Never suggest swear words.
    var blockOffensive: Bool {
        get { defaults.bool(forKey: Key.blockOffensive) }
        set { defaults.set(newValue, forKey: Key.blockOffensive) }
    }

    /// Show word suggestions in the bar (autocorrect still works when off).
    var showSuggestions: Bool {
        get { defaults.bool(forKey: Key.showSuggestions) }
        set { defaults.set(newValue, forKey: Key.showSuggestions) }
    }

    /// Learn words you type that aren't in the dictionary.
    var learnWords: Bool {
        get { defaults.bool(forKey: Key.learnWords) }
        set { defaults.set(newValue, forKey: Key.learnWords) }
    }

    /// Suggest the next few words together ("see you" → "see you soon").
    var phrasePredictions: Bool {
        get { defaults.bool(forKey: Key.phrasePredictions) }
        set { defaults.set(newValue, forKey: Key.phrasePredictions) }
    }

    /// The emoji key opens BetterBoard's emoji panel (off = iPhone's emoji keyboard).
    var emojiPanel: Bool {
        get { defaults.bool(forKey: Key.emojiPanel) }
        set { defaults.set(newValue, forKey: Key.emojiPanel) }
    }

    /// Offer just-copied text in the suggestion bar.
    var pasteSuggestion: Bool {
        get { defaults.bool(forKey: Key.pasteSuggestion) }
        set { defaults.set(newValue, forKey: Key.pasteSuggestion) }
    }

    /// Click sound on every key press (needs Full Access).
    var keySound: Bool {
        get { defaults.bool(forKey: Key.keySound) }
        set { defaults.set(newValue, forKey: Key.keySound) }
    }

    /// A light tap of the haptic engine on every key press (needs Full Access).
    var vibrate: Bool {
        get { defaults.bool(forKey: Key.vibrate) }
        set { defaults.set(newValue, forKey: Key.vibrate) }
    }

    /// Keys drawn as buttons (on) or as plain text on the background (Gboard "Key borders").
    var keyBorders: Bool {
        get { defaults.bool(forKey: Key.keyBorders) }
        set { defaults.set(newValue, forKey: Key.keyBorders) }
    }

    var theme: ThemeStyle {
        get { ThemeStyle(rawValue: defaults.integer(forKey: Key.theme)) ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Key.theme) }
    }

    /// Type a space automatically after . , ! ? : ; when a letter follows straight away.
    var autoSpace: Bool {
        get { defaults.bool(forKey: Key.autoSpace) }
        set { defaults.set(newValue, forKey: Key.autoSpace) }
    }

    /// Show predicted next words before you start typing (Gboard "Next-word suggestions").
    var nextWord: Bool {
        get { defaults.bool(forKey: Key.nextWord) }
        set { defaults.set(newValue, forKey: Key.nextWord) }
    }

    /// Your Giphy API key (sent from the BetterBoard app during GIF setup).
    var giphyKey: String? {
        get { defaults.string(forKey: "giphyKey") }
        set { defaults.set(newValue, forKey: "giphyKey") }
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
