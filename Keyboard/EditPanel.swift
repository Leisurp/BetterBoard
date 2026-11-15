import UIKit

enum EditAction {
    case left, right, wordLeft, wordRight, lineStart, lineEnd
    case copy, cut, paste, delete
}

protocol EditPanelDelegate: AnyObject {
    func editPanelClose(_ panel: EditPanel)
    func editPanel(_ panel: EditPanel, perform action: EditAction)
}

/// Gboard-style text editing panel: cursor keys plus copy, cut and paste.
/// (iOS doesn't let keyboards select text, so Copy and Cut work on text
/// selected in the app.)
final class EditPanel: UIView {
    weak var delegate: EditPanelDelegate?
    private let theme: Theme
    private let tipLabel = UILabel()
    private var repeatTimer: Timer?
    private var repeatAction: EditAction?
    private var tipResetWork: DispatchWorkItem?

    private let defaultTip = "Select text in the app first, then Copy or Cut."

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        overrideUserInterfaceStyle = theme.isDark ? .dark : .light
        backgroundColor = Touch.touchableBackground
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func removeFromSuperview() {
        stopRepeat()
        super.removeFromSuperview()
    }

    /// Briefly shows a message (e.g. "Copied") in place of the tip.
    func flash(_ message: String) {
        tipLabel.text = message
        tipResetWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.tipLabel.text = self.defaultTip
        }
        tipResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    private func buildUI() {
        let back = UIButton(type: .system)
        back.setTitle("ABC", for: .normal)
        back.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        back.tintColor = theme.accentColor
        back.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.editPanelClose(self)
        }, for: .touchUpInside)

        let title = UILabel()
        title.text = "Edit text"
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = theme.labelColor

        tipLabel.text = defaultTip
        tipLabel.font = .systemFont(ofSize: 13)
        tipLabel.textColor = theme.hintColor
        tipLabel.textAlignment = .center
        tipLabel.adjustsFontSizeToFitWidth = true
        tipLabel.minimumScaleFactor = 0.8

        let rows = UIStackView(arrangedSubviews: [
            row([key(icon: "arrow.left.to.line", text: "Line start", action: .lineStart),
                 key(icon: "arrow.right.to.line", text: "Line end", action: .lineEnd)]),
            row([key(icon: "chevron.left.2", text: nil, action: .wordLeft, repeats: true),
                 key(icon: "chevron.left", text: nil, action: .left, repeats: true),
                 key(icon: "chevron.right", text: nil, action: .right, repeats: true),
                 key(icon: "chevron.right.2", text: nil, action: .wordRight, repeats: true)]),
            row([key(icon: "doc.on.doc", text: "Copy", action: .copy),
                 key(icon: "scissors", text: "Cut", action: .cut),
                 key(icon: "doc.on.clipboard", text: "Paste", action: .paste),
                 key(icon: "delete.left", text: nil, action: .delete, repeats: true)]),
        ])
        rows.axis = .vertical
        rows.spacing = 8
        rows.distribution = .fillEqually

        for view in [back, title, tipLabel, rows] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            back.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            back.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            back.widthAnchor.constraint(equalToConstant: 48),
            back.heightAnchor.constraint(equalToConstant: 32),
            title.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            title.centerXAnchor.constraint(equalTo: centerXAnchor),

            tipLabel.topAnchor.constraint(equalTo: back.bottomAnchor, constant: 2),
            tipLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            tipLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            rows.topAnchor.constraint(equalTo: tipLabel.bottomAnchor, constant: 8),
            rows.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.sideMargin),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.sideMargin),
            rows.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.bottomInset - 2),
        ])
    }

    private func row(_ keys: [UIView]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: keys)
        stack.axis = .horizontal
        stack.spacing = Metrics.keyGap
        stack.distribution = .fillEqually
        return stack
    }

    private func key(icon: String, text: String?, action: EditAction, repeats: Bool = false) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: icon,
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular))
        config.imagePadding = 6
        if let text {
            var title = AttributedString(text)
            title.font = .systemFont(ofSize: 15)
            config.attributedTitle = title
        }
        config.baseForegroundColor = theme.labelColor
        config.background.backgroundColor = theme.keyBorders ? theme.keyColor : theme.keyPressedColor.withAlphaComponent(0.35)
        config.background.cornerRadius = Metrics.cornerRadius
        let button = UIButton(configuration: config)
        button.layer.shadowColor = theme.keyShadowColor.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        button.layer.shadowRadius = 0
        button.layer.shadowOpacity = 1
        let pressed = theme.keyPressedColor
        let normal = config.background.backgroundColor
        button.configurationUpdateHandler = { button in
            button.configuration?.background.backgroundColor = button.isHighlighted ? pressed : normal
        }

        if repeats {
            button.addAction(UIAction { [weak self] _ in self?.startRepeat(action) }, for: .touchDown)
            for event: UIControl.Event in [.touchUpInside, .touchUpOutside, .touchCancel] {
                button.addAction(UIAction { [weak self] _ in self?.stopRepeat() }, for: event)
            }
        } else {
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.delegate?.editPanel(self, perform: action)
            }, for: .touchUpInside)
        }
        return button
    }

    // Hold an arrow or delete to repeat, like a real key.

    private func startRepeat(_ action: EditAction) {
        stopRepeat()
        repeatAction = action
        delegate?.editPanel(self, perform: action)
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                guard let self, let action = self.repeatAction else { return }
                self.delegate?.editPanel(self, perform: action)
            }
        }
    }

    private func stopRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        repeatAction = nil
    }
}
