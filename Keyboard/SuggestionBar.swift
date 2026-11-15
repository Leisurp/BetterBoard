import UIKit

struct Suggestion: Equatable {
    /// Text that gets inserted.
    let text: String
    /// The word exactly as typed (shown in quotes; tapping keeps it).
    var isTypedWord = false
    /// Will be applied automatically when space is pressed.
    var isAutocorrect = false
    /// An emoji for the word (replaces the word being typed, like Gboard).
    var isEmoji = false
    /// A next-word prediction (shown before you start typing a word).
    var isPrediction = false
}

protocol SuggestionBarDelegate: AnyObject {
    func suggestionBar(_ bar: SuggestionBar, didPick suggestion: Suggestion)
    func suggestionBarDidTapSettings(_ bar: SuggestionBar)
    func suggestionBarDidTapGif(_ bar: SuggestionBar)
    func suggestionBarDidTapClipboard(_ bar: SuggestionBar)
}

/// The strip above the keys: ⚙ settings button + three suggestion slots.
final class SuggestionBar: UIView {
    weak var delegate: SuggestionBarDelegate?
    /// Taps on empty parts of the bar are passed to this view (the keys), so a
    /// fast tap that lands just above the top row still types a letter.
    weak var touchForwardTarget: UIView?

    var theme = Theme(isDark: false) {
        didSet { applyTheme() }
    }

    private let gearButton = UIButton(type: .system)
    private let gifButton = UIButton(type: .system)
    private let clipboardButton = UIButton(type: .system)
    private var slots: [UIButton] = []
    private var separators: [UIView] = []
    private var suggestions: [Suggestion?] = []
    /// Width of each toolbar button on the left (⚙, GIF, clipboard).
    private let toolWidth: CGFloat = 34
    private var toolsWidth: CGFloat { toolWidth * 3 + 4 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Touch.touchableBackground

        let iconConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        gearButton.setImage(UIImage(systemName: "gearshape", withConfiguration: iconConfig), for: .normal)
        gearButton.addTarget(self, action: #selector(gearTapped), for: .touchUpInside)
        addSubview(gearButton)

        gifButton.setTitle("GIF", for: .normal)
        gifButton.titleLabel?.font = .systemFont(ofSize: 11, weight: .heavy)
        gifButton.layer.borderWidth = 1.5
        gifButton.layer.cornerRadius = 4
        gifButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.suggestionBarDidTapGif(self)
        }, for: .touchUpInside)
        addSubview(gifButton)

        clipboardButton.setImage(UIImage(systemName: "list.clipboard", withConfiguration: iconConfig), for: .normal)
        clipboardButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.suggestionBarDidTapClipboard(self)
        }, for: .touchUpInside)
        addSubview(clipboardButton)

        for index in 0..<3 {
            let button = UIButton(type: .system)
            button.tag = index
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
            button.addTarget(self, action: #selector(slotTapped(_:)), for: .touchUpInside)
            slots.append(button)
            addSubview(button)
        }
        for _ in 0..<2 {
            let line = UIView()
            separators.append(line)
            addSubview(line)
        }
        applyTheme()
        setSuggestions([])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Three fixed slots: left, middle, right (Gboard style). The middle one is the
    /// main suggestion; it's bold when it will be applied by pressing space.
    func setSuggestions(_ list: [Suggestion?]) {
        var padded = Array(list.prefix(3))
        while padded.count < 3 { padded.append(nil) }
        guard padded != suggestions else { return }
        suggestions = padded
        for (index, button) in slots.enumerated() {
            if let s = padded[index] {
                button.setTitle(s.text, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: s.isEmoji ? 22 : 17,
                                                      weight: s.isAutocorrect ? .semibold : .regular)
                button.isHidden = false
            } else {
                button.setTitle(nil, for: .normal)
                button.isHidden = true
            }
        }
        for (index, line) in separators.enumerated() {
            line.isHidden = padded[index] == nil || padded[index + 1] == nil
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        gearButton.frame = CGRect(x: 4, y: 0, width: toolWidth, height: h)
        gifButton.frame = CGRect(x: 4 + toolWidth + 4, y: (h - 18) / 2, width: toolWidth - 8, height: 18)
        clipboardButton.frame = CGRect(x: 4 + toolWidth * 2, y: 0, width: toolWidth, height: h)
        let start = toolsWidth + 2
        let slotWidth = (bounds.width - start - 6) / 3
        for (index, button) in slots.enumerated() {
            button.frame = CGRect(x: start + CGFloat(index) * slotWidth, y: 0, width: slotWidth, height: h)
        }
        let lineHeight = h * 0.5
        for (index, line) in separators.enumerated() {
            let x = start + CGFloat(index + 1) * slotWidth
            line.frame = CGRect(x: x - 0.5, y: (bounds.height - lineHeight) / 2, width: 1, height: lineHeight)
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit === self, let target = touchForwardTarget, !target.isHidden {
            return target
        }
        return hit
    }

    private func applyTheme() {
        gearButton.tintColor = theme.hintColor
        clipboardButton.tintColor = theme.hintColor
        gifButton.setTitleColor(theme.hintColor, for: .normal)
        gifButton.layer.borderColor = theme.hintColor.cgColor
        for button in slots {
            button.setTitleColor(theme.labelColor, for: .normal)
            button.tintColor = theme.labelColor
        }
        for line in separators {
            line.backgroundColor = theme.separatorColor
        }
    }

    @objc private func gearTapped() {
        delegate?.suggestionBarDidTapSettings(self)
    }

    @objc private func slotTapped(_ sender: UIButton) {
        guard sender.tag < suggestions.count, let suggestion = suggestions[sender.tag] else { return }
        delegate?.suggestionBar(self, didPick: suggestion)
    }
}
