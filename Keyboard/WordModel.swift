import Foundation

/// Gboard-style word decoder.
///
/// For each word in the dictionary it asks: "how likely is it that the user meant
/// this word, given *where* each key was actually touched?" (a spatial model —
/// a tap near the edge of `e` could easily have been meant for `w` or `r`) and
/// "how common is this word?" (a frequency model). Missed keys, extra taps and
/// swapped letters are allowed at a cost. The cheapest words win.
final class WordModel {
    struct Candidate {
        let index: Int32
        let display: String
        /// How far the word is from what was typed (touch distance + edits). Lower is closer.
        let cost: Float
        /// `cost` minus the word's frequency bonus. Lower is better.
        let score: Float
        let logFreq: Float
        let suggestOnly: Bool
        let blocked: Bool
        let isUserWord: Bool
    }

    /// One typed word: letter indices (0 = a … 25 = z) and where each was touched,
    /// in key-pitch units on a QWERTY grid.
    struct Input {
        var letters: [UInt8]
        var x: [Float]
        var y: [Float]
    }

    private(set) var isReady = false

    // Flat storage (built once on a background thread, then only read on main).
    private var letters: [UInt8] = []
    private var starts: [Int32] = []
    private var lengths: [UInt8] = []
    private var logFreqs: [Float] = []
    private var displays: [String] = []
    private var flags: [UInt8] = []
    private var byLength: [[Int32]] = []
    private var byFrequency: [Int32] = []
    /// Letters-only key → indices of words spelled with exactly those letters.
    private var exact: [String: [Int32]] = [:]

    private static let flagBlocked: UInt8 = 1
    private static let flagSuggestOnly: UInt8 = 2
    private static let flagUser: UInt8 = 4
    static let maxLength = 24

    // MARK: Key geometry (QWERTY, in key-pitch units)

    static let keyX: [Float] = {
        var x = [Float](repeating: 0, count: 26)
        for (row, offset) in [("qwertyuiop", Float(0)), ("asdfghjkl", 0.5), ("zxcvbnm", 1.5)] {
            for (i, ch) in row.unicodeScalars.enumerated() {
                x[Int(ch.value - 97)] = offset + Float(i)
            }
        }
        return x
    }()

    static let keyY: [Float] = {
        var y = [Float](repeating: 0, count: 26)
        for (rowIndex, row) in ["qwertyuiop", "asdfghjkl", "zxcvbnm"].enumerated() {
            for ch in row.unicodeScalars {
                y[Int(ch.value - 97)] = Float(rowIndex)
            }
        }
        return y
    }()

    // MARK: Tuning

    /// 1 / (2σ²) with σ ≈ 0.5 keys: a tap one key away from a letter costs ~2.
    private let spatialWeight: Float = 2.0
    private let maxSubstitution: Float = 7.0
    private let extraTapCost: Float = 3.5
    private let doubleTapCost: Float = 1.5
    private let missedKeyCost: Float = 4.0
    private let missedDoubleLetterCost: Float = 1.5
    private let swapCost: Float = 1.5

    // MARK: Loading

    private struct Storage {
        var letters: [UInt8] = []
        var starts: [Int32] = []
        var lengths: [UInt8] = []
        var logFreqs: [Float] = []
        var displays: [String] = []
        var flags: [UInt8] = []
        var byLength: [[Int32]] = []
        var byFrequency: [Int32] = []
        var exact: [String: [Int32]] = [:]
    }

    private static func lettersKey(_ s: Storage, _ i: Int) -> String {
        let start = Int(s.starts[i])
        let length = Int(s.lengths[i])
        return String(decoding: s.letters[start..<start + length].map { $0 + 97 }, as: UTF8.self)
    }

    private static func index(_ s: inout Storage) {
        s.byLength = Array(repeating: [], count: maxLength + 2)
        s.exact = [:]
        for i in 0..<s.starts.count {
            s.byLength[Int(s.lengths[i])].append(Int32(i))
            s.exact[lettersKey(s, i), default: []].append(Int32(i))
        }
        let freqs = s.logFreqs
        s.byFrequency = (0..<Int32(s.starts.count)).sorted { freqs[Int($0)] > freqs[Int($1)] }
    }

    func load(completion: @escaping () -> Void) {
        let url = Bundle(for: WordModel.self).url(forResource: "words", withExtension: "txt")
        DispatchQueue.global(qos: .userInitiated).async {
            let storage = Self.build(from: url)
            DispatchQueue.main.async {
                self.install(storage)
                completion()
            }
        }
    }

