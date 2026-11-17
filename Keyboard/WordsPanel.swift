import UIKit

/// Lists the words the keyboard has learned (delete them one at a time) and the
/// suggestions you've removed (bring them back). Opened from settings.
final class WordsPanel: UIView, UITableViewDataSource, UITableViewDelegate {
    var onBack: (() -> Void)?
    private let autocorrector: Autocorrector
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var learned: [String] = []
    private var removed: [String] = []

    init(autocorrector: Autocorrector, isDark: Bool) {
        self.autocorrector = autocorrector
        super.init(frame: .zero)
        overrideUserInterfaceStyle = isDark ? .dark : .light
        backgroundColor = isDark ? UIColor(white: 0.12, alpha: 1) : UIColor(white: 0.93, alpha: 1)
        buildUI()
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        let back = UIButton(type: .system)
        back.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        back.setTitle(" Settings", for: .normal)
        back.titleLabel?.font = .systemFont(ofSize: 17)
        back.addAction(UIAction { [weak self] _ in self?.onBack?() }, for: .touchUpInside)

        let title = UILabel()
        title.text = "Words"
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = .label

        table.dataSource = self
        table.delegate = self
        table.backgroundColor = .clear
        table.register(UITableViewCell.self, forCellReuseIdentifier: "word")

        for view in [back, title, table] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            back.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            back.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            back.heightAnchor.constraint(equalToConstant: 36),
            title.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            title.centerXAnchor.constraint(equalTo: centerXAnchor),
            table.topAnchor.constraint(equalTo: back.bottomAnchor),
            table.leadingAnchor.constraint(equalTo: leadingAnchor),
            table.trailingAnchor.constraint(equalTo: trailingAnchor),
            table.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func reload() {
        learned = autocorrector.learnedWords
        removed = autocorrector.removedWords
        table.reloadData()
    }

    // MARK: Table

    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Learned words" : "Removed suggestions"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 {
            return learned.isEmpty
                ? "None yet. Words you type that aren't in the dictionary are learned after you use them twice."
                : "Tap − to forget a word."
        }
        return removed.isEmpty
            ? "None. Hold a suggestion in the bar to stop it being suggested."
            : "Tap ↺ to suggest it again."
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? learned.count : removed.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "word", for: indexPath)
        let word = indexPath.section == 0 ? learned[indexPath.row] : removed[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = word
        cell.contentConfiguration = content
        cell.selectionStyle = .none

        let button = UIButton(type: .system)
        let icon = indexPath.section == 0 ? "minus.circle.fill" : "arrow.uturn.backward.circle"
        button.setImage(UIImage(systemName: icon,
                                withConfiguration: UIImage.SymbolConfiguration(pointSize: 20)), for: .normal)
        button.tintColor = indexPath.section == 0 ? .systemRed : .systemBlue
        button.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        let section = indexPath.section
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if section == 0 {
                self.autocorrector.forget(word)
            } else {
                self.autocorrector.restore(word)
            }
            self.reload()
        }, for: .touchUpInside)
        cell.accessoryView = button
        return cell
    }
}
