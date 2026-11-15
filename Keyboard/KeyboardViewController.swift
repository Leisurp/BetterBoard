import UIKit

/// iOS entry point for the keyboard. Owns the text logic: inserting, deleting,
/// shift / auto-capitalisation, double-space full stop and autocorrect.
final class KeyboardViewController: UIInputViewController {
    private let settings = KeyboardSettings.shared
    private let autocorrector = Autocorrector()
    private let suggestionBar = SuggestionBar()
    private let keyboardView = KeyboardView()
    private var settingsPanel: SettingsPanel?
    private var heightConstraint: NSLayoutConstraint?

    private var shiftState: ShiftState = .off {
        didSet { keyboardView.shiftState = shiftState }
    }
    private var lastShiftTap: Date?
    private var shiftHeldDown = false
    private var typedWhileShiftHeld = false
    private var lastKeyWasSpace = false

    private struct Correction {
        let original: String
        let corrected: String
        let boundary: String
    }
    private var lastCorrection: Correction?

    private var proxy: UITextDocumentProxy { textDocumentProxy }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        suggestionBar.delegate = self
        keyboardView.delegate = self

        suggestionBar.translatesAutoresizingMaskIntoConstraints = false
        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(suggestionBar)
        // Added after the bar so key popups draw on top of it.
        view.addSubview(keyboardView)

