import UIKit

protocol GifPanelDelegate: AnyObject {
    func gifPanelClose(_ panel: GifPanel)
    func gifPanelBeginSearch(_ panel: GifPanel)
    func gifPanelOpenSetup(_ panel: GifPanel)
    func gifPanel(_ panel: GifPanel, didSelectCategory query: String?)
    func gifPanel(_ panel: GifPanel, didPick item: GifItem)
}

/// Gboard-style GIF picker shown in place of the keys.
final class GifPanel: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    enum State {
        case needsSetup(String)
        case loading
        case items([GifItem])
        case message(String)
    }

    weak var delegate: GifPanelDelegate?
    let client: GiphyClient

    private let backButton = UIButton(type: .system)
    private let searchButton = UIButton(type: .system)
    private let categoryScroll = UIScrollView()
    private let categoryStack = UIStackView()
    private let collection: UICollectionView
    private let messageLabel = UILabel()
    private let setupButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let toast = UILabel()
    private var items: [GifItem] = []
    private var categoryButtons: [UIButton] = []

    static let categories: [(title: String, query: String?)] = [
        ("Trending", nil), ("LOL", "lol"), ("Love", "love"), ("Yes", "yes"), ("No", "no"),
        ("Happy", "happy"), ("Sad", "sad"), ("Wow", "wow"), ("Thanks", "thank you"),
        ("Hi", "hello"), ("OMG", "omg"), ("Dance", "dance"), ("Party", "party"),
    ]

    init(client: GiphyClient, isDark: Bool, query: String?) {
        self.client = client
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 4
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)
        overrideUserInterfaceStyle = isDark ? .dark : .light
        backgroundColor = Touch.touchableBackground
        buildUI(query: query)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI(query: String?) {
        backButton.setTitle("ABC", for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        backButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.gifPanelClose(self)
        }, for: .touchUpInside)

        var config = UIButton.Configuration.gray()
        config.cornerStyle = .capsule
        config.image = UIImage(systemName: "magnifyingglass")
        config.imagePadding = 6
        config.title = query.map { "\u{201C}\($0)\u{201D}" } ?? "Search GIFs"
        config.baseForegroundColor = .secondaryLabel
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12)
        searchButton.configuration = config
        searchButton.contentHorizontalAlignment = .leading
        searchButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.gifPanelBeginSearch(self)
        }, for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [backButton, searchButton])
        header.spacing = 8
        header.alignment = .center
        backButton.widthAnchor.constraint(equalToConstant: 44).isActive = true

        categoryStack.axis = .horizontal
        categoryStack.spacing = 6
        for (index, category) in Self.categories.enumerated() {
            var c = UIButton.Configuration.plain()
            c.title = category.title
            c.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8)
            c.cornerStyle = .capsule
            let button = UIButton(configuration: c)
            button.tag = index
            button.addAction(UIAction { [weak self] action in
                guard let self, let sender = action.sender as? UIButton else { return }
                self.selectCategory(sender.tag)
                self.delegate?.gifPanel(self, didSelectCategory: Self.categories[sender.tag].query)
            }, for: .touchUpInside)
            categoryButtons.append(button)
            categoryStack.addArrangedSubview(button)
        }
        categoryScroll.showsHorizontalScrollIndicator = false
        categoryScroll.addSubview(categoryStack)
        categoryStack.translatesAutoresizingMaskIntoConstraints = false
        selectCategory(query == nil ? 0 : -1)

        collection.backgroundColor = .clear
        collection.showsHorizontalScrollIndicator = false
        collection.register(GifCell.self, forCellWithReuseIdentifier: GifCell.id)
        collection.dataSource = self
        collection.delegate = self

        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.font = .systemFont(ofSize: 15)
        messageLabel.textColor = .label

        setupButton.setTitle("Set up GIFs in the BetterBoard app \u{203A}", for: .normal)
        setupButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        setupButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.gifPanelOpenSetup(self)
        }, for: .touchUpInside)

        toast.font = .systemFont(ofSize: 14, weight: .semibold)
        toast.textColor = .white
        toast.backgroundColor = UIColor(white: 0.1, alpha: 0.9)
        toast.textAlignment = .center
        toast.layer.cornerRadius = 14
        toast.clipsToBounds = true
        toast.alpha = 0

        for view in [header, categoryScroll, collection, messageLabel, setupButton, spinner, toast] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            header.heightAnchor.constraint(equalToConstant: 34),

            categoryScroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            categoryScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            categoryScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            categoryScroll.heightAnchor.constraint(equalToConstant: 30),
            categoryStack.topAnchor.constraint(equalTo: categoryScroll.contentLayoutGuide.topAnchor),
            categoryStack.bottomAnchor.constraint(equalTo: categoryScroll.contentLayoutGuide.bottomAnchor),
            categoryStack.leadingAnchor.constraint(equalTo: categoryScroll.contentLayoutGuide.leadingAnchor, constant: 6),
            categoryStack.trailingAnchor.constraint(equalTo: categoryScroll.contentLayoutGuide.trailingAnchor, constant: -6),
            categoryStack.heightAnchor.constraint(equalTo: categoryScroll.frameLayoutGuide.heightAnchor),

            collection.topAnchor.constraint(equalTo: categoryScroll.bottomAnchor, constant: 4),
            collection.leadingAnchor.constraint(equalTo: leadingAnchor),
            collection.trailingAnchor.constraint(equalTo: trailingAnchor),
            collection.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),

            messageLabel.centerYAnchor.constraint(equalTo: collection.centerYAnchor, constant: -16),
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            setupButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 10),
            setupButton.centerXAnchor.constraint(equalTo: centerXAnchor),

            spinner.centerXAnchor.constraint(equalTo: collection.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: collection.centerYAnchor),

            toast.centerXAnchor.constraint(equalTo: centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            toast.heightAnchor.constraint(equalToConstant: 30),
            toast.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -24),
        ])
        setState(.loading)
    }

    private func selectCategory(_ index: Int) {
        for (i, button) in categoryButtons.enumerated() {
            var c = button.configuration
            c?.baseForegroundColor = i == index ? .label : .secondaryLabel
            c?.background.backgroundColor = i == index ? UIColor.label.withAlphaComponent(0.12) : .clear
            button.configuration = c
        }
    }

    func setState(_ state: State) {
        spinner.stopAnimating()
        messageLabel.isHidden = true
        setupButton.isHidden = true
        collection.isHidden = true
        switch state {
        case .needsSetup(let text):
            messageLabel.text = text
            messageLabel.isHidden = false
            setupButton.isHidden = false
            categoryScroll.isHidden = true
            searchButton.isEnabled = false
        case .loading:
            spinner.startAnimating()
        case .items(let list):
            items = list
            collection.isHidden = false
            collection.reloadData()
            collection.setContentOffset(.zero, animated: false)
            if list.isEmpty {
                messageLabel.text = "No GIFs found."
                messageLabel.isHidden = false
            }
        case .message(let text):
            messageLabel.text = text
            messageLabel.isHidden = false
        }
    }

    func showToast(_ text: String) {
        toast.text = "   \(text)   "
        UIView.animate(withDuration: 0.2) { self.toast.alpha = 1 }
        UIView.animate(withDuration: 0.3, delay: 2.5, options: []) { self.toast.alpha = 0 }
    }

    // MARK: Grid

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: GifCell.id, for: indexPath)
        guard let gifCell = cell as? GifCell else { return cell }
        let item = items[indexPath.item]
        gifCell.load(item.previewURL, client: client)
        return gifCell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let rowHeight = max((collectionView.bounds.height - 4) / 2, 40)
        let ratio = min(max(items[indexPath.item].aspectRatio, 0.6), 2.2)
        return CGSize(width: rowHeight * ratio, height: rowHeight)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        delegate?.gifPanel(self, didPick: items[indexPath.item])
    }
}

