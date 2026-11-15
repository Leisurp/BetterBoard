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
    private var lastCorrectionCheck: (word: String, fix: String?)?
    private var suggestionTimer: Timer?

    private var proxy: UITextDocumentProxy { textDocumentProxy }

    // MARK: Local text mirror
    //
    // The host app's copy of the text (documentContextBeforeInput) updates
    // asynchronously and falls behind when typing fast. Reading it mid-burst made
    // autocorrect delete the wrong number of characters, which looked like missed
    // keys. So the keyboard keeps its own copy of the text before the cursor,
    // updated on every edit it makes, and only re-reads the host's copy after a
    // pause in typing (when it's guaranteed to be up to date).

    private var mirror = ""
    private var lastEditTime: CFTimeInterval = 0
    private let mirrorLimit = 400
    private let idleResyncDelay: CFTimeInterval = 0.6

    private func resyncMirror() {
        mirror = String((proxy.documentContextBeforeInput ?? "").suffix(mirrorLimit))
    }

    private func resyncMirrorIfIdle() {
        if CACurrentMediaTime() - lastEditTime > idleResyncDelay {
            resyncMirror()
        }
    }

    private func insert(_ text: String) {
        proxy.insertText(text)
        mirror += text
        if mirror.utf16.count > mirrorLimit * 2 {
            mirror = String(mirror.suffix(mirrorLimit))
        }
        lastEditTime = CACurrentMediaTime()
    }

    private func deleteBackward(_ count: Int = 1) {
        for _ in 0..<max(count, 0) {
            proxy.deleteBackward()
            if !mirror.isEmpty { mirror.removeLast() }
        }
        lastEditTime = CACurrentMediaTime()
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        suggestionBar.delegate = self
        suggestionBar.touchForwardTarget = keyboardView
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
        resyncMirror()
        updateForContext()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
    }

    // MARK: System edge gestures
    //
    // iOS holds back touches near the screen edges (left/right swipes, home bar)
    // while it decides whether they're system gestures. That delays or loses fast
    // taps on edge keys and the bottom row, so ask iOS to defer those gestures and
    // stop its recognisers from delaying our touches.

    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        [.left, .right, .bottom]
    }

    private func relaxSystemGestures() {
        var recognizers: [UIGestureRecognizer] = view.window?.gestureRecognizers ?? []
        var ancestor = view.superview
        while let current = ancestor {
            recognizers += current.gestureRecognizers ?? []
            ancestor = current.superview
        }
        for recognizer in recognizers {
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        relaxSystemGestures()
        // Some recognisers are attached after the keyboard appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.relaxSystemGestures()
        }
        // The text field's settings are sometimes only available once the keyboard is on screen.
        resyncMirror()
        updateForContext()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // Mid-typing this fires for our own edits too, so only trust the host's
        // text (cursor moved, app cleared the field…) once typing has paused.
        resyncMirrorIfIdle()
        updateForContext()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        resyncMirrorIfIdle()
        updateAutoShift()
        scheduleSuggestions()
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
        scheduleSuggestions()
    }

    private func updateAppearance() {
        let appearance = proxy.keyboardAppearance ?? .default
        let isDark = appearance == .dark
            || (appearance != .light && traitCollection.userInterfaceStyle == .dark)
        guard isDark != keyboardView.theme.isDark || isDark != suggestionBar.theme.isDark else { return }
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
        var chars: [Character] = []
        for ch in mirror.reversed() {
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

    /// Replaces the word before the cursor if it's misspelled.
    private func applyAutocorrect(boundary: String) {
        guard fieldAllowsCorrection else { return }
        let word = currentWord()
        guard !word.isEmpty,
              let fixed = cachedCorrection(for: word),
              fixed != word else { return }
        deleteBackward(word.count)
        insert(fixed)
        lastCorrection = Correction(original: word, corrected: fixed, boundary: boundary)
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
        scheduleSuggestions()
    }

    // MARK: Shift / auto-capitalisation

    private func updateAutoShift() {
        guard shiftState != .locked, !shiftHeldDown else { return }
        guard settings.autocap, keyboardView.mode == .letters else {
            if shiftState == .once { shiftState = .off }
            return
        }

        let before = mirror
        var capType = proxy.autocapitalizationType ?? .sentences
        // Some text fields report "none" to third-party keyboards even though Apple's
        // keyboard capitalises there. Only honour "none" for fields that really
        // shouldn't capitalise (web addresses, emails, fields without autocorrect).
        if capType == .none, proxy.autocorrectionType != .no {
            switch proxy.keyboardType ?? .default {
            case .URL, .emailAddress, .webSearch, .twitter:
                break
            default:
                capType = .sentences
            }
        }
        let shouldCapitalise: Bool
        switch capType {
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
        guard let last = before.last else { return true }
        if last.isNewline { return true }
        guard last == " " else { return false }
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        guard let end = trimmed.last else { return true }
        return end == "." || end == "!" || end == "?" || end.isNewline
    }

    // MARK: Suggestions

    /// Spell-checking is slow, so it never runs while typing: the bar updates
    /// once typing pauses.
    private func scheduleSuggestions() {
        suggestionTimer?.invalidate()
        suggestionTimer = nil
        if !fieldAllowsCorrection || currentWord().isEmpty {
            suggestionBar.setSuggestions([])
            return
        }
        suggestionTimer = Timer.scheduledTimer(timeInterval: 0.3,
                                               target: self,
                                               selector: #selector(suggestionTimerFired),
                                               userInfo: nil,
                                               repeats: false)
    }

    @objc private func suggestionTimerFired() {
        suggestionTimer = nil
        refreshSuggestions()
    }

    /// Autocorrection for `word`, remembered so the spell checker runs once per word.
    private func cachedCorrection(for word: String) -> String? {
        if let cached = lastCorrectionCheck, cached.word == word {
            return cached.fix
        }
        let fix = autocorrector.correction(for: word)
        lastCorrectionCheck = (word, fix)
        return fix
    }

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
        if let fix = cachedCorrection(for: word), fix != word {
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
        resyncMirror()
        updateForContext()
    }
}

// MARK: - Key handling

extension KeyboardViewController: KeyboardViewDelegate {
    func keyboardView(_ keyboard: KeyboardView, didType text: String) {
        resyncMirrorIfIdle()
        lastKeyWasSpace = false
        lastCorrection = nil
        let breaksWord = [".", ",", "!", "?", ";", ":", ")", "\""].contains(text)
        if breaksWord {
            applyAutocorrect(boundary: text)
        }
        insert(text)
        afterInsert()
    }

    func keyboardViewDidTapSpace(_ keyboard: KeyboardView) {
        resyncMirrorIfIdle()

        // Double-space full stop.
        if settings.doubleSpacePeriod, lastKeyWasSpace, mirror.hasSuffix(" ") {
            let previous = mirror.dropLast().last
            if let previous, previous.isLetter || previous.isNumber {
                deleteBackward()
                insert(". ")
                lastKeyWasSpace = false
                lastCorrection = nil
                afterInsert()
                return
            }
        }

        lastCorrection = nil
        applyAutocorrect(boundary: " ")
        insert(" ")
        lastKeyWasSpace = true
        if keyboardView.mode != .letters {
            keyboardView.mode = .letters
        }
        afterInsert()
    }

    func keyboardViewDidTapReturn(_ keyboard: KeyboardView) {
        resyncMirrorIfIdle()
        lastKeyWasSpace = false
        lastCorrection = nil
        applyAutocorrect(boundary: "\n")
        insert("\n")
        afterInsert()
    }

    func keyboardView(_ keyboard: KeyboardView, backspaceWholeWord: Bool) {
        resyncMirrorIfIdle()
        lastKeyWasSpace = false

        // Backspace straight after an autocorrection restores what you typed.
        if !backspaceWholeWord, let correction = lastCorrection,
           mirror.hasSuffix(correction.corrected + correction.boundary) {
            deleteBackward(correction.corrected.count + correction.boundary.count)
            insert(correction.original)
            autocorrector.learn(correction.original)
            lastCorrection = nil
            updateAutoShift()
            scheduleSuggestions()
            return
        }
        lastCorrection = nil

        if backspaceWholeWord, !mirror.isEmpty {
            var count = 0
            var sawWordChar = false
            for ch in mirror.reversed() {
                if ch.isWhitespace || ch.isPunctuation {
                    if sawWordChar { break }
                } else {
                    sawWordChar = true
                }
                count += 1
            }
            deleteBackward(max(count, 1))
        } else {
            deleteBackward()
        }
        updateAutoShift()
        scheduleSuggestions()
    }

    func keyboardViewShiftDown(_ keyboard: KeyboardView) {
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

    func keyboardViewShiftUp(_ keyboard: KeyboardView) {
        shiftHeldDown = false
        if typedWhileShiftHeld && shiftState != .locked {
            shiftState = .off
        }
        typedWhileShiftHeld = false
    }

    func keyboardViewDidTapNextKeyboard(_ keyboard: KeyboardView) {
        advanceToNextInputMode()
    }

    func keyboardViewDidChangeMode(_ keyboard: KeyboardView) {
        updateHeight()
        updateAutoShift()
    }
}

// MARK: - Suggestion bar

extension KeyboardViewController: SuggestionBarDelegate {
    func suggestionBar(_ bar: SuggestionBar, didPick suggestion: Suggestion) {
        resyncMirrorIfIdle()
        let word = currentWord()
        if suggestion.isTypedWord {
            autocorrector.learn(word)
        } else {
            deleteBackward(word.count)
            insert(suggestion.text)
        }
        insert(" ")
        lastKeyWasSpace = true
        lastCorrection = nil
        afterInsert()
    }

    func suggestionBarDidTapSettings(_ bar: SuggestionBar) {
        showSettings()
    }
}