        NSLayoutConstraint.activate([
            suggestionBar.topAnchor.constraint(equalTo: view.topAnchor),
            suggestionBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            suggestionBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            suggestionBar.heightAnchor.constraint(equalToConstant: Metrics.barHeight),

            keyboardView.topAnchor.constraint(equalTo: suggestionBar.bottomAnchor),
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let height = view.heightAnchor.constraint(equalToConstant: totalHeight)
        height.priority = UILayoutPriority(999)
        height.isActive = true
        heightConstraint = height

        autocorrector.loadLexicon(from: self)

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (controller: KeyboardViewController, _: UITraitCollection) in
            controller.updateAppearance()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        switch proxy.keyboardType ?? .default {
        case .numberPad, .decimalPad, .numbersAndPunctuation, .asciiCapableNumberPad, .phonePad:
            keyboardView.mode = .numbers
        default:
            keyboardView.mode = .letters
        }
        updateForContext()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Stop iOS from delaying touches near the screen edges.
        view.window?.gestureRecognizers?.forEach { $0.delaysTouchesBegan = false }
        view.window?.superview?.gestureRecognizers?.forEach { $0.delaysTouchesBegan = false }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateForContext()
    }

    private var totalHeight: CGFloat {
        Metrics.barHeight + keyboardView.preferredHeight
    }

    private func updateHeight() {
        heightConstraint?.constant = totalHeight
    }

    private func updateForContext() {
        keyboardView.returnKeyType = proxy.returnKeyType ?? .default
        updateAppearance()
        updateAutoShift()
        refreshSuggestions()
    }

    private func updateAppearance() {
        let appearance = proxy.keyboardAppearance ?? .default
        let isDark = appearance == .dark
            || (appearance != .light && traitCollection.userInterfaceStyle == .dark)
        let theme = Theme(isDark: isDark)
        keyboardView.theme = theme
        suggestionBar.theme = theme
        settingsPanel?.overrideUserInterfaceStyle = isDark ? .dark : .light
    }

    // MARK: Field rules

    private var fieldAllowsCorrection: Bool {
        guard settings.autocorrect else { return false }
        if proxy.autocorrectionType == .no { return false }
        switch proxy.keyboardType ?? .default {
        case .URL, .emailAddress, .webSearch, .twitter, .numberPad, .decimalPad,
             .phonePad, .asciiCapableNumberPad, .numbersAndPunctuation:
            return false
        default:
            return true
        }
    }

    // MARK: Text helpers

    /// Letters (and apostrophes) directly before the cursor.
    private func currentWord() -> String {
        guard let before = proxy.documentContextBeforeInput else { return "" }
        var chars: [Character] = []
        for ch in before.reversed() {
            if ch.isLetter || ch == "'" || ch == "\u{2019}" {
                chars.append(ch)
            } else {
                break
            }
        }
        var word = String(chars.reversed())
        while let first = word.first, first == "'" || first == "\u{2019}" {
            word.removeFirst()
        }
        return word
    }

    private func deleteCharacters(_ count: Int) {
        for _ in 0..<max(count, 0) {
            proxy.deleteBackward()
        }
    }

    /// Replaces the word before the cursor if it's misspelled. Returns true if it changed.
    @discardableResult
    private func applyAutocorrect(boundary: String) -> Bool {
        guard fieldAllowsCorrection else { return false }
        let word = currentWord()
        guard !word.isEmpty,
              let fixed = autocorrector.correction(for: word),
              fixed != word else { return false }
        deleteCharacters(word.count)
        proxy.insertText(fixed)
        lastCorrection = Correction(original: word, corrected: fixed, boundary: boundary)
        return true
    }

    private func afterInsert() {
        if shiftState == .once {
            if shiftHeldDown {
                typedWhileShiftHeld = true
            } else {
                shiftState = .off
            }
        }
        updateAutoShift()
        refreshSuggestions()
    }

    // MARK: Shift / auto-capitalisation

    private func updateAutoShift() {
        guard shiftState != .locked, !shiftHeldDown else { return }
        guard settings.autocap, keyboardView.mode == .letters else {
            if shiftState == .once { shiftState = .off }
            return
        }

        let before = proxy.documentContextBeforeInput ?? ""
        let shouldCapitalise: Bool
        switch proxy.autocapitalizationType ?? .sentences {
        case .none:
            shouldCapitalise = false
        case .allCharacters:
            shouldCapitalise = true
        case .words:
            shouldCapitalise = before.isEmpty || (before.last?.isWhitespace ?? true)
        case .sentences:
            shouldCapitalise = isSentenceStart(before)
        @unknown default:
            shouldCapitalise = isSentenceStart(before)
        }
        shiftState = shouldCapitalise ? .once : .off
    }

    private func isSentenceStart(_ before: String) -> Bool {
        if before.isEmpty { return true }
        guard let last = before.last else { return true }
        if last.isNewline { return true }
        guard last == " " else { return false }
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        guard let end = trimmed.last else { return true }
        return end == "." || end == "!" || end == "?" || end.isNewline
    }

    // MARK: Suggestions

    private func refreshSuggestions() {
        guard fieldAllowsCorrection else {
            suggestionBar.setSuggestions([])
            return
        }
        let word = currentWord()
        guard !word.isEmpty else {
            suggestionBar.setSuggestions([])
            return
        }

        var list: [Suggestion] = [Suggestion(text: word, isTypedWord: true)]
        if let fix = autocorrector.correction(for: word), fix != word {
            list.append(Suggestion(text: fix, isAutocorrect: true))
        }
        var extras = autocorrector.completions(for: word)
        if list.count == 2 {
            extras = autocorrector.guesses(for: word) + extras
        }
        for candidate in extras where list.count < 3 {
            if candidate != word, !list.contains(where: { $0.text == candidate }) {
                list.append(Suggestion(text: candidate))
            }
        }
        suggestionBar.setSuggestions(list)
    }

    // MARK: Settings panel

    private func showSettings() {
        guard settingsPanel == nil else { return }
        let panel = SettingsPanel(isDark: keyboardView.theme.isDark)
        panel.onDone = { [weak self] in self?.hideSettings() }
        panel.onResetLearned = { [weak self] in self?.autocorrector.resetLearned() }
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: view.topAnchor),
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        settingsPanel = panel
        keyboardView.isHidden = true
        suggestionBar.isHidden = true
    }

    private func hideSettings() {
        settingsPanel?.removeFromSuperview()
        settingsPanel = nil
        keyboardView.isHidden = false
        suggestionBar.isHidden = false
        keyboardView.rebuild()
        updateHeight()
        updateForContext()
    }
}

// MARK: - Key handling

