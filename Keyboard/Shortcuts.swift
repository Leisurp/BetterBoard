import UIKit

/// A saved phrase: your email, phone, address… and optionally a shortcut that
/// brings it up ("addr" → your address). Must match ShortcutEntry in the app.
struct ShortcutEntry: Codable, Equatable {
    var shortcut: String
    var phrase: String
}

/// Shortcuts and personal info made in the BetterBoard app. They arrive over the
/// clipboard (like the custom theme), because with a free Apple ID the app and
/// keyboard can't share settings.
enum ShortcutStore {
    static let pasteboardType = "com.leisurp.betterboard.shortcuts"
    private static let defaultsKey = "shortcuts"
    private static var cached: [ShortcutEntry]?

    static var entries: [ShortcutEntry] {
        if let cached { return cached }
        var loaded: [ShortcutEntry] = []
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([ShortcutEntry].self, from: data) {
            loaded = decoded
        }
        cached = loaded
        return loaded
    }

    /// Takes shortcuts off the clipboard if the app put them there.
    static func receive(from pasteboard: UIPasteboard) -> Bool {
        guard pasteboard.contains(pasteboardTypes: [pasteboardType]),
              let data = pasteboard.data(forPasteboardType: pasteboardType),
              let decoded = try? JSONDecoder().decode([ShortcutEntry].self, from: data) else { return false }
        UserDefaults.standard.set(data, forKey: defaultsKey)
        cached = decoded
        pasteboard.items = []
        return true
    }

    /// Phrases to suggest for what's being typed.
    /// - token: the text since the last space ("dolf", "addr", "me@ex").
    /// - emailField: in email boxes, saved emails are offered before you type anything.
    static func matches(for token: String, emailField: Bool) -> [String] {
        let all = entries
        guard !all.isEmpty else { return [] }
        let typed = token.lowercased()
        var result: [String] = []
        func add(_ phrase: String) {
            if !result.contains(phrase) { result.append(phrase) }
        }
        if typed.isEmpty {
            if emailField {
                for entry in all where entry.phrase.contains("@") { add(entry.phrase) }
            }
            return Array(result.prefix(2))
        }
        // A shortcut typed exactly.
        for entry in all where !entry.shortcut.isEmpty && entry.shortcut.lowercased() == typed {
            add(entry.phrase)
        }
        // The start of a saved phrase ("dolf" → your email).
        let minimum = emailField ? 1 : 2
        if typed.count >= minimum {
            for entry in all {
                let phrase = entry.phrase.lowercased()
                if phrase.hasPrefix(typed) && phrase != typed { add(entry.phrase) }
            }
        }
        return Array(result.prefix(2))
    }
}
