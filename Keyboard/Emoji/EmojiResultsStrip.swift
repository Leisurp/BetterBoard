import UIKit

/// One row of emoji above the keys while searching (Gboard style).
final class EmojiResultsStrip: UIView {
    var onPick: ((String) -> Void)?
    private let scroll = UIScrollView()
    private let row = UIStackView()
    private let emptyLabel = UILabel()

    init(theme: Theme) {
        super.init(frame: .zero)
        backgroundColor = Touch.touchableBackground
        scroll.showsHorizontalScrollIndicator = false
        row.axis = .horizontal
        row.spacing = 0
        emptyLabel.text = "No emoji found"
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = theme.hintColor
        emptyLabel.isHidden = true

        for view in [scroll, row, emptyLabel] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        addSubview(scroll)
        scroll.addSubview(row)
        addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setEmojis(_ emojis: [String], emptyMessage: String?) {
        row.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for emoji in emojis {
            let button = UIButton(type: .system)
            button.setTitle(emoji, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 28)
            button.widthAnchor.constraint(equalToConstant: 44).isActive = true
            button.addAction(UIAction { [weak self] _ in self?.onPick?(emoji) }, for: .touchUpInside)
            row.addArrangedSubview(button)
        }
        scroll.contentOffset = .zero
        emptyLabel.text = emptyMessage
        emptyLabel.isHidden = !emojis.isEmpty || emptyMessage == nil
    }
}
