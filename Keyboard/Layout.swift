import UIKit

enum KeyboardMode {
    case letters, numbers, symbols
    /// Big 3×4 keypad for number and phone fields.
    case numberPad
}

/// What kind of text box the keyboard is typing into.
enum FieldKind: Equatable {
    case normal
    /// Web address: "/" and ".com" keys.
    case url
    /// Email: "@" key.
    case email
    case number, phone, decimal

    init(_ type: UIKeyboardType) {
        switch type {
        case .URL, .webSearch: self = type == .URL ? .url : .normal
        case .emailAddress: self = .email
        case .numberPad, .asciiCapableNumberPad: self = .number
        case .phonePad, .namePhonePad: self = type == .phonePad ? .phone : .normal
        case .decimalPad: self = .decimal
        default: self = .normal
        }
    }

    var usesNumberPad: Bool { self == .number || self == .phone || self == .decimal }
}

enum ShiftState {
    case off, once, locked
}

enum KeyAction: Equatable {
    /// Types `text` (or `hint` when held long enough).
    case character
    case shift
    case backspace
    case space
    case returnKey
    case mode(KeyboardMode)
    /// The emoji key: switches to the next keyboard (Apple's Emoji keyboard).
    case nextKeyboard
}

enum KeyWidth: Equatable {
    /// A multiple of a normal letter key's width.
    case units(CGFloat)
    /// Takes whatever space is left in the row.
    case flex
}

struct KeyDef {
    let action: KeyAction
    let text: String
    let hint: String?
    let width: KeyWidth

    var isLetter: Bool {
        action == .character && text.count == 1 && (text.first?.isLetter ?? false)
    }

    static func char(_ text: String, hint: String? = nil, width: CGFloat = 1) -> KeyDef {
        KeyDef(action: .character, text: text, hint: hint, width: .units(width))
    }

    /// A key that shares the row's width equally with the other flexible keys.
    static func flexChar(_ text: String) -> KeyDef {
        KeyDef(action: .character, text: text, hint: nil, width: .flex)
    }

    static func special(_ action: KeyAction, _ text: String = "", width: KeyWidth) -> KeyDef {
        KeyDef(action: action, text: text, hint: nil, width: width)
    }
}

struct KeyRow {
    let keys: [KeyDef]
    /// First and last keys stick to the edges, the rest are centred (shift row).
    var pinEnds: Bool = false
}

enum Layout {
    /// Hold-for-symbol map (Gboard style, `$` on D).
    static let symbolHints: [Character: String] = [
        "q": "%", "w": "\\", "e": "|", "r": "=", "t": "[", "y": "]", "u": "<", "i": ">", "o": "{", "p": "}",
        "a": "@", "s": "#", "d": "$", "f": "_", "g": "&", "h": "-", "j": "+", "k": "(", "l": ")",
        "z": "*", "x": "\"", "c": "'", "v": ":", "b": ";", "n": "!", "m": "?",
    ]

    /// Extra characters offered when a key is held (after its corner symbol, if any).
    /// Letters are listed lowercase and shown uppercase when Shift is on.
    static let alternates: [String: [String]] = [
        "a": ["à", "á", "â", "ä", "æ", "ã", "å", "ā"],
        "c": ["ç", "ć", "č"],
        "e": ["è", "é", "ê", "ë", "ē", "ė", "ę"],
        "i": ["ì", "í", "î", "ï", "ī", "į"],
        "l": ["ł"],
        "n": ["ñ", "ń"],
        "o": ["ò", "ó", "ô", "ö", "õ", "ø", "œ", "ō"],
        "s": ["ß", "ś", "š"],
        "u": ["ù", "ú", "û", "ü", "ū"],
        "y": ["ÿ"],
        "z": ["ž", "ź", "ż"],
        ".": ["?", "!", "'", "\"", ":", ";", "-", "…"],
        ",": ["'", "\"", "-", "/", "@"],
        ".com": [".com.au", ".net", ".org", ".au", ".net.au", ".edu", ".co"],
        "@": ["#", "_", "-", "+"],
        "+": ["*", "#", ",", ";"],
        // Numbers and symbols pages (like Apple's keyboard).
        "0": ["°"],
        "-": ["–", "—", "•"],
        "/": ["\\"],
        "$": ["€", "£", "¥", "₩", "₹", "¢"],
        "&": ["§"],
        "\"": ["“", "”", "„", "«", "»"],
        "'": ["‘", "’", "`"],
        "?": ["¿"],
        "!": ["¡"],
        "%": ["‰"],
    ]

