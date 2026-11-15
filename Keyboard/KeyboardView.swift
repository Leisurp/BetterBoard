import UIKit

protocol KeyboardViewDelegate: AnyObject {
    /// `touchOffset`: for letters, where the key was touched relative to its centre,
    /// in key-pitch units (0,0 = dead centre; 0.5 = halfway to the next key).
    func keyboardView(_ view: KeyboardView, didType text: String, touchOffset: CGPoint?)
    func keyboardViewDidTapSpace(_ view: KeyboardView)
    func keyboardViewDidTapReturn(_ view: KeyboardView)
    func keyboardView(_ view: KeyboardView, backspaceWholeWord: Bool)
    func keyboardViewShiftDown(_ view: KeyboardView)
    func keyboardViewShiftUp(_ view: KeyboardView)
    func keyboardViewDidTapNextKeyboard(_ view: KeyboardView)
    func keyboardViewDidChangeMode(_ view: KeyboardView)
    /// Slide on the space bar: move the cursor this many characters (negative = left).
    func keyboardView(_ view: KeyboardView, moveCursorBy offset: Int)
    func keyboardViewDidEndCursorSlide(_ view: KeyboardView)
    /// Slide left from backspace: the total number of words that should now be deleted
    /// since the slide began (going back right lowers it and restores words).
    func keyboardView(_ view: KeyboardView, deleteSwipeWords words: Int)
    func keyboardViewDidEndDeleteSwipe(_ view: KeyboardView)
}

/// Gboard-style slide gestures.
private enum Slide {
    /// Space bar: how far the finger moves before it becomes a cursor slide
    /// (big enough that a rolling thumb while typing fast still types a space).
    static let cursorStart: CGFloat = 20
    /// Space bar: finger travel per character moved.
    static let cursorStep: CGFloat = 10
    /// Backspace: finger travel (to the left) per word deleted.
    static let deleteStep: CGFloat = 26
}

/// Draws every key and handles all touches itself (multi-touch, hold-for-symbol,
/// backspace repeat). Popups draw above the view's top edge, over the suggestion bar.
final class KeyboardView: UIView {
    weak var delegate: KeyboardViewDelegate?
    /// Every key press (for click sound / vibration).
    var onKeyDown: ((KeyAction) -> Void)?
    /// Each step of a space-bar cursor slide.
    var onCursorStep: (() -> Void)?

    var mode: KeyboardMode = .letters {
        didSet { if oldValue != mode { rebuild(); delegate?.keyboardViewDidChangeMode(self) } }
    }
    /// The text box's kind: changes the bottom row (web / email) or shows the number pad.
    var field: FieldKind = .normal {
        didSet { if oldValue != field { rebuild(); delegate?.keyboardViewDidChangeMode(self) } }
    }
    var shiftState: ShiftState = .off {
        didSet {
            guard oldValue != shiftState else { return }
            for row in rows { for key in row { key.updateShift(shiftState) } }
        }
    }
    var returnKeyType: UIReturnKeyType = .default {
        didSet { if oldValue != returnKeyType { refreshKeys() } }
    }
    var theme = Theme(isDark: false) {
        didSet { if !oldValue.matches(theme) { refreshKeys() } }
    }

    private let settings = KeyboardSettings.shared
    private var rows: [[KeyView]] = []
    private var pinEndsRows: [Bool] = []
    private var hitFrames: [ObjectIdentifier: CGRect] = [:]
    private let popup = KeyPopupView()

    // MARK: Touch tracking

    private final class TouchState {
        var key: KeyView
        var startPoint: CGPoint = .zero
        /// Where the finger was when the current key was chosen (for autocorrect).
        var touchPoint: CGPoint = .zero
        var held = false
        /// What holding the key offers: its corner symbol, then accents etc.
        var options: [String] = []
        var selectedOption = 0
        var holdTimer: Timer?
        var repeatTimer: Timer?
        var repeatCount = 0
        enum SlideKind { case cursor, delete }
        /// Set once a space-bar or backspace touch turns into a slide gesture.
        var slide: SlideKind?
        var slideAnchorX: CGFloat = 0
        var slideWords = 0

        init(key: KeyView) { self.key = key }

        func stopTimers() {
            holdTimer?.invalidate()
            holdTimer = nil
            repeatTimer?.invalidate()
            repeatTimer = nil
        }
    }

    private var touchStates: [UITouch: TouchState] = [:]
    private weak var popupOwner: TouchState?

    // MARK: Setup

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        clipsToBounds = false
        backgroundColor = Touch.touchableBackground
        popup.hide()
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var scale: CGFloat { settings.heightSize.scale }
    private var keyHeight: CGFloat { Metrics.keyHeight * scale }
    private var rowGap: CGFloat { Metrics.rowGap * scale }
    private var fontScale: CGFloat { 0.94 + 0.06 * scale }

