import Foundation

struct EmojiEntry {
    let emoji: String
    /// Lowercased search words (name + keywords).
    let words: [String]
    /// The five skin-tone versions (light → dark), or empty.
    let tones: [String]
}

struct EmojiGroup {
    let name: String
    let icon: String
    let entries: [EmojiEntry]
}

/// The emoji list (from Unicode data), recently used emoji and your skin-tone choices.
final class EmojiStore {
    static let shared = EmojiStore()

    private(set) var groups: [EmojiGroup] = []
    private var byEmoji: [String: EmojiEntry] = [:]
    private let defaults = UserDefaults.standard
    private let recentsKey = "recentEmoji"
    private let tonesKey = "emojiTones"
    private let maxRecents = 32

    private(set) var recents: [String]
    /// Base emoji → the skin-tone version you last picked.
    private var toneChoices: [String: String]

    private static let icons: [String: String] = [
        "Smileys & Emotion": "face.smiling",
        "People & Body": "hand.wave",
        "Animals & Nature": "pawprint",
        "Food & Drink": "fork.knife",
        "Travel & Places": "car",
        "Activities": "soccerball",
        "Objects": "lightbulb",
        "Symbols": "heart",
        "Flags": "flag",
    ]

    private init() {
        recents = defaults.stringArray(forKey: recentsKey) ?? []
        toneChoices = (defaults.dictionary(forKey: tonesKey) as? [String: String]) ?? [:]
        load()
    }

    private func load() {
        guard let url = Bundle(for: EmojiStore.self).url(forResource: "emoji_list", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        var name = ""
        var entries: [EmojiEntry] = []
        func finishGroup() {
            if !entries.isEmpty {
                groups.append(EmojiGroup(name: name, icon: Self.icons[name] ?? "circle", entries: entries))
            }
            entries = []
        }
        for line in text.split(whereSeparator: { $0.isNewline }) {
            if line.hasPrefix("# ") {
                finishGroup()
                name = String(line.dropFirst(2))
                continue
            }
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 2 else { continue }
            let entry = EmojiEntry(
                emoji: String(parts[0]),
                words: parts[1].split(separator: " ").map(String.init),
                tones: parts.count > 2 ? parts[2].split(separator: " ").map(String.init) : [])
            entries.append(entry)
            byEmoji[entry.emoji] = entry
        }
        finishGroup()
    }

    func entry(for emoji: String) -> EmojiEntry? {
        byEmoji[emoji]
    }

    /// What to show / type for an emoji: your skin-tone choice if you made one.
    func display(_ emoji: String) -> String {
        toneChoices[emoji] ?? emoji
    }

    func setTone(_ toned: String, for base: String) {
        if toned == base {
            toneChoices[base] = nil
        } else {
            toneChoices[base] = toned
        }
        defaults.set(toneChoices, forKey: tonesKey)
    }

    func noteUsed(_ emoji: String) {
        recents.removeAll { $0 == emoji }
        recents.insert(emoji, at: 0)
        if recents.count > maxRecents { recents.removeLast(recents.count - maxRecents) }
        defaults.set(recents, forKey: recentsKey)
    }

    /// Emoji whose name or keywords start with every word typed ("red hea" → ❤️).
    func search(_ query: String, limit: Int = 60) -> [String] {
        let tokens = query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard !tokens.isEmpty else { return [] }
        var exact: [String] = []
        var partial: [String] = []
        for group in groups {
            for entry in group.entries {
                var allMatch = true
                var allExact = true
                for token in tokens {
                    if entry.words.contains(token) { continue }
                    allExact = false
                    if !entry.words.contains(where: { $0.hasPrefix(token) }) {
                        allMatch = false
                        break
                    }
                }
                guard allMatch else { continue }
                if allExact { exact.append(display(entry.emoji)) } else { partial.append(display(entry.emoji)) }
            }
        }
        return Array((exact + partial).prefix(limit))
    }
}