    static let sideKeyWidth: CGFloat = 1.36
    static let bottomModeWidth: CGFloat = 1.31
    static let returnWidth: CGFloat = 1.89

    static func rows(mode: KeyboardMode, numberRow: Bool, field: FieldKind = .normal) -> [KeyRow] {
        switch mode {
        case .numberPad:
            let corner: KeyDef
            switch field {
            case .phone: corner = .flexChar("+")
            case .decimal: corner = .flexChar(".")
            default: corner = .special(.mode(.letters), "ABC", width: .flex)
            }
            return [
                KeyRow(keys: "123".map { .flexChar(String($0)) }),
                KeyRow(keys: "456".map { .flexChar(String($0)) }),
                KeyRow(keys: "789".map { .flexChar(String($0)) }),
                KeyRow(keys: [corner, .flexChar("0"), .special(.backspace, width: .flex)]),
            ]

        case .letters:
            var rows: [KeyRow] = []
            if numberRow {
                rows.append(charRow("1234567890"))
            }
            rows.append(letterRow("qwertyuiop"))
            rows.append(letterRow("asdfghjkl"))
            rows.append(KeyRow(
                keys: [KeyDef.special(.shift, width: .units(sideKeyWidth))]
                    + letterRow("zxcvbnm").keys
                    + [KeyDef.special(.backspace, width: .units(sideKeyWidth))],
                pinEnds: true))
            rows.append(bottomRow(modeKey: .special(.mode(.numbers), "123", width: .units(bottomModeWidth)), field: field))
            return rows

        case .numbers:
            return [
                charRow("1234567890"),
                KeyRow(keys: ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""].map { KeyDef.char($0) }),
                punctuationRow(modeKey: .special(.mode(.symbols), "#+=", width: .units(sideKeyWidth))),
                bottomRow(modeKey: .special(.mode(.letters), "ABC", width: .units(bottomModeWidth)), field: field),
            ]

        case .symbols:
            return [
                KeyRow(keys: ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="].map { KeyDef.char($0) }),
                KeyRow(keys: ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"].map { KeyDef.char($0) }),
                punctuationRow(modeKey: .special(.mode(.numbers), "123", width: .units(sideKeyWidth))),
                bottomRow(modeKey: .special(.mode(.letters), "ABC", width: .units(bottomModeWidth)), field: field),
            ]
        }
    }

    private static func letterRow(_ letters: String) -> KeyRow {
        KeyRow(keys: letters.map { KeyDef.char(String($0), hint: symbolHints[$0]) })
    }

    private static func charRow(_ chars: String) -> KeyRow {
        KeyRow(keys: chars.map { KeyDef.char(String($0)) })
    }

    private static func punctuationRow(modeKey: KeyDef) -> KeyRow {
        KeyRow(
            keys: [modeKey]
                + [".", ",", "?", "!", "'"].map { KeyDef.char($0, width: 1.42) }
                + [KeyDef.special(.backspace, width: .units(sideKeyWidth))],
            pinEnds: true)
    }

    private static func bottomRow(modeKey: KeyDef, field: FieldKind) -> KeyRow {
        switch field {
        case .url:
            // Web addresses: "/" and ".com" (hold for .com.au, .net…), like Apple / Gboard.
            return KeyRow(keys: [
                modeKey,
                .char("/"),
                .special(.nextKeyboard, width: .units(1.1)),
                .special(.space, width: .flex),
                .char("."),
                .char(".com", width: 1.45),
                .special(.returnKey, width: .units(1.6)),
            ])
        case .email:
            return KeyRow(keys: [
                modeKey,
                .char("@"),
                .special(.nextKeyboard, width: .units(1.1)),
                .special(.space, width: .flex),
                .char("."),
                .special(.returnKey, width: .units(returnWidth)),
            ])
        default:
            break
        }
        // Gboard-style: comma between 123 and emoji, with a slightly narrower
        // emoji key and space bar to make room.
        return KeyRow(keys: [
            modeKey,
            .char(","),
            .special(.nextKeyboard, width: .units(1.1)),
            .special(.space, width: .flex),
            .char(".", hint: ","),
            .special(.returnKey, width: .units(returnWidth)),
        ])
    }
}
