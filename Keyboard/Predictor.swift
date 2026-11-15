import Foundation

/// Gboard-style next-word predictions and emoji suggestions.
///
/// - `bigrams.txt`: for each word, the words most often typed after it
///   (from ~2 million everyday English sentences). "<s>" = start of a sentence.
/// - `emoji.txt`: emoji for words ("cow" → 🐄 🐮).
final class Predictor {
    private(set) var isReady = false

    /// Letters-only previous word → [(next word, count)], most common first.
    private var nextWords: [String: [(word: String, count: Int)]] = [:]
    private var emojiByWord: [String: [String]] = [:]

    static let sentenceStart = "<s>"

    func load() {
        let bundle = Bundle(for: Predictor.self)
        let bigramURL = bundle.url(forResource: "bigrams", withExtension: "txt")
        let emojiURL = bundle.url(forResource: "emoji", withExtension: "txt")
        DispatchQueue.global(qos: .utility).async {
            let next = Self.loadBigrams(bigramURL)
            let emoji = Self.loadEmoji(emojiURL)
            DispatchQueue.main.async {
                self.nextWords = next
                self.emojiByWord = emoji
                self.isReady = true
            }
        }
    }

    private static func loadBigrams(_ url: URL?) -> [String: [(word: String, count: Int)]] {
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var result: [String: [(word: String, count: Int)]] = [:]
        for line in text.split(whereSeparator: { $0.isNewline }) {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0] == "<s>" ? sentenceStart : lettersOnly(String(parts[0]))
            var list = result[key] ?? []
            for item in parts[1].split(separator: " ") {
                guard let colon = item.lastIndex(of: ":"),
                      let count = Int(item[item.index(after: colon)...]) else { continue }
                list.append((word: String(item[..<colon]), count: count))
            }
            // "its" and "it's" share letters: merge and keep the best.
            result[key] = list.sorted { $0.count > $1.count }
        }
        return result
    }

    private static func loadEmoji(_ url: URL?) -> [String: [String]] {
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var result: [String: [String]] = [:]
        for line in text.split(whereSeparator: { $0.isNewline }) {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            result[String(parts[0])] = parts[1].split(separator: " ").map(String.init)
        }
        return result
    }

    static func lettersOnly(_ word: String) -> String {
        String(word.lowercased().unicodeScalars.filter { $0.value >= 97 && $0.value <= 122 }
            .map(Character.init))
    }

    /// How the word should appear ("i'm" → "I'm").
    static func display(_ token: String) -> String {
        if token == "i" || token.hasPrefix("i'") {
            return "I" + token.dropFirst()
        }
        return token
    }

    // MARK: Queries

    /// Most likely next words after `previous` (nil / "<s>" = start of a sentence).
    func predictions(after previous: String?, limit: Int) -> [String] {
        guard isReady else { return [] }
        let key = previous.map { $0 == Self.sentenceStart ? $0 : Self.lettersOnly($0) } ?? Self.sentenceStart
        guard let list = nextWords[key] else { return [] }
        var seen: Set<String> = []
        var result: [String] = []
        for item in list where !seen.contains(item.word) {
            seen.insert(item.word)
            result.append(Self.display(item.word))
            if result.count == limit { break }
        }
        return result
    }

    /// Words that often follow `previous` and start with `prefix` (letters only).
    func predictions(after previous: String?, startingWith prefix: String) -> [(word: String, count: Int)] {
        guard isReady, let previous, !prefix.isEmpty else { return [] }
        let key = previous == Self.sentenceStart ? previous : Self.lettersOnly(previous)
        return (nextWords[key] ?? []).filter {
            let letters = Self.lettersOnly($0.word)
            return letters.count > prefix.count && letters.hasPrefix(prefix)
        }.map { (word: Self.display($0.word), count: $0.count) }
    }

    /// How often `next` follows `previous` (0 if never seen).
    func pairCount(previous: String?, next: String) -> Int {
        guard isReady, let previous else { return 0 }
        let key = previous == Self.sentenceStart ? previous : Self.lettersOnly(previous)
        let target = Self.lettersOnly(next)
        return (nextWords[key] ?? []).first { Self.lettersOnly($0.word) == target }?.count ?? 0
    }

    /// Emoji for a word ("cow" → 🐄 🐮), also matching simple plurals ("cows").
    func emoji(for word: String) -> [String] {
        guard isReady else { return [] }
        let lower = word.lowercased()
        if let found = emojiByWord[lower] { return found }
        if lower.hasSuffix("es"), let found = emojiByWord[String(lower.dropLast(2))] { return found }
        if lower.hasSuffix("s"), let found = emojiByWord[String(lower.dropLast())] { return found }
        return []
    }
}
