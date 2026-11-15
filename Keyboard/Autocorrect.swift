import UIKit

/// Spelling correction and word completion using Apple's built-in spell checker.
final class Autocorrector {
    private let checker = UITextChecker()
    let language: String

    private var learned: Set<String>
    private var lexiconWords: Set<String> = []
    /// Text replacements from iOS Settings (e.g. "omw" -> "On my way!").
    private var replacements: [String: String] = [:]
    private let learnedKey = "learnedWords"

    init() {
        let available = UITextChecker.availableLanguages
        language = ["en_AU", "en_GB", "en"].first(where: { available.contains($0) })
            ?? available.first(where: { $0.hasPrefix("en") })
            ?? "en_GB"
        learned = Set(UserDefaults.standard.stringArray(forKey: learnedKey) ?? [])
    }

    func loadLexicon(from controller: UIInputViewController) {
        controller.requestSupplementaryLexicon { [weak self] lexicon in
            let entries = lexicon.entries.map { ($0.userInput, $0.documentText) }
            DispatchQueue.main.async {
                guard let self else { return }
                for (input, text) in entries {
                    let key = input.lowercased()
                    if key == text.lowercased() {
                        self.lexiconWords.insert(key)
                    } else {
                        self.replacements[key] = text
                    }
                }
            }
        }
    }

    // MARK: Queries

    func isKnown(_ word: String) -> Bool {
        let lower = word.lowercased()
        if learned.contains(lower) || lexiconWords.contains(lower) { return true }
        let range = NSRange(location: 0, length: (word as NSString).length)
        let miss = checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: language)
        return miss.location == NSNotFound
    }

    /// The word to auto-replace `word` with when a space/punctuation is typed, if any.
    func correction(for word: String) -> String? {
        if let replacement = replacements[word.lowercased()] { return replacement }
        if word == "i" { return "I" }
        guard word.count >= 2, !isKnown(word) else { return nil }

        // Leave acronyms and mixed-case words (iPhone, NASA) alone.
        let rest = word.dropFirst()
        if rest.contains(where: { $0.isUppercase }) { return nil }

        let capitalised = word.first?.isUppercase ?? false
        let maxDistance = (word.count <= 3 || capitalised) ? 1 : 2
        return guesses(for: word, maxDistance: maxDistance).first
    }

    /// Spelling guesses, closest first.
    func guesses(for word: String, maxDistance: Int = 2) -> [String] {
        let range = NSRange(location: 0, length: (word as NSString).length)
        let raw = checker.guesses(forWordRange: range, in: word, language: language) ?? []
        let lower = word.lowercased()
        let scored = raw.enumerated().compactMap { index, guess -> (String, Int, Int)? in
            let distance = Self.distance(lower, guess.lowercased())
            guard distance <= maxDistance else { return nil }
            return (guess, distance, index)
        }
        return scored
            .sorted { ($0.1, $0.2) < ($1.1, $1.2) }
            .map { matchCase($0.0, to: word) }
    }

    func completions(for word: String) -> [String] {
        let range = NSRange(location: 0, length: (word as NSString).length)
        let raw = checker.completions(forPartialWordRange: range, in: word, language: language) ?? []
        return raw.prefix(6).map { matchCase($0, to: word) }
    }

    // MARK: Learning

    func learn(_ word: String) {
        let lower = word.lowercased()
        guard !lower.isEmpty else { return }
        learned.insert(lower)
        save()
    }

    func resetLearned() {
        learned.removeAll()
        save()
    }

    private func save() {
        UserDefaults.standard.set(Array(learned), forKey: learnedKey)
    }

    // MARK: Helpers

    private func matchCase(_ guess: String, to word: String) -> String {
        if word.count > 1, word == word.uppercased(), word != word.lowercased() {
            return guess.uppercased()
        }
        if let first = word.first, first.isUppercase {
            return guess.prefix(1).uppercased() + guess.dropFirst()
        }
        return guess
    }

    /// Edit distance where swapping two neighbouring letters counts as one edit.
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count]
    }
}
