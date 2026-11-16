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
    /// Shown instead of `text` (e.g. "📋 Paste: …").
    var label: String?
    /// How many characters before the cursor it replaces (nil = the current word).
    var replaceCount: Int?
    /// Whether a space follows it.
    var addsSpace = true
    /// Just-copied text offered for pasting.
    var isPaste = false
}

protocol SuggestionBarDelegate: AnyObject {
    func suggestionBar(_ bar: SuggestionBar, didPick suggestion: Suggestion)
    func suggestionBarDidTapSettings(_ bar: SuggestionBar)
    func suggestionBarDidTapGif(_ bar: SuggestionBar)
    func suggestionBarDidTapClipboard(_ bar: SuggestionBar)
    func suggestionBarDidTapEdit(_ bar: SuggestionBar)
    func suggestionBarDidTapEmoji(_ bar: SuggestionBar)
    /// Held a suggestion and chose Remove: stop suggesting it.
    func suggestionBar(_ bar: SuggestionBar, didRemove suggestion: Suggestion)
}

/// The strip above the keys, laid out like Gboard: a round button on the left
/// that opens the toolbar (settings, GIF, clipboard, edit, emoji), then three
/// suggestion slots. Typing closes the toolbar again.
final class SuggestionBar: UIView {
    weak var delegate: SuggestionBarDelegate?
    /// Taps on empty parts of the bar are passed to this view (the keys), so a
    /// fast tap that lands just above the top row still types a letter.
    weak var touchForwardTarget: UIView?

    var theme = Theme(isDark: false) {
        didSet { applyTheme() }
    }

    private let expandButton = UIButton(type: .system)
    private let expandCircle = UIView()
    private let toolsRow = UIStackView()
    private let gearButton = UIButton(type: .system)
    private let gifButton = UIButton(type: .system)
    private let gifBadge = UILabel()
    private let clipboardButton = UIButton(type: .system)
    private let editButton = UIButton(type: .system)
    private let emojiButton = UIButton(type: .system)
    /// The toolbar is showing instead of the suggestions.
    private(set) var isExpanded = false
    /// "Stop suggesting …?" strip shown after holding a suggestion.
    private let removeStrip = UIView()
    private let removeLabel = UILabel()
    private let removeButton = UIButton(type: .system)
    private let cancelRemoveButton = UIButton(type: .system)
    private var removing: Suggestion?
    private var slots: [UIButton] = []
    private var separators: [UIView] = []
    private var suggestions: [Suggestion?] = []
    /// Width of the round toolbar button on the left.
    private let expandWidth: CGFloat = 40

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Touch.touchableBackground

        // Round button on the left (Gboard's "G").
        expandCircle.isUserInteractionEnabled = false
        expandCircle.layer.cornerRadius = 13
        addSubview(expandCircle)
        expandButton.addAction(UIAction { [weak self] _ in self?.setExpanded(!(self?.isExpanded ?? false)) },
                               for: .touchUpInside)
        addSubview(expandButton)

