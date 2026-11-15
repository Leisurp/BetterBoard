import UIKit
import UniformTypeIdentifiers

/// iOS entry point for the keyboard. Owns the text logic: inserting, deleting,
/// shift / auto-capitalisation, double-space full stop and autocorrect.
final class KeyboardViewController: UIInputViewController {
    private let settings = KeyboardSettings.shared
    private let autocorrector = Autocorrector()
    private let suggestionBar = SuggestionBar()
    private let keyboardView = KeyboardView()
    private var settingsPanel: SettingsPanel?

    // GIFs and clipboard history (need Full Access).
    private let clipboard = ClipboardStore()
    private let giphy = GiphyClient()
    private var gifPanel: GifPanel?
    private var clipboardPanel: ClipboardPanel?
    private var gifSearchField: GifSearchField?
    /// Non-nil while typing a GIF search: keys type into the search box instead.
    private var gifQuery: String?
    private var lastGifQuery: String?
    private var clipboardTimer: Timer?
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
        let fresh = String((proxy.documentContextBeforeInput ?? "").suffix(mirrorLimit))
        if fresh != mirror {
            mirror = fresh
            wordOffsets.removeAll() // cursor moved or text changed: touch history no longer applies
        }
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
        // Clipboard history: iOS only lets the keyboard look while it's on screen.
        checkClipboard()
        clipboardTimer?.invalidate()
        clipboardTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self,
                                              selector: #selector(checkClipboard),
                                              userInfo: nil, repeats: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        giphy.clearImageCache()
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
        if gifQuery == nil {
            keyboardView.returnKeyType = proxy.returnKeyType ?? .default
        }
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

    /// Whether words typed here should be corrected automatically.
    private var autoApplyCorrections: Bool {
        settings.autocorrect && fieldAllowsCorrection
    }

