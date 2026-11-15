import UIKit

/// Settings shown inside the keyboard (in place of the keys) when ⚙ is tapped.
final class SettingsPanel: UIView {
    var onDone: (() -> Void)?
    var onResetLearned: (() -> Void)?
    /// Opens the theme editor in the BetterBoard app.
    var onOpenThemeEditor: (() -> Void)?

    private let settings = KeyboardSettings.shared
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let hasFullAccess: Bool
    private var themeButtons: [UIButton] = []

    init(isDark: Bool, hasFullAccess: Bool) {
        self.hasFullAccess = hasFullAccess
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
        addToggle("Sound on key press", \.keySound)
        addToggle("Vibrate on key press", \.vibrate)
        if !hasFullAccess {
            addNote("Sound and vibration need Full Access: Settings › General › Keyboard › Keyboards › BetterBoard.")
        }

        addSection("THEME")
        addThemePicker()
        addToggle("Key borders", \.keyBorders)
        addLinkButton("Make your own theme (photo, key colours) in the BetterBoard app \u{203A}") { [weak self] in
            self?.onOpenThemeEditor?()
        }

        addSection("TYPING")
        addToggle("Auto-correction", \.autocorrect)
        addToggle("Next-word suggestions", \.nextWord)
        addToggle("Emoji suggestions", \.emojiSuggestions)
        addToggle("Auto-capitalisation", \.autocap)
        addToggle("Double-space full stop", \.doubleSpacePeriod)
        addToggle("Auto-space after punctuation", \.autoSpace)
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

    private func addLinkButton(_ title: String, action: @escaping () -> Void) {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15)
        button.titleLabel?.numberOfLines = 0
        button.contentHorizontalAlignment = .leading
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        stack.addArrangedSubview(button)
    }

    private func addNote(_ text: String) {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        stack.addArrangedSubview(label)
    }

    /// A row of colour swatches, like Gboard's theme picker.
    private func addThemePicker() {
        let scroller = UIScrollView()
        scroller.showsHorizontalScrollIndicator = false
        scroller.heightAnchor.constraint(equalToConstant: 78).isActive = true
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        scroller.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: scroller.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scroller.contentLayoutGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: scroller.contentLayoutGuide.topAnchor, constant: 4),
            row.bottomAnchor.constraint(equalTo: scroller.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: scroller.frameLayoutGuide.heightAnchor, constant: -4),
        ])
        for style in ThemeStyle.allCases {
            row.addArrangedSubview(themeSwatch(style))
        }
        stack.addArrangedSubview(scroller)
        highlightTheme()
    }

    private func themeSwatch(_ style: ThemeStyle) -> UIView {
        let preview = Theme(style: style, systemIsDark: traitCollection.userInterfaceStyle == .dark,
                            keyBorders: true)
        let button = UIButton(type: .custom)
        button.tag = style.rawValue
        button.layer.cornerRadius = 10
        button.layer.cornerCurve = .continuous
        button.clipsToBounds = true
        button.widthAnchor.constraint(equalToConstant: 58).isActive = true
        button.heightAnchor.constraint(equalToConstant: 46).isActive = true
        let customMissing = style == .custom && CustomThemeStore.data == nil
        if style == .custom {
            if let image = CustomThemeStore.image {
                let photo = UIImageView(image: image)
                photo.contentMode = .scaleAspectFill
                photo.frame = CGRect(x: 0, y: 0, width: 58, height: 46)
                photo.isUserInteractionEnabled = false
                button.addSubview(photo)
            }
            if customMissing {
                button.backgroundColor = UIColor.secondarySystemFill
                let plus = UIImageView(image: UIImage(systemName: "plus"))
                plus.tintColor = .label
                plus.contentMode = .center
                plus.frame = CGRect(x: 0, y: 0, width: 58, height: 46)
                plus.isUserInteractionEnabled = false
                button.addSubview(plus)
            } else {
                button.backgroundColor = preview.background
                addMiniKeys(to: button, colors: [preview.keyColor, preview.keyColor], border: preview.keyBorderColor)
            }
        } else if style == .system {
            // Half light, half dark: follows your phone.
            let light = Theme(style: .system, systemIsDark: false, keyBorders: true)
            let dark = Theme(style: .system, systemIsDark: true, keyBorders: true)
            button.backgroundColor = UIColor(white: 0.82, alpha: 1)
            let half = UIView(frame: CGRect(x: 29, y: 0, width: 29, height: 46))
            half.backgroundColor = UIColor(white: 0.17, alpha: 1)
            half.isUserInteractionEnabled = false
            button.addSubview(half)
            addMiniKeys(to: button, colors: [light.keyColor, dark.keyColor])
        } else {
            button.backgroundColor = preview.background
            addMiniKeys(to: button, colors: [preview.keyColor, preview.keyColor])
        }
        button.addAction(UIAction { [weak self] _ in
            if customMissing {
                self?.onOpenThemeEditor?()
                return
            }
            self?.settings.theme = style
            self?.highlightTheme()
        }, for: .touchUpInside)
        themeButtons.append(button)

        let name = UILabel()
        name.text = style.title
        name.font = .systemFont(ofSize: 12)
        name.textColor = .secondaryLabel
        name.textAlignment = .center

        let column = UIStackView(arrangedSubviews: [button, name])
        column.axis = .vertical
        column.spacing = 4
        column.alignment = .center
        return column
    }

    /// Three little keys on the swatch.
    private func addMiniKeys(to button: UIButton, colors: [UIColor], border: UIColor? = nil) {
        for index in 0..<3 {
            let key = UIView(frame: CGRect(x: 7 + CGFloat(index) * 15, y: 16, width: 13, height: 14))
            key.backgroundColor = index < 2 ? colors[0] : colors[1]
            key.layer.cornerRadius = 3
            if let border {
                key.layer.borderWidth = 1
                key.layer.borderColor = border.cgColor
            }
            key.isUserInteractionEnabled = false
            button.addSubview(key)
        }
    }

    private func highlightTheme() {
        for button in themeButtons {
            let selected = button.tag == settings.theme.rawValue
            button.layer.borderWidth = selected ? 3 : 1
            button.layer.borderColor = selected ? UIColor.systemBlue.cgColor : UIColor.separator.cgColor
        }
    }

    private func addResetButton() {
        let button = UIButton(type: .system)
        button.setTitle("Reset learned & removed words", for: .normal)
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
