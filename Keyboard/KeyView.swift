import UIKit

/// One key cap. Purely visual — KeyboardView handles all touches.
final class KeyView: UIView {
    let def: KeyDef
    /// What a tap types (the letter, cased for the current shift state).
    private(set) var output: String = ""

    var isPressed = false {
        didSet { if oldValue != isPressed { updateColors() } }
    }

    private let label = UILabel()
    private let hintLabel = UILabel()
    private let iconView = UIImageView()
    private var theme = Theme(isDark: false)
    private var isAccent = false
    private var isShiftActive = false
    private var iconConfig = UIImage.SymbolConfiguration(pointSize: Metrics.iconPointSize, weight: .regular)
    private var shiftIconName = ""

    init(def: KeyDef) {
        self.def = def
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.cornerRadius = Metrics.cornerRadius
        layer.cornerCurve = .continuous
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        layer.shadowOpacity = 1

        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        hintLabel.textAlignment = .right
        iconView.contentMode = .center

        addSubview(label)
        addSubview(hintLabel)
        addSubview(iconView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(theme: Theme,
                   shift: ShiftState,
                   showHint: Bool,
                   returnKeyType: UIReturnKeyType,
                   fontScale: CGFloat) {
        self.theme = theme
        label.text = nil
        hintLabel.text = nil
        iconView.image = nil
        isAccent = false
        isShiftActive = false

        iconConfig = UIImage.SymbolConfiguration(pointSize: Metrics.iconPointSize * fontScale, weight: .regular)

        switch def.action {
        case .character:
            output = (def.isLetter && shift != .off) ? def.text.uppercased() : def.text
            label.text = output
            label.font = .systemFont(ofSize: Metrics.letterFontSize * fontScale)
            if showHint, let hint = def.hint {
                hintLabel.text = hint
                hintLabel.font = .systemFont(ofSize: Metrics.hintFontSize * fontScale)
            }

        case .shift:
            applyShiftIcon(shift)

        case .backspace:
            iconView.image = UIImage(systemName: "delete.left", withConfiguration: iconConfig)

        case .space:
            break

        case .returnKey:
            let style = Self.returnStyle(returnKeyType)
            isAccent = style.accent
            iconView.image = UIImage(systemName: style.icon, withConfiguration: iconConfig)

        case .mode:
            label.text = def.text
            label.font = .systemFont(ofSize: Metrics.labelFontSize * fontScale)

        case .nextKeyboard:
            let big = UIImage.SymbolConfiguration(pointSize: Metrics.iconPointSize * 1.15 * fontScale, weight: .regular)
            iconView.image = UIImage(systemName: "face.smiling.inverse", withConfiguration: big)
        }

        updateColors()
        setNeedsLayout()
    }

    /// Fast path for shift changes: only touches letter labels and the shift icon.
    func updateShift(_ shift: ShiftState) {
        switch def.action {
        case .character:
            guard def.isLetter else { return }
            let newOutput = shift != .off ? def.text.uppercased() : def.text
            if newOutput != output {
                output = newOutput
                label.text = newOutput
            }
        case .shift:
            applyShiftIcon(shift)
            updateColors()
        default:
            break
        }
    }

    private func applyShiftIcon(_ shift: ShiftState) {
        let name: String
        switch shift {
        case .off: name = "shift"
        case .once: name = "shift.fill"
        case .locked: name = "capslock.fill"
        }
        isShiftActive = shift != .off
        if name != shiftIconName || iconView.image == nil {
            shiftIconName = name
            iconView.image = UIImage(systemName: name, withConfiguration: iconConfig)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 2, dy: 0).offsetBy(dx: 0, dy: -1)
        iconView.frame = bounds
        hintLabel.frame = CGRect(x: 0, y: 2, width: bounds.width - 4, height: 14)
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: Metrics.cornerRadius).cgPath
    }

    private func updateColors() {
        let base: UIColor
        if isAccent {
            base = theme.accentColor
        } else if isShiftActive {
            base = theme.shiftActiveColor
        } else {
            base = theme.keyColor
        }

        if isPressed {
            backgroundColor = isAccent ? theme.accentColor.withAlphaComponent(0.7) : theme.keyPressedColor
        } else {
            backgroundColor = base
        }

        label.textColor = theme.labelColor
        hintLabel.textColor = theme.hintColor
        if isAccent {
            iconView.tintColor = .white
        } else if isShiftActive && !isPressed {
            iconView.tintColor = theme.shiftActiveIconColor
        } else {
            iconView.tintColor = theme.labelColor
        }
        layer.shadowColor = theme.keyShadowColor.cgColor
    }

    private static func returnStyle(_ type: UIReturnKeyType) -> (icon: String, accent: Bool) {
        switch type {
        case .default:
            return ("return.left", false)
        case .go, .join, .route, .continue, .next:
            return ("arrow.right", true)
        case .search, .google, .yahoo:
            return ("magnifyingglass", true)
        case .send:
            return ("arrow.up", true)
        case .done:
            return ("checkmark", true)
        case .emergencyCall:
            return ("phone.fill", true)
        @unknown default:
            return ("return.left", false)
        }
    }
}
