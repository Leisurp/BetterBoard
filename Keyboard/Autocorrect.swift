import UIKit

/// Gboard-style autocorrect: decides what (if anything) to replace the current word
/// with, and what to show in the suggestion bar.
///
/// - `WordModel` ranks words by touch position + word frequency (the Gboard part).
/// - Apple's spell checker (`UITextChecker`, Australian English) decides which words
///   are valid and fixes spelling to the Australian form ("color" → "colour").
/// - Your contacts / text replacements and words you've taught it are never corrected.
final class Autocorrector {
    struct Analysis {
        let word: String
        /// What to replace the word with when space/punctuation is typed (nil = leave it).
        let correction: String?
        /// Suggestion bar: [left, middle, right].
        let suggestions: [Suggestion?]
    }

    let model = WordModel()
    let predictor = Predictor()
    private let checker = UITextChecker()
    let language: String

    /// Lowercased word → how you typed it.
    private var learned: [String: String]
    private var lexiconWords: [String: String] = [:]
    /// Text replacements from iOS Settings (e.g. "omw" → "On my way!").
    private var replacements: [String: String] = [:]
    private var pendingWords: [String: Int] = [:]
    private var checkerCache: [String: Bool] = [:]

    private let learnedKey = "learnedWords"
    private var blockOffensive: Bool { KeyboardSettings.shared.blockOffensive }
    private var learningOn: Bool { KeyboardSettings.shared.learnWords }

    private func isBlocked(_ lower: String) -> Bool {
        blockOffensive && Lexicon.blocked.contains(lower)
    }
    /// Words (and emoji) you've told the keyboard to stop suggesting, lowercased.
    private var removed: Set<String>
    private let removedKey = "removedWords"
    private let learnedLogFreq: Float = 10
    private let lexiconLogFreq: Float = 9

