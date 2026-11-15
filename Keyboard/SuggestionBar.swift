import UIKit

struct Suggestion: Equatable {
    /// Text that gets inserted.
    let text: String
    /// The word exactly as typed (shown in quotes; tapping keeps it).
    var isTypedWord = false
    /// Will be applied automatically when space is pressed.
    var isAutocorrect = false
}

protocol SuggestionBarDelegate: AnyObject {
    func suggestionBar(_ bar: SuggestionBar, didPick suggestion: Suggestion)
    func suggestionBarDidTapSettings(_ bar: SuggestionBar)
}

/// The strip above the keys: ⚙ settings button + three suggestion slots.
final class SuggestionBar: UIView {
    weak var delegate: SuggestionBarDelegate?

    var theme = Theme(isDark: false) {
        didSet { applyTheme() }
    }

    private let gearButton = UIButton(type: .system)
    private var slots: [UIButton] = []
    private var separators: [UIView] = []
    private var suggestions: [Suggestion] = []
    private let gearWidth: CGFloat = 44

    override init(frame: CGRect) {
        super.init(frame: frame)

        let gearConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        gearButton.setImage(UIImage(systemName: "gearshape", withConfiguration: gearConfig), for: .normal)
        gearButton.addTarget(self, action: #selector(gearTapped), for: .touchUpInside)
        addSubview(gearButton)

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

    func setSuggestions(_ list: [Suggestion]) {
        suggestions = Array(list.prefix(3))
        for (index, button) in slots.enumerated() {
            if index < suggestions.count {
                let s = suggestions[index]
                let title = s.isTypedWord ? "\u{201C}\(s.text)\u{201D}" : s.text
                button.setTitle(title, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 17, weight: s.isAutocorrect ? .semibold : .regular)
                button.isHidden = false
            } else {
                button.setTitle(nil, for: .normal)
                button.isHidden = true
            }
        }
        for (index, line) in separators.enumerated() {
            line.isHidden = !(index + 1 < suggestions.count)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gearButton.frame = CGRect(x: 0, y: 0, width: gearWidth, height: bounds.height)
        let slotWidth = (bounds.width - gearWidth * 2) / 3
        for (index, button) in slots.enumerated() {
            button.frame = CGRect(x: gearWidth + CGFloat(index) * slotWidth, y: 0, width: slotWidth, height: bounds.height)
        }
        let lineHeight = bounds.height * 0.5
        for (index, line) in separators.enumerated() {
            let x = gearWidth + CGFloat(index + 1) * slotWidth
            line.frame = CGRect(x: x - 0.5, y: (bounds.height - lineHeight) / 2, width: 1, height: lineHeight)
        }
    }

    private func applyTheme() {
        gearButton.tintColor = theme.hintColor
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
        guard sender.tag < suggestions.count else { return }
        delegate?.suggestionBar(self, didPick: suggestions[sender.tag])
    }
}