    /// Whether this field gets suggestions at all (not for web addresses, emails, numbers…).
    private var fieldAllowsCorrection: Bool {
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

    /// Replaces the word before the cursor if autocorrect has a better word.
    private func applyAutocorrect(boundary: String) {
        let word = currentWord()
        guard !word.isEmpty, fieldAllowsCorrection else { return }
        guard let fixed = analysis()?.correction, fixed != word else {
            autocorrector.noteCommitted(word)
            return
        }
        deleteBackward(word.count)
        insert(fixed)
        lastCorrection = Correction(original: word, corrected: fixed, boundary: boundary)
    }

    // MARK: Touch positions for the current word
    //
    // Where each letter was touched (relative to the key's centre) lets autocorrect
    // tell "tapped the edge of e, probably meant w" from "tapped dead centre of e".

    private var wordOffsets: [CGPoint] = []

    private func resetWordOffsets() {
        wordOffsets.removeAll()
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
        guard shiftState != .locked, !shiftHeldDown, gifQuery == nil else { return }
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

    private var cachedAnalysis: (key: String, result: Autocorrector.Analysis)?
    private var suggestionsPending = false

    /// The word before the current one, or "<s>" at the start of a sentence.
    private func previousWord() -> String {
        var text = Substring(mirror)
        // Skip the word being typed.
        while let last = text.last, last.isLetter || last == "'" || last == "\u{2019}" {
            text = text.dropLast()
        }
        // Skip spaces and commas between words.
        while let last = text.last, last == " " || last == "," || last == "\u{00A0}" {
            text = text.dropLast()
        }
        guard let last = text.last, last.isLetter || last == "'" || last == "\u{2019}" else {
            return Predictor.sentenceStart
        }
        var word: [Character] = []
        for ch in text.reversed() {
            if ch.isLetter || ch == "'" || ch == "\u{2019}" { word.append(ch) } else { break }
        }
        return String(word.reversed())
    }

    /// Autocorrect's verdict on the current word (cached until the word changes).
    private func analysis() -> Autocorrector.Analysis? {
        let word = currentWord()
        guard !word.isEmpty, fieldAllowsCorrection else { return nil }
        let autoApply = autoApplyCorrections
        let previous = previousWord()
        let showEmoji = settings.emojiSuggestions
        let key = "\(word)|\(wordOffsets.count)|\(autoApply)|\(previous)|\(showEmoji)"
        if let cached = cachedAnalysis, cached.key == key {
            return cached.result
        }
        let result = autocorrector.analyze(word: word, offsets: wordOffsets, previous: previous,
                                           autoApply: autoApply, showEmoji: showEmoji)
        cachedAnalysis = (key, result)
        return result
    }

    /// Updates the bar live, like Gboard. Several quick keystrokes queued up
    /// together only cost one update.
    private func scheduleSuggestions() {
        guard !suggestionsPending else { return }
        suggestionsPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.suggestionsPending = false
            self.refreshSuggestions()
        }
    }

    private func refreshSuggestions() {
        if let analysis = analysis() {
            suggestionBar.setSuggestions(analysis.suggestions)
        } else if currentWord().isEmpty, fieldAllowsCorrection, settings.nextWord,
                  keyboardView.mode == .letters, mirror.isEmpty || mirror.last?.isWhitespace == true {
            // Before a word is started: predict the next word, like Gboard.
            suggestionBar.setSuggestions(autocorrector.predictions(previous: previousWord(),
                                                                   capitalise: shiftState != .off,
                                                                   showEmoji: settings.emojiSuggestions))
        } else {
            suggestionBar.setSuggestions([])
        }
    }

    // MARK: Settings panel

    private func showSettings() {
        guard settingsPanel == nil else { return }
        dismissPanels()
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
    func keyboardView(_ keyboard: KeyboardView, didType text: String, touchOffset: CGPoint?) {
        if handleGifSearchKey(.text(text)) { return }
        resyncMirrorIfIdle()
        lastKeyWasSpace = false
        lastCorrection = nil
        let isLetter = text.count == 1 && (text.first?.isLetter ?? false)
        let isApostrophe = text == "'" || text == "\u{2019}"
        if isLetter {
            if currentWord().isEmpty { resetWordOffsets() }
            insert(text)
            wordOffsets.append(touchOffset ?? .zero)
        } else if isApostrophe {
            insert(text)
        } else {
            let breaksWord = [".", ",", "!", "?", ";", ":", ")", "\""].contains(text)
            if breaksWord {
                applyAutocorrect(boundary: text)
            }
            insert(text)
            resetWordOffsets()
        }
        afterInsert()
    }

    func keyboardViewDidTapSpace(_ keyboard: KeyboardView) {
        if handleGifSearchKey(.space) { return }
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
        resetWordOffsets()
        lastKeyWasSpace = true
        if keyboardView.mode != .letters {
            keyboardView.mode = .letters
        }
        afterInsert()
    }

    func keyboardViewDidTapReturn(_ keyboard: KeyboardView) {
        if handleGifSearchKey(.submit) { return }
        resyncMirrorIfIdle()
        lastKeyWasSpace = false
        lastCorrection = nil
        applyAutocorrect(boundary: "\n")
        insert("\n")
        resetWordOffsets()
        afterInsert()
    }

    func keyboardView(_ keyboard: KeyboardView, backspaceWholeWord: Bool) {
        if handleGifSearchKey(.backspace) { return }
        resyncMirrorIfIdle()
        lastKeyWasSpace = false

        // Backspace straight after an autocorrection restores what you typed.
        if !backspaceWholeWord, let correction = lastCorrection,
           mirror.hasSuffix(correction.corrected + correction.boundary) {
            deleteBackward(correction.corrected.count + correction.boundary.count)
            insert(correction.original)
            resetWordOffsets()
            // Gboard-style: undoing a correction teaches the keyboard your word.
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
            resetWordOffsets()
        } else {
            if mirror.last?.isLetter == true, !wordOffsets.isEmpty {
                wordOffsets.removeLast()
            }
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
            // Words and emoji replace what's being typed (Gboard); predictions and
            // emoji offered after a space are simply added.
            deleteBackward(word.count)
            insert(suggestion.text)
        }
        insert(" ")
        resetWordOffsets()
        lastKeyWasSpace = true
        lastCorrection = nil
        afterInsert()
    }

    func suggestionBarDidTapSettings(_ bar: SuggestionBar) {
        showSettings()
    }

    func suggestionBarDidTapGif(_ bar: SuggestionBar) {
        showGifPanel(query: nil)
    }

    func suggestionBarDidTapClipboard(_ bar: SuggestionBar) {
        showClipboardPanel()
    }
}

// MARK: - GIFs & clipboard

extension KeyboardViewController: GifPanelDelegate, ClipboardPanelDelegate {
    private enum GifSearchKey {
        case text(String), space, backspace, submit
    }

    private var isDark: Bool { keyboardView.theme.isDark }

    /// While searching for GIFs, keys type into the search box instead of the document.
    private func handleGifSearchKey(_ key: GifSearchKey) -> Bool {
        guard var query = gifQuery else { return false }
        switch key {
        case .text(let text):
            query += text
        case .space:
            query += " "
        case .backspace:
            if !query.isEmpty { query.removeLast() }
        case .submit:
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            showGifPanel(query: trimmed.isEmpty ? nil : trimmed)
            return true
        }
        gifQuery = query
        gifSearchField?.setQuery(query)
        if shiftState == .once { shiftState = .off }
        return true
    }

    @objc private func checkClipboard() {
        guard hasFullAccess else { return }
        let result = clipboard.capture()
        if let key = result.giphyKey {
            settings.giphyKey = key
            if gifPanel != nil { loadGifs(query: lastGifQuery) }
        }
        if result.changed { clipboardPanel?.reload() }
    }

    private func presentPanel(_ panel: UIView) {
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: view.topAnchor),
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        keyboardView.isHidden = true
        suggestionBar.isHidden = true
    }

    /// Back to the normal keyboard.
    private func dismissPanels() {
        gifPanel?.removeFromSuperview()
        gifPanel = nil
        clipboardPanel?.removeFromSuperview()
        clipboardPanel = nil
        gifSearchField?.removeFromSuperview()
        gifSearchField = nil
        gifQuery = nil
        keyboardView.returnKeyType = proxy.returnKeyType ?? .default
        keyboardView.isHidden = false
        suggestionBar.isHidden = false
        updateAutoShift()
        scheduleSuggestions()
    }

    /// Opens the BetterBoard app. Keyboards have no official way to do this, so find
    /// the app object through the responder chain and call `open(_:options:completionHandler:)`
    /// dynamically (it's hidden from extensions at compile time), as other keyboards do.
    private func openApp(_ link: String) {
        guard let url = URL(string: link) else { return }
        typealias OpenFunction = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if current is UIApplication, current.responds(to: selector) {
                let open = unsafeBitCast(current.method(for: selector), to: OpenFunction.self)
                open(current, selector, url as NSURL, NSDictionary(), nil)
                return
            }
            responder = current.next
        }
    }

