import UIKit

protocol ClipboardPanelDelegate: AnyObject {
    func clipboardPanelClose(_ panel: ClipboardPanel)
    func clipboardPanelOpenSetup(_ panel: ClipboardPanel)
    func clipboardPanel(_ panel: ClipboardPanel, didPick text: String)
}

/// Clipboard history shown in place of the keys. Tap to paste, swipe to delete,
/// pin to keep.
final class ClipboardPanel: UIView, UITableViewDataSource, UITableViewDelegate {
    weak var delegate: ClipboardPanelDelegate?
    private let store: ClipboardStore
    private let table = UITableView(frame: .zero, style: .plain)
    private let messageLabel = UILabel()
    private let setupButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private var rows: [ClipItem] = []

    init(store: ClipboardStore, isDark: Bool, hasFullAccess: Bool) {
        self.store = store
        super.init(frame: .zero)
        overrideUserInterfaceStyle = isDark ? .dark : .light
        backgroundColor = Touch.touchableBackground
        buildUI()
        if hasFullAccess {
            reload()
        } else {
            showSetup()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        let back = UIButton(type: .system)
        back.setTitle("ABC", for: .normal)
        back.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        back.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.clipboardPanelClose(self)
        }, for: .touchUpInside)

        let title = UILabel()
        title.text = "Clipboard"
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = .label
        title.textAlignment = .center

        clearButton.setTitle("Clear", for: .normal)
        clearButton.addAction(UIAction { [weak self] _ in
            self?.store.clearUnpinned()
            self?.reload()
        }, for: .touchUpInside)

        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 50
        table.register(UITableViewCell.self, forCellReuseIdentifier: "clip")

        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.font = .systemFont(ofSize: 15)
        messageLabel.textColor = .label

        setupButton.setTitle("Set up clipboard in the BetterBoard app \u{203A}", for: .normal)
        setupButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        setupButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.clipboardPanelOpenSetup(self)
        }, for: .touchUpInside)

        for view in [back, title, clearButton, table, messageLabel, setupButton] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            back.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            back.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            back.widthAnchor.constraint(equalToConstant: 44),
            back.heightAnchor.constraint(equalToConstant: 34),
            title.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            title.centerXAnchor.constraint(equalTo: centerXAnchor),
            clearButton.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            table.topAnchor.constraint(equalTo: back.bottomAnchor, constant: 4),
            table.leadingAnchor.constraint(equalTo: leadingAnchor),
            table.trailingAnchor.constraint(equalTo: trailingAnchor),
            table.bottomAnchor.constraint(equalTo: bottomAnchor),

            messageLabel.centerYAnchor.constraint(equalTo: table.centerYAnchor, constant: -16),
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            setupButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 10),
            setupButton.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    private func showSetup() {
        table.isHidden = true
        clearButton.isHidden = true
        messageLabel.isHidden = false
        setupButton.isHidden = false
        messageLabel.text = "Clipboard history needs Full Access turned on. iOS only lets keyboards see what you've copied when it's on."
    }

    func reload() {
        rows = store.items.sorted { ($0.pinned ? 0 : 1, $1.date) < ($1.pinned ? 0 : 1, $0.date) }
        setupButton.isHidden = true
        table.isHidden = rows.isEmpty
        clearButton.isHidden = !rows.contains { !$0.pinned }
        messageLabel.isHidden = !rows.isEmpty
        messageLabel.text = "Text you copy shows up here.\nTap an item to paste it, swipe to delete, pin to keep it."
        table.reloadData()
    }

    // MARK: Table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "clip", for: indexPath)
        let item = rows[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = item.text.replacingOccurrences(of: "\n", with: " ")
        content.textProperties.numberOfLines = 2
        content.textProperties.font = .systemFont(ofSize: 15)
        cell.contentConfiguration = content
        cell.backgroundColor = .clear

        let pin = UIButton(type: .system)
        pin.setImage(UIImage(systemName: item.pinned ? "pin.fill" : "pin"), for: .normal)
        pin.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        pin.addAction(UIAction { [weak self] _ in
            self?.store.togglePin(item.id)
            self?.reload()
        }, for: .touchUpInside)
        cell.accessoryView = pin
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        delegate?.clipboardPanel(self, didPick: rows[indexPath.row].text)
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let item = rows[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            self?.store.delete(item.id)
            self?.reload()
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}