    /// Height of the keys area (not including the suggestion bar).
    var preferredHeight: CGFloat {
        let count = CGFloat(Layout.rows(mode: mode, numberRow: settings.numberRow && mode == .letters, field: field).count)
        return Metrics.topInset + count * keyHeight + (count - 1) * rowGap + Metrics.bottomInset
    }

    /// Re-creates all keys (mode or settings changed).
    func rebuild() {
        cancelAllTouches()
        rows.flatMap { $0 }.forEach { $0.removeFromSuperview() }
        let layout = Layout.rows(mode: mode, numberRow: settings.numberRow && mode == .letters, field: field)
        rows = layout.map { row in row.keys.map { KeyView(def: $0) } }
        pinEndsRows = layout.map { $0.pinEnds }
        rows.flatMap { $0 }.forEach { addSubview($0) }
        popup.removeFromSuperview()
        addSubview(popup)
        refreshKeys()
        setNeedsLayout()
    }

    /// Updates labels / colours without re-creating keys.
    func refreshKeys() {
        let showHints = settings.showHints && settings.holdForSymbols
        for key in rows.flatMap({ $0 }) {
            key.configure(theme: theme,
                          shift: shiftState,
                          showHint: showHints,
                          returnKeyType: returnKeyType,
                          fontScale: fontScale)
        }
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        guard width > 0 else { return }

        let margin = Metrics.sideMargin
        let gap = Metrics.keyGap
        let unit = (width - margin * 2 - gap * 9) / 10
        hitFrames.removeAll()

        for (rowIndex, row) in rows.enumerated() {
            let y = Metrics.topInset + CGFloat(rowIndex) * (keyHeight + rowGap)
            let widths: [CGFloat?] = row.map { key in
                if case .units(let u) = key.def.width { return u * unit }
                return nil
            }
            let fixedTotal = widths.compactMap { $0 }.reduce(0, +)
            let flexCount = widths.filter { $0 == nil }.count
            let gapsTotal = gap * CGFloat(max(row.count - 1, 0))

            var frames: [CGRect] = []
            if flexCount > 0 {
                let flexWidth = max(0, (width - margin * 2 - fixedTotal - gapsTotal) / CGFloat(flexCount))
                var x = margin
                for w in widths {
                    let kw = w ?? flexWidth
                    frames.append(CGRect(x: x, y: y, width: kw, height: keyHeight))
                    x += kw + gap
                }
            } else if pinEndsRows[rowIndex], row.count >= 3 {
                let first = widths.first!!, last = widths.last!!
                frames.append(CGRect(x: margin, y: y, width: first, height: keyHeight))
                let middle = widths[1..<(widths.count - 1)].map { $0! }
                let middleTotal = middle.reduce(0, +) + gap * CGFloat(middle.count - 1)
                var x = (width - middleTotal) / 2
                for w in middle {
                    frames.append(CGRect(x: x, y: y, width: w, height: keyHeight))
                    x += w + gap
                }
                frames.append(CGRect(x: width - margin - last, y: y, width: last, height: keyHeight))
            } else {
                var x = (width - fixedTotal - gapsTotal) / 2
                for w in widths {
                    let kw = w ?? 0
                    frames.append(CGRect(x: x, y: y, width: kw, height: keyHeight))
                    x += kw + gap
                }
            }

            for (key, frame) in zip(row, frames) {
                key.frame = frame
                hitFrames[ObjectIdentifier(key)] = frame.insetBy(dx: -gap / 2, dy: -rowGap / 2)
            }
        }
    }

    // MARK: Hit testing