    init() {
        let available = UITextChecker.availableLanguages
        language = ["en_AU", "en_GB", "en"].first(where: { available.contains($0) })
            ?? available.first(where: { $0.hasPrefix("en") })
            ?? "en_GB"
        let stored = UserDefaults.standard.stringArray(forKey: learnedKey) ?? []
        learned = Dictionary(stored.map { ($0.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        removed = Set(UserDefaults.standard.stringArray(forKey: removedKey) ?? [])
        model.load { [weak self] in self?.addUserWordsToModel() }
        predictor.load()
    }

    // MARK: Next-word predictions

    /// Suggestions before a word is started: likely next words (best in the middle,
    /// like Gboard) and an emoji for the previous word on the right.
    func predictions(previous: String?, capitalise: Bool, showEmoji: Bool, phrases: Bool) -> [Suggestion?] {
        func capitalised(_ text: String) -> String {
            capitalise ? text.prefix(1).uppercased() + text.dropFirst() : text
        }
        let words = predictor.predictions(after: previous, limit: 6)
            .filter { !isBlocked($0.lowercased()) && !removed.contains($0.lowercased()) }
            .map(capitalised)
        var slots: [Suggestion?] = [nil, nil, nil]
        let order = [1, 0, 2] // best word in the middle
        for (rank, word) in words.prefix(3).enumerated() {
            slots[order[rank]] = Suggestion(text: word, isPrediction: true)
        }
        // Several words at once when the next ones are very likely (Smart Compose-ish).
        if phrases {
            let phrase = predictor.phrase(after: previous)
            if phrase.count >= 2, !phrase.contains(where: { isBlocked($0.lowercased()) || removed.contains($0.lowercased()) }) {
                slots[0] = Suggestion(text: capitalised(phrase.joined(separator: " ")), isPrediction: true)
            }
        }
        if showEmoji, let previous, previous != Predictor.sentenceStart,
           let emoji = predictor.emoji(for: previous).first(where: { !removed.contains($0) }) {
            slots[2] = Suggestion(text: emoji, isEmoji: true)
        }
        return slots
    }

    /// Bonus for words that often follow the previous word ("I'm" → "from" over "form").
    private func contextBonus(previous: String?, word: String) -> Float {
        guard let previous else { return 0 }
        let count = predictor.pairCount(previous: previous, next: word)
        return count > 0 ? min(4, 0.8 * Float(log(1 + Double(count)))) : 0
    }

    private func addUserWordsToModel() {
        for word in learned.values { model.addUserWord(word, logFreq: learnedLogFreq) }
        for word in lexiconWords.values { model.addUserWord(word, logFreq: lexiconLogFreq) }
    }

    func loadLexicon(from controller: UIInputViewController) {
        controller.requestSupplementaryLexicon { [weak self] lexicon in
            let entries = lexicon.entries.map { ($0.userInput, $0.documentText) }
            DispatchQueue.main.async {
                guard let self else { return }
                for (input, text) in entries {
                    let key = input.lowercased()
                    if key == text.lowercased() {
                        self.lexiconWords[key] = text
                        self.model.addUserWord(text, logFreq: self.lexiconLogFreq)
                    } else {
                        self.replacements[key] = text
                    }
                }
            }
        }
    }

    // MARK: Analysis

    /// - Parameters:
    ///   - offsets: where each letter of the word was touched, relative to the centre
    ///     of the key that was hit, in key-pitch units (zeros if unknown).
    ///   - previous: the word before this one ("<s>" at the start of a sentence).
    ///   - autoApply: whether the "Auto-correction" setting is on.
    ///   - showEmoji: whether to offer an emoji for the word.
    func analyze(word: String, offsets: [CGPoint], previous: String?,
                 autoApply: Bool, showEmoji: Bool) -> Analysis {
        let typed = Suggestion(text: word, isTypedWord: true)
        let lower = word.lowercased()

        if let replacement = replacements[lower] {
            return Analysis(word: word,
                            correction: autoApply ? replacement : nil,
                            suggestions: [typed, Suggestion(text: replacement, isAutocorrect: autoApply), nil])
        }

        guard model.isReady, let letters = Self.encode(word), !letters.isEmpty,
              letters.count <= WordModel.maxLength else {
            return Analysis(word: word, correction: nil, suggestions: [nil, typed, nil])
        }

        let input = makeInput(letters: letters, offsets: offsets)
        let n = letters.count
        let isAllCaps = word.count > 1 && word == word.uppercased()
        let hasInnerCaps = word.dropFirst().contains { $0.isUppercase } && !isAllCaps
        let leaveAlone = isAllCaps || hasInnerCaps

        // What did they type?
        let exact = model.exactMatches(input)
        let listed = exact.first { !$0.display.contains("'") }
        let knownLocally = learned[lower] != nil || lexiconWords[lower] != nil
            || checkerKnows(word) || checkerKnows(lower)
        let ownTouchCost = touchCost(offsets: offsets, count: n)
        let typedScore = ownTouchCost - (listed?.logFreq ?? (knownLocally ? 4 : 0))
            - contextBonus(previous: previous, word: lower)

        // Spellings that are always fixed: "i" → "I", "dont" → "don't", "color" → "colour".
        var forced: String?
        if lower == "i" {
            forced = "I"
        } else if let contraction = exact.first(where: { $0.display.contains("'") && !$0.suggestOnly }) {
            forced = contraction.display
        } else if !knownLocally, listed != nil, let local = localSpelling(of: lower) {
            forced = local
        }

        // Ranked alternatives (touch + frequency), in Australian spelling.
        struct Alternative {
            let text: String
            let score: Float
            let cost: Float
            /// Only offered in the bar, never applied automatically.
            let barOnly: Bool
        }
        var alternatives: [Alternative] = []
        var seen: Set<String> = [lower]
        func consider(_ c: WordModel.Candidate, penalty: Float, barOnly: Bool) {
            guard !(c.blocked && blockOffensive), let text = localForm(c) else { return }
            let key = text.lowercased()
            guard !seen.contains(key), !removed.contains(key) else { return }
            seen.insert(key)
            alternatives.append(Alternative(text: matchCase(text, to: word),
                                            score: c.score + penalty - contextBonus(previous: previous, word: key),
                                            cost: c.cost,
                                            barOnly: barOnly || c.suggestOnly))
        }
        // Same letters, different word ("its" → "it's") comes first.
        for c in exact where c.display.lowercased() != lower { consider(c, penalty: -100, barOnly: true) }
        for c in model.decode(input, limit: 6) { consider(c, penalty: 0, barOnly: false) }
        // Completions that commonly follow the previous word ("how m" → "many").
        let typedLetters = Predictor.lettersOnly(word)
        for (rank, p) in predictor.predictions(after: previous, startingWith: typedLetters).prefix(3).enumerated() {
            let key = p.word.lowercased()
            guard !seen.contains(key), !isBlocked(key), !removed.contains(key) else { continue }
            seen.insert(key)
            alternatives.append(Alternative(text: matchCase(p.word, to: word),
                                            score: -30 + Float(rank), cost: 0, barOnly: true))
        }
        // Other completions rank below similar-scoring corrections and are never auto-applied.
        for c in model.completions(input, limit: 4) { consider(c, penalty: 2.5, barOnly: true) }
        alternatives.sort { $0.score < $1.score }

        // Decide whether to autocorrect.
        var correction: String?
        if autoApply && !leaveAlone {
            if let forced, !removed.contains(forced.lowercased()) {
                correction = matchCase(forced, to: word)
            } else {
                let margin: Float = knownLocally ? 5 : (listed != nil ? 3 : 1)
                let maxCost = min(3 + Float(n), 9)
                if let best = alternatives.first(where: { !$0.barOnly }),
                   best.cost <= maxCost,
                   best.score < typedScore - margin {
                    correction = best.text
                }
            }
        }

        // Suggestion bar, Gboard style.
        var others = alternatives.map { $0.text }.filter { $0 != correction }
        func next() -> Suggestion? {
            others.isEmpty ? nil : Suggestion(text: others.removeFirst())
        }
        var suggestions: [Suggestion?]
        if let correction {
            suggestions = [typed, Suggestion(text: correction, isAutocorrect: true), next()]
        } else if knownLocally || listed != nil {
            suggestions = [next(), typed, next()]
        } else {
            suggestions = [typed, next(), next()]
        }
        // Emoji for the word (or what it'll be corrected to) on the right, like Gboard.
        if showEmoji, let emoji = predictor.emoji(for: correction ?? lower).first(where: { !removed.contains($0) }) {
            suggestions[2] = Suggestion(text: emoji, isEmoji: true)
        }
        return Analysis(word: word, correction: correction, suggestions: suggestions)
    }

    // MARK: Learning

    /// Called when a word is finished without being corrected. Words you type twice
    /// that the dictionary doesn't know get learned (Gboard does the same).
    func noteCommitted(_ word: String) {
        let lower = word.lowercased()
        guard learningOn, word.count >= 2, Self.encode(word) != nil, learned[lower] == nil,
              !removed.contains(lower) else { return }
        if checkerKnows(word) || checkerKnows(lower) { return }
        if model.isReady, let letters = Self.encode(word),
           model.exactMatches(makeInput(letters: letters, offsets: [])).contains(where: { !$0.display.contains("'") }) {
            return
        }
        pendingWords[lower, default: 0] += 1
        if pendingWords[lower, default: 0] >= 2 {
            learn(word)
        }
    }

    func learn(_ word: String) {
        let lower = word.lowercased()
        guard learningOn, !lower.isEmpty, Self.encode(word) != nil else { return }
        // Choosing a word yourself brings it back if it was removed.
        if removed.remove(lower) != nil {
            UserDefaults.standard.set(Array(removed), forKey: removedKey)
        }
        learned[lower] = word
        pendingWords[lower] = nil
        model.addUserWord(word, logFreq: learnedLogFreq)
        save()
    }

    /// Stop suggesting this word or emoji (hold it in the suggestion bar). If the
    /// keyboard learned it, it's forgotten too.
    func remove(_ text: String) {
        let lower = text.lowercased()
        removed.insert(lower)
        pendingWords[lower] = nil
        if learned.removeValue(forKey: lower) != nil {
            model.removeAllUserWords()
            addUserWordsToModel()
            save()
        }
        UserDefaults.standard.set(Array(removed), forKey: removedKey)
    }

    /// Words the keyboard has learned, A–Z.
    var learnedWords: [String] {
        learned.values.sorted { $0.lowercased() < $1.lowercased() }
    }

    /// Words and emoji you've told it to stop suggesting, A–Z.
    var removedWords: [String] {
        removed.sorted()
    }

    /// Forget one learned word.
    func forget(_ word: String) {
        let lower = word.lowercased()
        guard learned.removeValue(forKey: lower) != nil else { return }
        pendingWords[lower] = nil
        model.removeAllUserWords()
        addUserWordsToModel()
        save()
    }

    /// Suggest a removed word again.
    func restore(_ word: String) {
        guard removed.remove(word.lowercased()) != nil else { return }
        UserDefaults.standard.set(Array(removed), forKey: removedKey)
    }

    /// Forgets learned words and brings back removed suggestions.
    func resetLearned() {
        removed.removeAll()
        UserDefaults.standard.set([String](), forKey: removedKey)
        learned.removeAll()
        pendingWords.removeAll()
        model.removeAllUserWords()
        for word in lexiconWords.values { model.addUserWord(word, logFreq: lexiconLogFreq) }
        save()
    }

    private func save() {
        UserDefaults.standard.set(Array(learned.values), forKey: learnedKey)
    }

    // MARK: Helpers

    /// Letter indices (a = 0 … z = 25), skipping apostrophes. Nil for anything else
    /// (accents, digits), which the model doesn't handle.
    static func encode(_ word: String) -> [UInt8]? {
        var result: [UInt8] = []
        for scalar in word.lowercased().unicodeScalars {
            let v = scalar.value
            if v >= 97 && v <= 122 {
                result.append(UInt8(v - 97))
            } else if scalar == "'" || scalar == "\u{2019}" {
                continue
            } else {
                return nil
            }
        }
        return result
    }

    private func makeInput(letters: [UInt8], offsets: [CGPoint]) -> WordModel.Input {
        let n = letters.count
        var x = [Float](repeating: 0, count: n)
        var y = [Float](repeating: 0, count: n)
        let usable = offsets.suffix(n)
        let pad = n - usable.count
        for (i, letter) in letters.enumerated() {
            x[i] = WordModel.keyX[Int(letter)]
            y[i] = WordModel.keyY[Int(letter)]
            if i >= pad {
                let offset = usable[usable.startIndex + (i - pad)]
                x[i] += Float(offset.x)
                y[i] += Float(offset.y)
            }
        }
        return WordModel.Input(letters: letters, x: x, y: y)
    }

    /// How far the touches were from the centres of the keys that were hit.
    private func touchCost(offsets: [CGPoint], count: Int) -> Float {
        offsets.suffix(count).reduce(0) { total, o in
            total + min(2 * Float(o.x * o.x + o.y * o.y), 7)
        }
    }

    private func checkerKnows(_ word: String) -> Bool {
        if let cached = checkerCache[word] { return cached }
        let range = NSRange(location: 0, length: (word as NSString).length)
        let miss = checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: language)
        let known = miss.location == NSNotFound
        if checkerCache.count > 4000 { checkerCache.removeAll() }
        checkerCache[word] = known
        return known
    }

    /// A dictionary word in its correct Australian form and capitalisation.
    private func localForm(_ c: WordModel.Candidate) -> String? {
        let word = c.display
        if c.isUserWord || word.contains("'") || word == "I" { return word }
        if checkerKnows(word) { return word }
        let capitalised = word.prefix(1).uppercased() + word.dropFirst()
        if checkerKnows(capitalised) { return capitalised }
        if let local = localSpelling(of: word) { return local }
        // Slang and informal words ("gonna", "lol") that Apple's dictionary lacks.
        return word
    }

    /// US → Australian spelling ("color" → "colour", "organize" → "organise").
    private func localSpelling(of word: String) -> String? {
        guard !checkerKnows(word) else { return nil }
        for variant in Self.spellingVariants(of: word) where checkerKnows(variant) {
            return variant
        }
        return nil
    }

    private static let suffixRules: [(String, String)] = [
        ("ization", "isation"), ("izations", "isations"), ("ize", "ise"), ("izes", "ises"),
        ("ized", "ised"), ("izing", "ising"), ("izer", "iser"), ("yze", "yse"), ("yzed", "ysed"),
        ("yzing", "ysing"), ("eled", "elled"), ("eling", "elling"), ("eler", "eller"),
        ("er", "re"), ("ers", "res"), ("og", "ogue"), ("ogs", "ogues"),
        ("ense", "ence"), ("ment", "ement"),
    ]

    static func spellingVariants(of word: String) -> [String] {
        var variants: [String] = []
        for (us, uk) in suffixRules where word.hasSuffix(us) {
            variants.append(String(word.dropLast(us.count)) + uk)
        }
        // color → colour, favorite → favourite, behavior → behaviour
        var search = word.startIndex
        while let range = word.range(of: "or", range: search..<word.endIndex) {
            if range.lowerBound > word.startIndex {
                variants.append(word.replacingCharacters(in: range, with: "our"))
            }
            search = range.upperBound
        }
        if word == "gray" { variants.append("grey") }
        if word == "mom" { variants.append("mum") }
        return variants
    }

    private func matchCase(_ text: String, to word: String) -> String {
        if word.count > 1, word == word.uppercased(), word != word.lowercased() {
            return text.uppercased()
        }
        if let first = word.first, first.isUppercase {
            return text.prefix(1).uppercased() + text.dropFirst()
        }
        return text
    }
}
