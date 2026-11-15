import UIKit

protocol EmojiPanelDelegate: AnyObject {
    func emojiPanelClose(_ panel: EmojiPanel)
    func emojiPanelBeginSearch(_ panel: EmojiPanel)
    func emojiPanel(_ panel: EmojiPanel, didPick emoji: String)
    func emojiPanelBackspace(_ panel: EmojiPanel)
    func emojiPanelNextKeyboard(_ panel: EmojiPanel)
}

/// BetterBoard's own emoji keyboard: categories, recently used, search and
/// skin tones (hold an emoji to pick one; it's remembered).
final class EmojiPanel: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    weak var delegate: EmojiPanelDelegate?
    private let store = EmojiStore.shared
    private let theme: Theme
    private let collection: UICollectionView
    private var categoryButtons: [UIButton] = []
    private var toneBar: UIView?
    private var repeatTimer: Timer?
    /// Section 0 is recently used; the rest are the Unicode groups.
    private var recents: [String] = []

    init(theme: Theme) {
        self.theme = theme
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 44, height: 42)
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 12)
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)
        overrideUserInterfaceStyle = theme.isDark ? .dark : .light
        backgroundColor = Touch.touchableBackground
        recents = store.recents
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func removeFromSuperview() {
        repeatTimer?.invalidate()
        super.removeFromSuperview()
    }

    private func buildUI() {
        // Search pill.
        let search = UIButton(type: .system)
        var searchConfig = UIButton.Configuration.filled()
        searchConfig.baseBackgroundColor = theme.labelColor.withAlphaComponent(0.1)
        searchConfig.baseForegroundColor = theme.hintColor
        searchConfig.cornerStyle = .capsule
        searchConfig.image = UIImage(systemName: "magnifyingglass",
                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 13))
        searchConfig.imagePadding = 6
        var searchTitle = AttributedString("Search emoji")
        searchTitle.font = .systemFont(ofSize: 15)
        searchConfig.attributedTitle = searchTitle
        search.configuration = searchConfig
        search.contentHorizontalAlignment = .leading
        search.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.emojiPanelBeginSearch(self)
        }, for: .touchUpInside)

        collection.backgroundColor = .clear
        collection.showsHorizontalScrollIndicator = false
        collection.dataSource = self
        collection.delegate = self
        collection.register(EmojiCell.self, forCellWithReuseIdentifier: "emoji")
        collection.register(EmojiHeader.self,
                            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                            withReuseIdentifier: "header")
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.35
        collection.addGestureRecognizer(hold)

        // Bottom bar: ABC, 🌐, categories, delete.
        let bar = UIStackView()
        bar.axis = .horizontal
        bar.distribution = .fillEqually
        let abc = UIButton(type: .system)
        abc.setTitle("ABC", for: .normal)
        abc.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        abc.tintColor = theme.labelColor
        abc.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.emojiPanelClose(self)
        }, for: .touchUpInside)
        bar.addArrangedSubview(abc)

        let sections = ["clock"] + store.groups.map(\.icon)
        for (index, icon) in sections.enumerated() {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: icon,
                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 15)), for: .normal)
            button.tintColor = theme.hintColor
            button.tag = index
            button.addAction(UIAction { [weak self] _ in self?.scrollTo(section: index) }, for: .touchUpInside)
            categoryButtons.append(button)
            bar.addArrangedSubview(button)
        }

        let delete = UIButton(type: .system)
        delete.setImage(UIImage(systemName: "delete.left",
                                withConfiguration: UIImage.SymbolConfiguration(pointSize: 17)), for: .normal)
        delete.tintColor = theme.labelColor
        delete.addAction(UIAction { [weak self] _ in self?.startDeleteRepeat() }, for: .touchDown)
        for event: UIControl.Event in [.touchUpInside, .touchUpOutside, .touchCancel] {
            delete.addAction(UIAction { [weak self] _ in self?.stopDeleteRepeat() }, for: event)
        }
        bar.addArrangedSubview(delete)

        for view in [search, collection, bar] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            search.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            search.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            search.heightAnchor.constraint(equalToConstant: 30),

            collection.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 2),
            collection.leadingAnchor.constraint(equalTo: leadingAnchor),
            collection.trailingAnchor.constraint(equalTo: trailingAnchor),
            collection.bottomAnchor.constraint(equalTo: bar.topAnchor),

            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            bar.heightAnchor.constraint(equalToConstant: 38),
        ])
        highlightCategory(recents.isEmpty ? 1 : 0)

        // The 🌐 key, so you can still reach other keyboards (long-press the ABC key).
        let globe = UILongPressGestureRecognizer(target: self, action: #selector(abcHeld(_:)))
        abc.addGestureRecognizer(globe)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Open on Smileys if nothing's been used yet.
        if window != nil, recents.isEmpty, store.groups.count > 0 {
            DispatchQueue.main.async { self.scrollTo(section: 1, animated: false) }
        }
    }

    @objc private func abcHeld(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        delegate?.emojiPanelNextKeyboard(self)
    }

    // MARK: Data

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        1 + store.groups.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        section == 0 ? recents.count : store.groups[section - 1].entries.count
    }

    private func emoji(at indexPath: IndexPath) -> (shown: String, entry: EmojiEntry?) {
        if indexPath.section == 0 {
            let shown = recents[indexPath.item]
            return (shown, nil)
        }
        let entry = store.groups[indexPath.section - 1].entries[indexPath.item]
        return (store.display(entry.emoji), entry)
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "emoji", for: indexPath) as! EmojiCell
        cell.label.text = emoji(at: indexPath).shown
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "header", for: indexPath)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        hideToneBar()
        pick(emoji(at: indexPath).shown)
    }

    private func pick(_ emoji: String) {
        store.noteUsed(emoji)
        delegate?.emojiPanel(self, didPick: emoji)
    }

    // MARK: Categories

    private func scrollTo(section: Int, animated: Bool = true) {
        hideToneBar()
        guard section < collection.numberOfSections else { return }
        if collection.numberOfItems(inSection: section) == 0 { return }
        collection.scrollToItem(at: IndexPath(item: 0, section: section), at: .left, animated: animated)
        highlightCategory(section)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        hideToneBar()
        let probe = CGPoint(x: scrollView.contentOffset.x + 30, y: scrollView.bounds.midY)
        if let indexPath = collection.indexPathForItem(at: probe) {
            highlightCategory(indexPath.section)
        }
    }

    private func highlightCategory(_ section: Int) {
        for button in categoryButtons {
            button.tintColor = button.tag == section ? theme.accentColor : theme.hintColor
        }
    }

    // MARK: Skin tones

    @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        let point = recognizer.location(in: collection)
        guard let indexPath = collection.indexPathForItem(at: point),
              let entry = emoji(at: indexPath).entry, entry.tones.count == 5,
              let cell = collection.cellForItem(at: indexPath) else { return }
        showToneBar(for: entry, above: cell.convert(cell.bounds, to: self))
    }

    private func showToneBar(for entry: EmojiEntry, above cellFrame: CGRect) {
        hideToneBar()
        let options = [entry.emoji] + entry.tones
        let size: CGFloat = 42
        let width = size * CGFloat(options.count) + 8
        var x = cellFrame.midX - width / 2
        x = min(max(x, 4), bounds.width - width - 4)
        let y = max(cellFrame.minY - size - 6, 2)
        let bar = UIView(frame: CGRect(x: x, y: y, width: width, height: size + 6))
        bar.backgroundColor = theme.popupColor
        bar.layer.cornerRadius = 10
        bar.layer.shadowColor = UIColor.black.cgColor
        bar.layer.shadowOpacity = 0.3
        bar.layer.shadowRadius = 4
        bar.layer.shadowOffset = CGSize(width: 0, height: 1)
        for (index, option) in options.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(option, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 28)
            button.frame = CGRect(x: 4 + CGFloat(index) * size, y: 3, width: size, height: size)
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.store.setTone(option, for: entry.emoji)
                self.hideToneBar()
                self.pick(option)
                self.collection.reloadData()
            }, for: .touchUpInside)
            bar.addSubview(button)
        }
        addSubview(bar)
        toneBar = bar
    }

    private func hideToneBar() {
        toneBar?.removeFromSuperview()
        toneBar = nil
    }

    // MARK: Delete (hold to repeat)

    private func startDeleteRepeat() {
        stopDeleteRepeat()
        delegate?.emojiPanelBackspace(self)
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.delegate?.emojiPanelBackspace(self)
            }
        }
    }

    private func stopDeleteRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}

private final class EmojiCell: UICollectionViewCell {
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 30)
        label.textAlignment = .center
        label.frame = contentView.bounds
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet {
            contentView.backgroundColor = isHighlighted ? UIColor.label.withAlphaComponent(0.12) : .clear
            contentView.layer.cornerRadius = 8
        }
    }
}

private final class EmojiHeader: UICollectionReusableView {}