        // The toolbar it opens.
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        func tool(_ button: UIButton, _ icon: String?, action: @escaping (SuggestionBar) -> Void) {
            if let icon {
                button.setImage(UIImage(systemName: icon, withConfiguration: iconConfig), for: .normal)
            }
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.setExpanded(false)
                action(self)
            }, for: .touchUpInside)
            toolsRow.addArrangedSubview(button)
        }
        tool(gearButton, "gearshape") { $0.delegate?.suggestionBarDidTapSettings($0) }
        tool(gifButton, nil) { $0.delegate?.suggestionBarDidTapGif($0) }
        tool(clipboardButton, "list.clipboard") { $0.delegate?.suggestionBarDidTapClipboard($0) }
        tool(editButton, "character.cursor.ibeam") { $0.delegate?.suggestionBarDidTapEdit($0) }
        tool(emojiButton, "face.smiling") { $0.delegate?.suggestionBarDidTapEmoji($0) }
        // "GIF" in a little rounded box, centred in its button.
        gifBadge.text = "GIF"
        gifBadge.font = .systemFont(ofSize: 11, weight: .heavy)
        gifBadge.textAlignment = .center
        gifBadge.layer.borderWidth = 1.5
        gifBadge.layer.cornerRadius = 4
        gifBadge.isUserInteractionEnabled = false
        gifButton.addSubview(gifBadge)
        toolsRow.axis = .horizontal
        toolsRow.distribution = .fillEqually
        toolsRow.isHidden = true
        addSubview(toolsRow)

        for index in 0..<3 {
            let button = UIButton(type: .system)
            button.tag = index
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
            button.addTarget(self, action: #selector(slotTapped(_:)), for: .touchUpInside)
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(slotHeld(_:)))
            hold.minimumPressDuration = 0.5
            button.addGestureRecognizer(hold)
            slots.append(button)
            addSubview(button)
        }
        for _ in 0..<2 {
            let line = UIView()
            separators.append(line)
            addSubview(line)
        }
        buildRemoveStrip()
        applyTheme()
        setSuggestions([])
        updateExpandIcon()
    }

    /// Shows the toolbar in place of the suggestions (or back again).
    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        if expanded { hideRemoveStrip() }
        updateExpandIcon()
        UIView.transition(with: self, duration: 0.15, options: .transitionCrossDissolve) {
            self.toolsRow.isHidden = !expanded
            self.applySlotVisibility()
        }
    }

    private func updateExpandIcon() {
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let name = isExpanded ? "chevron.left" : "square.grid.2x2"
        expandButton.setImage(UIImage(systemName: name, withConfiguration: config), for: .normal)
    }

    private func applySlotVisibility() {
        for (index, button) in slots.enumerated() {
            button.isHidden = isExpanded || index >= suggestions.count || suggestions[index] == nil
        }
        for (index, line) in separators.enumerated() {
            line.isHidden = isExpanded || index + 1 >= suggestions.count
                || suggestions[index] == nil || suggestions[index + 1] == nil
        }
    }

    private func buildRemoveStrip() {
        removeStrip.isHidden = true
        removeLabel.font = .systemFont(ofSize: 15)
        removeLabel.adjustsFontSizeToFitWidth = true
        removeLabel.minimumScaleFactor = 0.7
        removeButton.setTitle("Remove", for: .normal)
        removeButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        removeButton.setTitleColor(.systemRed, for: .normal)
        removeButton.addAction(UIAction { [weak self] _ in
            guard let self, let suggestion = self.removing else { return }
            self.hideRemoveStrip()
            self.delegate?.suggestionBar(self, didRemove: suggestion)
        }, for: .touchUpInside)
        cancelRemoveButton.setTitle("Cancel", for: .normal)
        cancelRemoveButton.titleLabel?.font = .systemFont(ofSize: 15)
        cancelRemoveButton.addAction(UIAction { [weak self] _ in self?.hideRemoveStrip() }, for: .touchUpInside)
        for view in [removeLabel, removeButton, cancelRemoveButton] {
            removeStrip.addSubview(view)
        }
        addSubview(removeStrip)
    }

    private func hideRemoveStrip() {
        removing = nil
        removeStrip.isHidden = true
    }

    @objc private func slotHeld(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let button = recognizer.view as? UIButton,
              button.tag < suggestions.count, let suggestion = suggestions[button.tag] else { return }
        removing = suggestion
        removeLabel.text = "Stop suggesting “\(suggestion.text)”?"
        removeStrip.isHidden = false
        bringSubviewToFront(removeStrip)
        setNeedsLayout()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Three fixed slots: left, middle, right (Gboard style). The middle one is the
    /// main suggestion; it's bold when it will be applied by pressing space.
    func setSuggestions(_ list: [Suggestion?]) {
        var padded = Array(list.prefix(3))
        while padded.count < 3 { padded.append(nil) }
        guard padded != suggestions else { return }
        suggestions = padded
        hideRemoveStrip()
        for (index, button) in slots.enumerated() {
            if let s = padded[index] {
                button.setTitle(s.label ?? s.text, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: s.isEmoji ? 22 : 17,
                                                      weight: s.isAutocorrect ? .semibold : .regular)
            } else {
                button.setTitle(nil, for: .normal)
            }
        }
        applySlotVisibility()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        expandButton.frame = CGRect(x: 4, y: 0, width: expandWidth, height: h)
        expandCircle.frame = CGRect(x: 4 + (expandWidth - 26) / 2, y: (h - 26) / 2, width: 26, height: 26)
        toolsRow.frame = CGRect(x: 4 + expandWidth + 4, y: 0, width: bounds.width - expandWidth - 16, height: h)
        toolsRow.layoutIfNeeded()
        gifBadge.frame = CGRect(x: (gifButton.bounds.width - 30) / 2, y: (gifButton.bounds.height - 18) / 2,
                                width: 30, height: 18)
        removeStrip.frame = bounds
        cancelRemoveButton.frame = CGRect(x: bounds.width - 70, y: 0, width: 64, height: h)
        removeButton.frame = CGRect(x: bounds.width - 140, y: 0, width: 70, height: h)
        removeLabel.frame = CGRect(x: 12, y: 0, width: bounds.width - 156, height: h)
        let start = 4 + expandWidth + 2
        let slotWidth = (bounds.width - start - 8) / 3
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
        for button in [gearButton, clipboardButton, editButton, emojiButton] {
            button.tintColor = theme.labelColor.withAlphaComponent(0.75)
        }
        expandButton.tintColor = theme.labelColor.withAlphaComponent(0.8)
        expandCircle.backgroundColor = theme.labelColor.withAlphaComponent(theme.isDark ? 0.14 : 0.08)
        removeStrip.backgroundColor = theme.background
            ?? (theme.isDark ? UIColor(white: 0.17, alpha: 1) : UIColor(white: 0.82, alpha: 1))
        removeLabel.textColor = theme.labelColor
        cancelRemoveButton.setTitleColor(theme.labelColor, for: .normal)
        gifBadge.textColor = theme.labelColor.withAlphaComponent(0.75)
        gifBadge.layer.borderColor = theme.labelColor.withAlphaComponent(0.75).cgColor
        for button in slots {
            button.setTitleColor(theme.labelColor, for: .normal)
            button.tintColor = theme.labelColor
        }
        for line in separators {
            line.backgroundColor = theme.separatorColor
        }
    }

    @objc private func slotTapped(_ sender: UIButton) {
        guard sender.tag < suggestions.count, let suggestion = suggestions[sender.tag] else { return }
        delegate?.suggestionBar(self, didPick: suggestion)
    }
}
