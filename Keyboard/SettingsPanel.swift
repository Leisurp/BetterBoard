import UIKit

/// Settings shown inside the keyboard (in place of the keys) when ⚙ is tapped.
final class SettingsPanel: UIView {
    var onDone: (() -> Void)?
    var onResetLearned: (() -> Void)?

    private let settings = KeyboardSettings.shared
    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    init(isDark: Bool) {
        super.init(frame: .zero)
        overrideUserInterfaceStyle = isDark ? .dark : .light
        backgroundColor = Touch.touchableBackground
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        let title = UILabel()
        title.text = "BetterBoard Settings"
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = .label

        let done = UIButton(type: .system)
        done.setTitle("Done", for: .normal)
        done.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        done.addAction(UIAction { [weak self] _ in self?.onDone?() }, for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [title, UIView(), done])
        header.axis = .horizontal
        header.alignment = .center
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            header.heightAnchor.constraint(equalToConstant: 40),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
        ])

        addSection("KEYS")
        addToggle("Hold for symbols", \.holdForSymbols)
        addDelaySlider()
        addToggle("Show symbol hints", \.showHints)
        addToggle("Pop-up on key press", \.keyPopup)
        addToggle("Number row", \.numberRow)
        addHeightPicker()

        addSection("TYPING")
        addToggle("Auto-correction", \.autocorrect)
        addToggle("Auto-capitalisation", \.autocap)
        addToggle("Double-space full stop", \.doubleSpacePeriod)
        addToggle("Double-tap Shift for caps lock", \.capsLock)

        addSection("OTHER")
        addResetButton()
    }

    // MARK: Rows

    private func addSection(_ text: String) {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabel
        let container = UIView()
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            container.heightAnchor.constraint(equalToConstant: 30),
        ])
        stack.addArrangedSubview(container)
    }

    private func row(_ title: String, _ control: UIView) -> UIStackView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 16)
        label.textColor = .label
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        let row = UIStackView(arrangedSubviews: [label, control])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        return row
    }

    private func addToggle(_ title: String, _ keyPath: ReferenceWritableKeyPath<KeyboardSettings, Bool>) {
        let toggle = UISwitch()
        toggle.isOn = settings[keyPath: keyPath]
        toggle.addAction(UIAction { [weak self] action in
            guard let sender = action.sender as? UISwitch else { return }
            self?.settings[keyPath: keyPath] = sender.isOn
        }, for: .valueChanged)
        stack.addArrangedSubview(row(title, toggle))
    }

    private func addDelaySlider() {
        let valueLabel = UILabel()
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        valueLabel.textColor = .secondaryLabel
        valueLabel.text = "\(settings.longPressDelayMs) ms"
        valueLabel.widthAnchor.constraint(equalToConstant: 64).isActive = true
        valueLabel.textAlignment = .right

        let slider = UISlider()
        slider.minimumValue = 100
        slider.maximumValue = 1000
        slider.value = Float(settings.longPressDelayMs)
        slider.widthAnchor.constraint(equalToConstant: 150).isActive = true
        slider.addAction(UIAction { [weak self] action in
            guard let sender = action.sender as? UISlider else { return }
            let ms = Int((sender.value / 50).rounded()) * 50
            valueLabel.text = "\(ms) ms"
            self?.settings.longPressDelayMs = ms
        }, for: .valueChanged)

        let controls = UIStackView(arrangedSubviews: [slider, valueLabel])
        controls.axis = .horizontal
        controls.spacing = 8
        controls.alignment = .center
        stack.addArrangedSubview(row("Hold delay", controls))
    }

    private func addHeightPicker() {
        let sizes = KeyboardSettings.HeightSize.allCases
        let picker = UISegmentedControl(items: sizes.map { $0.title })
        picker.selectedSegmentIndex = sizes.firstIndex(of: settings.heightSize) ?? 1
        picker.addAction(UIAction { [weak self] action in
            guard let sender = action.sender as? UISegmentedControl else { return }
            self?.settings.heightSize = sizes[sender.selectedSegmentIndex]
        }, for: .valueChanged)
        stack.addArrangedSubview(row("Keyboard height", picker))
    }

    private func addResetButton() {
        let button = UIButton(type: .system)
        button.setTitle("Reset learned words", for: .normal)
        button.setTitleColor(.systemRed, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16)
        button.contentHorizontalAlignment = .leading
        button.addAction(UIAction { [weak self] action in
            self?.onResetLearned?()
            (action.sender as? UIButton)?.setTitle("Learned words cleared", for: .normal)
        }, for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        stack.addArrangedSubview(button)
    }
}
