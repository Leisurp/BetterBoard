import UIKit

protocol KeyboardViewDelegate: AnyObject {
    func keyboardView(_ view: KeyboardView, didType text: String)
    func keyboardViewDidTapSpace(_ view: KeyboardView)
    func keyboardViewDidTapReturn(_ view: KeyboardView)
    func keyboardView(_ view: KeyboardView, backspaceWholeWord: Bool)
    func keyboardViewShiftDown(_ view: KeyboardView)
    func keyboardViewShiftUp(_ view: KeyboardView)
    func keyboardViewDidTapNextKeyboard(_ view: KeyboardView)
    func keyboardViewDidChangeMode(_ view: KeyboardView)
}

/// Draws every key and handles all touches itself (multi-touch, hold-for-symbol,
/// backspace repeat). Popups draw above the view's top edge, over the suggestion bar.
final class KeyboardView: UIView {
    weak var delegate: KeyboardViewDelegate?

    var mode: KeyboardMode = .letters {
        didSet { if oldValue != mode { rebuild(); delegate?.keyboardViewDidChangeMode(self) } }
    }
    var shiftState: ShiftState = .off {
        didSet { if oldValue != shiftState { refreshKeys() } }
    }
    var returnKeyType: UIReturnKeyType = .default {
        didSet { if oldValue != returnKeyType { refreshKeys() } }
    }
    var theme = Theme(isDark: false) {
        didSet { if oldValue.isDark != theme.isDark { refreshKeys() } }
    }

    private let settings = KeyboardSettings.shared
    private var rows: [[KeyView]] = []
    private var pinEndsRows: [Bool] = []
    private var hitFrames: [ObjectIdentifier: CGRect] = [:]
    private let popup = KeyPopupView()

    // MARK: Touch tracking

    private final class TouchState {
        var key: KeyView
        var held = false
        var holdTimer: Timer?
        var repeatTimer: Timer?
        var repeatCount = 0

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
        let count = CGFloat(Layout.rows(mode: mode, numberRow: settings.numberRow).count)
        return Metrics.topInset + count * keyHeight + (count - 1) * rowGap + Metrics.bottomInset
    }

    /// Re-creates all keys (mode or settings changed).
    func rebuild() {
        cancelAllTouches()
        rows.flatMap { $0 }.forEach { $0.removeFromSuperview() }
        let layout = Layout.rows(mode: mode, numberRow: settings.numberRow && mode == .letters)
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
        for touch in touches {
            guard let key = key(at: touch.location(in: self)) else { continue }
            // Fast typing: a new finger finishes any key that's still down.
            commitPendingTouches()
            let state = TouchState(key: key)
            touchStates[touch] = state
            keyDown(state)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let state = touchStates[touch],
                  state.key.def.action == .character,
                  !state.held,
                  let newKey = key(at: touch.location(in: self)),
                  newKey !== state.key,
                  newKey.def.action == .character else { continue }
            // Slide to a neighbouring key before the hold kicks in.
            state.stopTimers()
            state.key.isPressed = false
            state.key = newKey
            keyDown(state)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let state = touchStates.removeValue(forKey: touch) else { continue }
            keyUp(state, commit: true)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let state = touchStates.removeValue(forKey: touch) else { continue }
            keyUp(state, commit: false)
        }
    }

    private func commitPendingTouches() {
        for (touch, state) in touchStates {
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
            if settings.holdForSymbols, key.def.hint != nil {
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
        guard commit else { return }

        switch key.def.action {
        case .character:
            let text = state.held ? (key.def.hint ?? key.output) : key.output
            delegate?.keyboardView(self, didType: text)
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

    @objc private func holdTimerFired(_ timer: Timer) {
        guard let state = timer.userInfo as? TouchState, isActive(state),
              let hint = state.key.def.hint else { return }
        state.held = true
        state.holdTimer = nil
        if popupOwner === state {
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
                   limits: bounds,
                   theme: theme,
                   fontScale: fontScale)
    }
}