private final class GifCell: UICollectionViewCell {
    static let id = "GifCell"
    private let imageView = UIImageView()
    private var currentURL: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 6
        imageView.backgroundColor = UIColor.label.withAlphaComponent(0.08)
        contentView.addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = contentView.bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        currentURL = nil
    }

    func load(_ url: URL, client: GiphyClient) {
        currentURL = url
        client.preview(for: url, maxPixel: 200) { [weak self] image in
            guard let self, self.currentURL == url else { return }
            self.imageView.image = image
        }
    }
}

/// Search box shown above the keys while typing a GIF search.
final class GifSearchField: UIView {
    var onCancel: (() -> Void)?
    private let label = UILabel()
    private let cancel = UIButton(type: .system)
    private let placeholder: String

    init(isDark: Bool, placeholder: String = "Search GIFs") {
        self.placeholder = placeholder
        super.init(frame: .zero)
        overrideUserInterfaceStyle = isDark ? .dark : .light
        backgroundColor = Touch.touchableBackground

        let pill = UIView()
        pill.backgroundColor = UIColor.label.withAlphaComponent(0.1)
        pill.layer.cornerRadius = 13
        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        icon.tintColor = .secondaryLabel
        label.font = .systemFont(ofSize: 16)
        label.textColor = .label
        cancel.setTitle("Cancel", for: .normal)
        cancel.addAction(UIAction { [weak self] _ in self?.onCancel?() }, for: .touchUpInside)

        for view in [pill, icon, label, cancel] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            pill.trailingAnchor.constraint(equalTo: cancel.leadingAnchor, constant: -8),
            pill.centerYAnchor.constraint(equalTo: centerYAnchor),
            pill.heightAnchor.constraint(equalToConstant: 26),
            icon.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            cancel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            cancel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setQuery("")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setQuery(_ query: String) {
        if query.isEmpty {
            label.text = placeholder
            label.textColor = .secondaryLabel
        } else {
            label.text = query + "|"
            label.textColor = .label
        }
    }
}