extension KeyboardViewController: KeyboardViewDelegate {
    func keyboardView(_ view: KeyboardView, didType text: String) {
        lastKeyWasSpace = false
        lastCorrection = nil
        let breaksWord = [".", ",", "!", "?", ";", ":", ")", "\""].contains(text)
        if breaksWord {
            applyAutocorrect(boundary: text)
        }
        proxy.insertText(text)
        afterInsert()
    }

    func keyboardViewDidTapSpace(_ view: KeyboardView) {
        // Double-space full stop.
        if settings.doubleSpacePeriod, lastKeyWasSpace,
           let before = proxy.documentContextBeforeInput, before.hasSuffix(" ") {
            let previous = before.dropLast().last
            if let previous, previous.isLetter || previous.isNumber {
                proxy.deleteBackward()
                proxy.insertText(". ")
                lastKeyWasSpace = false
                lastCorrection = nil
                afterInsert()
                return
            }
        }

        lastCorrection = nil
        applyAutocorrect(boundary: " ")
        proxy.insertText(" ")
        lastKeyWasSpace = true
        if keyboardView.mode != .letters {
            keyboardView.mode = .letters
        }
        afterInsert()
    }

    func keyboardViewDidTapReturn(_ view: KeyboardView) {
        lastKeyWasSpace = false
        lastCorrection = nil
        applyAutocorrect(boundary: "\n")
        proxy.insertText("\n")
        afterInsert()
    }

    func keyboardView(_ view: KeyboardView, backspaceWholeWord: Bool) {
        lastKeyWasSpace = false

        // Backspace straight after an autocorrection restores what you typed.
        if !backspaceWholeWord, let correction = lastCorrection,
           let before = proxy.documentContextBeforeInput,
           before.hasSuffix(correction.corrected + correction.boundary) {
            deleteCharacters(correction.corrected.count + correction.boundary.count)
            proxy.insertText(correction.original)
            autocorrector.learn(correction.original)
            lastCorrection = nil
            updateAutoShift()
            refreshSuggestions()
            return
        }
        lastCorrection = nil

        if backspaceWholeWord, let before = proxy.documentContextBeforeInput, !before.isEmpty {
            var count = 0
            var sawWordChar = false
            for ch in before.reversed() {
                if ch.isWhitespace || ch.isPunctuation {
                    if sawWordChar { break }
                } else {
                    sawWordChar = true
                }
                count += 1
            }
            deleteCharacters(max(count, 1))
        } else {
            proxy.deleteBackward()
        }
        updateAutoShift()
        refreshSuggestions()
    }

    func keyboardViewShiftDown(_ view: KeyboardView) {
        shiftHeldDown = true
        typedWhileShiftHeld = false
        let now = Date()
        if settings.capsLock, let last = lastShiftTap, now.timeIntervalSince(last) < 0.35 {
            shiftState = .locked
            lastShiftTap = nil
            return
        }
        lastShiftTap = now
        shiftState = (shiftState == .off) ? .once : .off
    }

    func keyboardViewShiftUp(_ view: KeyboardView) {
        shiftHeldDown = false
        if typedWhileShiftHeld && shiftState != .locked {
            shiftState = .off
        }
        typedWhileShiftHeld = false
    }

    func keyboardViewDidTapNextKeyboard(_ view: KeyboardView) {
        advanceToNextInputMode()
    }

    func keyboardViewDidChangeMode(_ view: KeyboardView) {
        updateHeight()
        updateAutoShift()
    }
}

// MARK: - Suggestion bar

extension KeyboardViewController: SuggestionBarDelegate {
    func suggestionBar(_ bar: SuggestionBar, didPick suggestion: Suggestion) {
        let word = currentWord()
        if suggestion.isTypedWord {
            autocorrector.learn(word)
        } else {
            deleteCharacters(word.count)
            proxy.insertText(suggestion.text)
        }
        proxy.insertText(" ")
        lastKeyWasSpace = true
        lastCorrection = nil
        afterInsert()
    }

    func suggestionBarDidTapSettings(_ bar: SuggestionBar) {
        showSettings()
    }
}
