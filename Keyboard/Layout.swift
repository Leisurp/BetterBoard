import UIKit

enum KeyboardMode {
    case letters, numbers, symbols
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

    static let sideKeyWidth: CGFloat = 1.36
    static let bottomModeWidth: CGFloat = 1.31
    static let returnWidth: CGFloat = 1.89

    static func rows(mode: KeyboardMode, numberRow: Bool) -> [KeyRow] {
        switch mode {
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
            rows.append(bottomRow(modeKey: .special(.mode(.numbers), "123", width: .units(bottomModeWidth))))
            return rows

        case .numbers:
            return [
                charRow("1234567890"),
                KeyRow(keys: ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""].map { KeyDef.char($0) }),
                punctuationRow(modeKey: .special(.mode(.symbols), "#+=", width: .units(sideKeyWidth))),
                bottomRow(modeKey: .special(.mode(.letters), "ABC", width: .units(bottomModeWidth))),
            ]

        case .symbols:
            return [
                KeyRow(keys: ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="].map { KeyDef.char($0) }),
                KeyRow(keys: ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"].map { KeyDef.char($0) }),
                punctuationRow(modeKey: .special(.mode(.numbers), "123", width: .units(sideKeyWidth))),
                bottomRow(modeKey: .special(.mode(.letters), "ABC", width: .units(bottomModeWidth))),
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

    private static func bottomRow(modeKey: KeyDef) -> KeyRow {
        // Gboard-style: comma between 123 and emoji, with a slightly narrower
        // emoji key and space bar to make room.
        KeyRow(keys: [
            modeKey,
            .char(","),
            .special(.nextKeyboard, width: .units(1.1)),
            .special(.space, width: .flex),
            .char(".", hint: ","),
            .special(.returnKey, width: .units(returnWidth)),
        ])
    }
}