    private func key(at point: CGPoint) -> KeyView? {
        let all = rows.flatMap { $0 }
        if let hit = all.first(where: { hitFrames[ObjectIdentifier($0)]?.contains(point) ?? false }) {
            return hit
        }
        // Gaps / edges: use the nearest key.
        var best: KeyView?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for key in all {
            let f = key.frame
            let dx = max(f.minX - point.x, 0, point.x - f.maxX)
            let dy = max(f.minY - point.y, 0, point.y - f.maxY)
            let d = dx * dx + dy * dy
            if d < bestDistance {
                bestDistance = d
                best = key
            }
        }
        return best
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Two fingers can land in the same event; handle them in the order they landed.
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard let key = key(at: touch.location(in: self)) else { continue }
            // Fast typing: a new finger finishes any key that's still down.
            commitPendingTouches()
            let state = TouchState(key: key)
            state.startPoint = touch.location(in: self)
            state.touchPoint = state.startPoint
            touchStates[touch] = state
            onKeyDown?(key.def.action)
            keyDown(state)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let state = touchStates[touch] else { continue }
            let point = touch.location(in: self)
            switch state.key.def.action {
            case .space:
                trackCursorSlide(state, at: point)
            case .backspace:
                trackDeleteSwipe(state, at: point)
            case .character where state.held && state.options.count > 1:
                // Choosing from the row of options.
                let index = popup.optionIndex(atX: point.x)
                if index != state.selectedOption {
                    state.selectedOption = index
                    popup.selectOption(index)
                }
            case .character:
                trackKeySlide(state, at: point)
            default:
                break
            }
        }
    }

    private func trackKeySlide(_ state: TouchState, at point: CGPoint) {
        // Fast typing rolls the finger a little as it lifts. Only treat it as a
        // deliberate slide to another key once it has moved well away.
        guard !state.held,
              hypot(point.x - state.startPoint.x, point.y - state.startPoint.y) > state.key.bounds.width * 0.75,
              let newKey = key(at: point),
              newKey !== state.key,
              newKey.def.action == .character else { return }
        // Slide to a neighbouring key before the hold kicks in.
        state.stopTimers()
        state.key.isPressed = false
        state.key = newKey
        state.touchPoint = point
        keyDown(state)
    }

    /// Slide left or right on the space bar to move the cursor (Gboard).
    private func trackCursorSlide(_ state: TouchState, at point: CGPoint) {
        if state.slide == nil {
            let dx = point.x - state.startPoint.x
            guard abs(dx) > Slide.cursorStart else { return }
            state.slide = .cursor
            // Start counting from where the slide began, so the first step comes quickly.
            state.slideAnchorX = state.startPoint.x + (dx > 0 ? Slide.cursorStart : -Slide.cursorStart) * 0.5
            setOtherKeysDimmed(true, except: state.key)
        }
        var moved = 0
        while point.x - state.slideAnchorX >= Slide.cursorStep {
            moved += 1
            state.slideAnchorX += Slide.cursorStep
        }
        while state.slideAnchorX - point.x >= Slide.cursorStep {
            moved -= 1
            state.slideAnchorX -= Slide.cursorStep
        }
        if moved != 0 {
            delegate?.keyboardView(self, moveCursorBy: moved)
            onCursorStep?()
        }
    }

    /// Slide left from backspace to delete whole words; slide back right to bring them back.
    private func trackDeleteSwipe(_ state: TouchState, at point: CGPoint) {
        let travel = state.startPoint.x - point.x
        if state.slide == nil {
            guard travel > Slide.deleteStep else { return }
            state.slide = .delete
            state.stopTimers() // no more repeat-delete once it's a swipe
        }
        let words = max(0, Int(travel / Slide.deleteStep))
        if words != state.slideWords {
            state.slideWords = words
            delegate?.keyboardView(self, deleteSwipeWords: words)
        }
    }

    private func setOtherKeysDimmed(_ dimmed: Bool, except keep: KeyView? = nil) {
        UIView.animate(withDuration: 0.15) {
            for key in self.rows.flatMap({ $0 }) where key !== keep {
                key.alpha = dimmed ? 0.35 : 1
            }
        }
    }

    /// Finishes a slide gesture. Returns true if the touch was a slide.
    private func endSlide(_ state: TouchState) -> Bool {
        switch state.slide {
        case .cursor:
            setOtherKeysDimmed(false)
            delegate?.keyboardViewDidEndCursorSlide(self)
            return true
        case .delete:
            delegate?.keyboardViewDidEndDeleteSwipe(self)
            return true
        case nil:
            return false
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard let state = touchStates.removeValue(forKey: touch) else { continue }
            keyUp(state, commit: true)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // iOS sometimes cancels fast taps (system gestures near the screen edges).
        // Still type letters and spaces so they don't go missing.
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard let state = touchStates.removeValue(forKey: touch) else { continue }
            let action = state.key.def.action
            keyUp(state, commit: action == .character || action == .space)
        }
    }

    private func commitPendingTouches() {
        for (touch, state) in touchStates where state.slide == nil {
            switch state.key.def.action {
            case .shift, .backspace:
                continue
            default:
                touchStates.removeValue(forKey: touch)
                keyUp(state, commit: true)
            }
        }
    }

    private func cancelAllTouches() {
        for state in touchStates.values {
            state.stopTimers()
            state.key.isPressed = false
            _ = endSlide(state)
        }
        touchStates.removeAll()
        popup.hide()
        popupOwner = nil
    }

    private func keyDown(_ state: TouchState) {
        let key = state.key
        switch key.def.action {
        case .character:
            if settings.keyPopup {
                showPopup(for: state, text: key.output)
            } else {
                key.isPressed = true
            }
            state.options = holdOptions(for: key)
            state.selectedOption = 0
            if !state.options.isEmpty {
                let delay = TimeInterval(settings.longPressDelayMs) / 1000
                state.holdTimer = Timer.scheduledTimer(timeInterval: delay,
                                                       target: self,
                                                       selector: #selector(holdTimerFired(_:)),
                                                       userInfo: state,
                                                       repeats: false)
            }

        case .backspace:
            key.isPressed = true
            delegate?.keyboardView(self, backspaceWholeWord: false)
            state.repeatTimer = Timer.scheduledTimer(timeInterval: 0.45,
                                                     target: self,
                                                     selector: #selector(backspaceRepeatStart(_:)),
                                                     userInfo: state,
                                                     repeats: false)

        case .shift:
            key.isPressed = true
            delegate?.keyboardViewShiftDown(self)

        default:
            key.isPressed = true
        }
    }

    private func keyUp(_ state: TouchState, commit: Bool) {
        state.stopTimers()
        let key = state.key
        key.isPressed = false
        if popupOwner === state {
            popup.hide()
            popupOwner = nil
        }

        if key.def.action == .shift {
            delegate?.keyboardViewShiftUp(self)
            return
        }
        // A slide on the space bar or backspace has already done its job.
        if endSlide(state) { return }
        guard commit else { return }

        switch key.def.action {
        case .character:
            let text = state.held && state.selectedOption < state.options.count
                ? state.options[state.selectedOption] : key.output
            var offset: CGPoint?
            if !state.held, key.def.isLetter {
                let pitchX = key.frame.width + Metrics.keyGap
                let pitchY = keyHeight + rowGap
                offset = CGPoint(x: (state.touchPoint.x - key.frame.midX) / pitchX,
                                 y: (state.touchPoint.y - key.frame.midY) / pitchY)
            }
            delegate?.keyboardView(self, didType: text, touchOffset: offset)
        case .space:
            delegate?.keyboardViewDidTapSpace(self)
        case .returnKey:
            delegate?.keyboardViewDidTapReturn(self)
        case .mode(let newMode):
            mode = newMode
        case .nextKeyboard:
            delegate?.keyboardViewDidTapNextKeyboard(self)
        case .shift, .backspace:
            break
        }
    }

    private func isActive(_ state: TouchState) -> Bool {
        touchStates.values.contains { $0 === state }
    }

    /// The corner symbol (if hold-for-symbols is on) followed by accents and similar
    /// characters, cased to match the key.
    private func holdOptions(for key: KeyView) -> [String] {
        var options: [String] = []
        if settings.holdForSymbols, let hint = key.def.hint { options.append(hint) }
        let upper = key.def.isLetter && key.output != key.def.text
        for option in Layout.alternates[key.def.text] ?? [] {
            options.append(upper ? option.uppercased() : option)
        }
        return options
    }

    @objc private func holdTimerFired(_ timer: Timer) {
        guard let state = timer.userInfo as? TouchState, isActive(state),
              let hint = state.options.first else { return }
        state.held = true
        state.holdTimer = nil
        if state.options.count > 1 {
            popupOwner = state
            state.key.isPressed = true
            bringSubviewToFront(popup)
            popup.showOptions(state.options, keyFrame: state.key.frame, limits: popupLimits,
                              theme: theme, fontScale: fontScale)
            onCursorStep?()
        } else if popupOwner === state {
            popup.setText(hint)
        } else {
            // Popups are off: still show the symbol so you know it switched.
            state.key.isPressed = false
            showPopup(for: state, text: hint)
        }
    }

    @objc private func backspaceRepeatStart(_ timer: Timer) {
        guard let state = timer.userInfo as? TouchState, isActive(state) else { return }
        state.repeatTimer = Timer.scheduledTimer(timeInterval: 0.09,
                                                 target: self,
                                                 selector: #selector(backspaceRepeat(_:)),
                                                 userInfo: state,
                                                 repeats: true)
        backspaceRepeat(state.repeatTimer!)
    }

    @objc private func backspaceRepeat(_ timer: Timer) {
        guard let state = timer.userInfo as? TouchState, isActive(state) else {
            timer.invalidate()
            return
        }
        state.repeatCount += 1
        // After ~1.5 s of holding, delete whole words (slower pace).
        let wordMode = state.repeatCount > 16
        if wordMode && state.repeatCount % 3 != 0 { return }
        delegate?.keyboardView(self, backspaceWholeWord: wordMode)
    }

    private func showPopup(for state: TouchState, text: String) {
        popupOwner = state
        bringSubviewToFront(popup)
        popup.show(text: text,
                   keyFrame: state.key.frame,
                   limits: popupLimits,
                   theme: theme,
                   fontScale: fontScale)
    }

    /// The suggestion bar above is part of the keyboard, so popups may cover it.
    private var popupLimits: CGRect {
        CGRect(x: bounds.minX, y: bounds.minY - Metrics.barHeight,
               width: bounds.width, height: bounds.height + Metrics.barHeight)
    }
}