    // MARK: GIFs

    private func showGifPanel(query: String?) {
        dismissPanels()
        let panel = GifPanel(client: giphy, isDark: isDark, query: query)
        panel.delegate = self
        gifPanel = panel
        lastGifQuery = query
        presentPanel(panel)

        guard hasFullAccess else {
            panel.setState(.needsSetup("""
                GIFs need a quick one-time setup.
                Turn on Full Access so the keyboard can fetch GIFs and copy them for pasting, \
                and add a free Giphy key so it can search them.
                """))
            return
        }
        checkClipboard() // picks up a key the app just sent
        guard let key = settings.giphyKey, !key.isEmpty else {
            panel.setState(.needsSetup("""
                Almost there! GIFs come from Giphy, which needs a free key.
                The app walks you through getting one (about 2 minutes).
                """))
            return
        }
        giphy.apiKey = key
        loadGifs(query: query)
    }

    private func loadGifs(query: String?) {
        guard let panel = gifPanel else { return }
        giphy.apiKey = settings.giphyKey
        panel.setState(.loading)
        let completion: (Result<[GifItem], GiphyClient.Failure>) -> Void = { [weak self, weak panel] result in
            guard let self, let panel, panel === self.gifPanel else { return }
            switch result {
            case .success(let items):
                panel.setState(.items(items))
            case .failure(.badKey):
                panel.setState(.needsSetup("Giphy didn't accept your key. Check it in the BetterBoard app."))
            case .failure(.offline):
                panel.setState(.message("Can't reach Giphy. Check your internet connection."))
            case .failure(.server):
                panel.setState(.message("Giphy isn't responding right now. Try again in a moment."))
            }
        }
        if let query, !query.isEmpty {
            giphy.search(query, completion: completion)
        } else {
            giphy.trending(completion: completion)
        }
    }

    private func startGifSearch() {
        gifPanel?.removeFromSuperview()
        gifPanel = nil
        let field = GifSearchField(isDark: isDark)
        field.onCancel = { [weak self] in
            guard let self else { return }
            self.showGifPanel(query: self.lastGifQuery)
        }
        field.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(field)
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: view.topAnchor),
            field.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            field.heightAnchor.constraint(equalToConstant: Metrics.barHeight),
        ])
        gifSearchField = field
        gifQuery = ""
        if keyboardView.mode != .letters { keyboardView.mode = .letters }
        keyboardView.returnKeyType = .search
        keyboardView.isHidden = false
        suggestionBar.isHidden = true
        shiftState = .off
    }

    func gifPanelClose(_ panel: GifPanel) {
        dismissPanels()
    }

    func gifPanelBeginSearch(_ panel: GifPanel) {
        startGifSearch()
    }

    func gifPanelOpenSetup(_ panel: GifPanel) {
        openApp("betterboard://setup/gifs")
    }

    func gifPanel(_ panel: GifPanel, didSelectCategory query: String?) {
        lastGifQuery = query
        loadGifs(query: query)
    }

    func gifPanel(_ panel: GifPanel, didPick item: GifItem) {
        panel.showToast("Copying GIF…")
        giphy.download(item.shareURL) { [weak self, weak panel] data in
            guard let self, let panel else { return }
            guard let data else {
                panel.showToast("Couldn't download that GIF")
                return
            }
            // Keyboards can only type text, so the GIF goes on the clipboard (as Gboard does).
            UIPasteboard.general.setData(data, forPasteboardType: UTType.gif.identifier)
            self.clipboard.ignoreCurrentClipboard()
            panel.showToast("GIF copied! Tap the text box and choose Paste")
        }
    }

    // MARK: Clipboard

    private func showClipboardPanel() {
        dismissPanels()
        if hasFullAccess { checkClipboard() }
        let panel = ClipboardPanel(store: clipboard, isDark: isDark, hasFullAccess: hasFullAccess)
        panel.delegate = self
        clipboardPanel = panel
        presentPanel(panel)
    }

    func clipboardPanelClose(_ panel: ClipboardPanel) {
        dismissPanels()
    }

    func clipboardPanelOpenSetup(_ panel: ClipboardPanel) {
        openApp("betterboard://setup/clipboard")
    }

    func clipboardPanel(_ panel: ClipboardPanel, didPick text: String) {
        resyncMirrorIfIdle()
        insert(text)
        resetWordOffsets()
        lastCorrection = nil
        lastKeyWasSpace = false
        dismissPanels()
    }
}