    private static func build(from url: URL?) -> Storage {
        var s = Storage()
        func add(_ display: String, count: Double, flags: UInt8) {
            var word: [UInt8] = []
            for scalar in display.lowercased().unicodeScalars {
                let v = scalar.value
                if v >= 97 && v <= 122 { word.append(UInt8(v - 97)) }
            }
            guard !word.isEmpty, word.count <= maxLength else { return }
            s.starts.append(Int32(s.letters.count))
            s.lengths.append(UInt8(word.count))
            s.letters.append(contentsOf: word)
            s.logFreqs.append(Float(log(max(count, 2))))
            s.displays.append(display)
            s.flags.append(flags)
        }

        if let url, let text = try? String(contentsOf: url, encoding: .utf8) {
            for line in text.split(whereSeparator: { $0.isNewline }) {
                let parts = line.split(separator: " ")
                guard parts.count >= 2 else { continue }
                let word = String(parts[0])
                let count = Double(parts[1].trimmingCharacters(in: .whitespaces)) ?? 1
                let display = word == "i" ? "I" : word
                add(display, count: count, flags: Lexicon.blocked.contains(word) ? flagBlocked : 0)
            }
        }
        for c in Lexicon.contractions {
            add(c.display, count: c.count, flags: c.suggestOnly ? flagSuggestOnly : 0)
        }
        index(&s)
        return s
    }

    private func install(_ s: Storage) {
        letters = s.letters
        starts = s.starts
        lengths = s.lengths
        logFreqs = s.logFreqs
        displays = s.displays
        flags = s.flags
        byLength = s.byLength
        byFrequency = s.byFrequency
        exact = s.exact
        isReady = true
    }

    private func key(of index: Int32) -> String {
        let start = Int(starts[Int(index)])
        let length = Int(lengths[Int(index)])
        return String(decoding: letters[start..<start + length].map { $0 + 97 }, as: UTF8.self)
    }

    // MARK: User words (learned + contacts / text replacements)

    private var userWordIndex: [String: Int32] = [:]

    /// Adds a word the user types (learned) so it can be typed and corrected to.
    func addUserWord(_ word: String, logFreq: Float) {
        guard isReady else { return }
        let lower = word.lowercased()
        if let existing = userWordIndex[lower] {
            logFreqs[Int(existing)] = max(logFreqs[Int(existing)], logFreq)
            return
        }
        var encoded: [UInt8] = []
        for scalar in lower.unicodeScalars {
            let v = scalar.value
            if v >= 97 && v <= 122 { encoded.append(UInt8(v - 97)) }
        }
        guard !encoded.isEmpty, encoded.count <= Self.maxLength else { return }
        let index = Int32(starts.count)
        starts.append(Int32(letters.count))
        lengths.append(UInt8(encoded.count))
        letters.append(contentsOf: encoded)
        logFreqs.append(logFreq)
        displays.append(word)
        flags.append(Self.flagUser)
        byLength[encoded.count].append(index)
        exact[key(of: index), default: []].append(index)
        userWordIndex[lower] = index
        // Keep frequency order roughly right without a full re-sort.
        let position = byFrequency.firstIndex { logFreqs[Int($0)] < logFreq } ?? byFrequency.count
        byFrequency.insert(index, at: position)
    }

    func removeAllUserWords() {
        guard isReady, !userWordIndex.isEmpty else { return }
        let removed = Set(userWordIndex.values)
        for index in removed {
            let i = Int(index)
            byLength[Int(lengths[i])].removeAll { $0 == index }
            let k = key(of: index)
            exact[k]?.removeAll { $0 == index }
            if exact[k]?.isEmpty == true { exact[k] = nil }
        }
        byFrequency.removeAll { removed.contains($0) }
        userWordIndex.removeAll()
    }

    // MARK: Lookups

    /// Words spelled with exactly these letters (ignoring apostrophes and case).
    func exactMatches(_ input: Input) -> [Candidate] {
        let key = String(decoding: input.letters.map { $0 + 97 }, as: UTF8.self)
        return (exact[key] ?? []).map { candidate(index: $0, cost: 0) }
    }

    private func candidate(index: Int32, cost: Float) -> Candidate {
        let i = Int(index)
        return Candidate(index: index,
                         display: displays[i],
                         cost: cost,
                         score: cost - logFreqs[i],
                         logFreq: logFreqs[i],
                         suggestOnly: flags[i] & Self.flagSuggestOnly != 0,
                         blocked: flags[i] & Self.flagBlocked != 0,
                         isUserWord: flags[i] & Self.flagUser != 0)
    }

    /// Most common words starting with the typed letters (longer than what's typed).
    func completions(_ input: Input, limit: Int) -> [Candidate] {
        let n = input.letters.count
        guard isReady, n > 0, limit > 0 else { return [] }
        var result: [Candidate] = []
        letters.withUnsafeBufferPointer { all in
            for index in byFrequency {
                let i = Int(index)
                let length = Int(lengths[i])
                guard length > n, flags[i] & Self.flagBlocked == 0 else { continue }
                let start = Int(starts[i])
                var matches = true
                for k in 0..<n where all[start + k] != input.letters[k] {
                    matches = false
                    break
                }
                if matches {
                    result.append(candidate(index: index, cost: 0))
                    if result.count >= limit { break }
                }
            }
        }
        return result
    }

    // MARK: Decoding

    /// The `limit` most likely intended words for what was typed.
    func decode(_ input: Input, limit: Int) -> [Candidate] {
        let n = input.letters.count
        guard isReady, n > 0, n <= Self.maxLength else { return [] }

        // Cost of each typed position being each letter, from touch distance.
        var spatial = [Float](repeating: 0, count: n * 26)
        for i in 0..<n {
            for c in 0..<26 {
                let dx = input.x[i] - Self.keyX[c]
                let dy = input.y[i] - Self.keyY[c]
                spatial[i * 26 + c] = min(spatialWeight * (dx * dx + dy * dy), maxSubstitution)
            }
        }
        var deleteCost = [Float](repeating: extraTapCost, count: n)
        for i in 1..<max(n, 1) where input.letters[i] == input.letters[i - 1] {
            deleteCost[i] = doubleTapCost
        }

        let costLimit = min(4.0 + 1.5 * Float(n), 14.0)
        let width = Self.maxLength + 3
        var rows = [Float](repeating: .infinity, count: 3 * width)
        var best: [(index: Int32, cost: Float, score: Float)] = []
        let keep = limit * 3

        letters.withUnsafeBufferPointer { all in
            spatial.withUnsafeBufferPointer { sp in
                rows.withUnsafeMutableBufferPointer { r in
                    for m in max(1, n - 1)...min(Self.maxLength, n + 1) {
                        for index in byLength[m] {
                            let i = Int(index)
                            let start = Int(starts[i])
                            guard let cost = alignmentCost(all: all, start: start, m: m, n: n,
                                                           sp: sp, deleteCost: deleteCost,
                                                           rows: r, width: width, limit: costLimit)
                            else { continue }
                            let score = cost - logFreqs[i]
                            if best.count < keep || score < best[best.count - 1].score {
                                let at = best.firstIndex { score < $0.score } ?? best.count
                                best.insert((index, cost, score), at: at)
                                if best.count > keep { best.removeLast() }
                            }
                        }
                    }
                }
            }
        }
        return best.map { candidate(index: $0.index, cost: $0.cost) }
    }

    /// Weighted edit distance between the typed touches and a dictionary word,
    /// using three rolling rows of the DP table. Returns nil if it exceeds `limit`.
    @inline(__always)
    private func alignmentCost(all: UnsafeBufferPointer<UInt8>, start: Int, m: Int, n: Int,
                               sp: UnsafeBufferPointer<Float>, deleteCost: [Float],
                               rows r: UnsafeMutableBufferPointer<Float>, width: Int,
                               limit: Float) -> Float? {
        // Row layout: r[(row % 3) * width + j]
        @inline(__always) func word(_ j: Int) -> Int { Int(all[start + j]) }
        func insertCost(_ j: Int) -> Float {
            (j > 0 && all[start + j] == all[start + j - 1]) ? missedDoubleLetterCost : missedKeyCost
        }

        // Row 0
        r[0] = 0
        for j in 1...m { r[j] = j <= 2 ? r[j - 1] + insertCost(j - 1) : .infinity }

        for i in 1...n {
            let cur = (i % 3) * width
            let prev = ((i - 1) % 3) * width
            let prev2 = ((i + 1) % 3) * width // (i - 2) % 3
            let lo = max(0, i - 2)
            let hi = min(m, i + 2)
            for j in 0...m { r[cur + j] = .infinity }
            if lo == 0 { r[cur] = r[prev] + deleteCost[i - 1] }
            var rowMin = r[cur]
            if lo <= hi {
                for j in max(1, lo)...max(max(1, lo), hi) where j <= hi {
                    let c = word(j - 1)
                    var v = r[prev + j - 1] + sp[(i - 1) * 26 + c]
                    let del = r[prev + j] + deleteCost[i - 1]
                    if del < v { v = del }
                    let ins = r[cur + j - 1] + insertCost(j - 1)
                    if ins < v { v = ins }
                    if i >= 2 && j >= 2 {
                        let a = word(j - 1), b = word(j - 2)
                        if a != b {
                            let swap = r[prev2 + j - 2] + sp[(i - 2) * 26 + a] + sp[(i - 1) * 26 + b] + swapCost
                            if swap < v { v = swap }
                        }
                    }
                    r[cur + j] = v
                    if v < rowMin { rowMin = v }
                }
            }
            if rowMin > limit { return nil }
        }
        let result = r[(n % 3) * width + m]
        return result <= limit ? result : nil
    }
}
