import UIKit

/// The balloon that appears above a letter key while it's pressed.
/// Shows the letter, then swaps to the symbol after the hold delay.
final class KeyPopupView: UIView {
    private let shape = CAShapeLayer()
    private let label = UILabel()
    /// Row of choices shown when a key with several options is held.
    private var optionLabels: [UILabel] = []
    private let highlight = CALayer()
    /// Frames of the choices in the superview's coordinates, in option order.
    private var optionFrames: [CGRect] = []
    private var highlightColor = UIColor.systemBlue
    private var normalTextColor = UIColor.label
    private(set) var selectedOption = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.addSublayer(shape)
        shape.shadowColor = UIColor.black.cgColor
        shape.shadowOpacity = 0.3
        shape.shadowRadius = 3
        shape.shadowOffset = CGSize(width: 0, height: 1)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        addSubview(label)
        highlight.cornerRadius = Metrics.cornerRadius - 1
        layer.addSublayer(highlight)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// - Parameters:
    ///   - keyFrame: the pressed key's frame, in the superview's coordinates.
    ///   - limits: area the balloon must stay inside (it can't draw outside the keyboard).
    func show(text: String, keyFrame: CGRect, limits: CGRect, theme: Theme, fontScale: CGFloat) {
        let radius = Metrics.cornerRadius
        let inflate = keyFrame.width * 0.3
        let gap: CGFloat = 3
        let roomAbove = keyFrame.minY - gap - (limits.minY + 1)
        let bulbHeight = max(26, min(keyFrame.height * 1.05, 48, roomAbove))

        var bulb = CGRect(
            x: keyFrame.minX - inflate,
            y: keyFrame.minY - gap - bulbHeight,
            width: keyFrame.width + inflate * 2,
            height: bulbHeight)
        if bulb.minX < limits.minX + 1 { bulb.origin.x = limits.minX + 1 }
        if bulb.maxX > limits.maxX - 1 { bulb.origin.x = limits.maxX - 1 - bulb.width }

        let neck = UIBezierPath()
        neck.move(to: CGPoint(x: bulb.minX, y: bulb.maxY - radius))
        neck.addLine(to: CGPoint(x: bulb.maxX, y: bulb.maxY - radius))
        neck.addLine(to: CGPoint(x: keyFrame.maxX, y: keyFrame.minY + radius))
        neck.addLine(to: CGPoint(x: keyFrame.minX, y: keyFrame.minY + radius))
        neck.close()

        // All three shapes wind the same way, so filling them together draws their union
        // (much cheaper than boolean path operations on every key press).
        let path = UIBezierPath(roundedRect: bulb, cornerRadius: radius + 2)
        path.append(neck)
        path.append(UIBezierPath(roundedRect: keyFrame, cornerRadius: radius))
        let combined = path.cgPath

        let box = combined.boundingBoxOfPath
        frame = box
        var shift = CGAffineTransform(translationX: -box.minX, y: -box.minY)
        let local = combined.copy(using: &shift) ?? combined

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.path = local
        shape.shadowPath = local
        shape.fillColor = theme.popupColor.cgColor
        CATransaction.commit()

        label.frame = bulb.offsetBy(dx: -box.minX, dy: -box.minY).insetBy(dx: 2, dy: 0)
        label.font = .systemFont(ofSize: min(Metrics.popupFontSize * fontScale, bulbHeight * 0.85))
        label.textColor = theme.labelColor
        label.text = text
        label.isHidden = false
        clearOptions()
        isHidden = false
    }

    /// Shows several choices in a row above the key, the first one selected.
    /// The row extends away from the nearer screen edge, with the first choice over the key.
    func showOptions(_ options: [String], keyFrame: CGRect, limits: CGRect, theme: Theme, fontScale: CGFloat) {
        let radius = Metrics.cornerRadius
        let gap: CGFloat = 3
        let pad: CGFloat = 4
        let roomAbove = keyFrame.minY - gap - (limits.minY + 1)
        let bulbHeight = max(28, min(keyFrame.height * 1.05, 48, roomAbove))
        let cellWidth = min(max(keyFrame.width, 30), (limits.width - 2 - pad * 2) / CGFloat(options.count))
        let width = cellWidth * CGFloat(options.count) + pad * 2

        // Go right from the key, or left if the key is on the right-hand side.
        let goLeft = keyFrame.midX > limits.midX
        var bulb = CGRect(x: goLeft ? keyFrame.midX + cellWidth / 2 + pad - width
                                    : keyFrame.midX - cellWidth / 2 - pad,
                          y: keyFrame.minY - gap - bulbHeight,
                          width: width, height: bulbHeight)
        if bulb.minX < limits.minX + 1 { bulb.origin.x = limits.minX + 1 }
        if bulb.maxX > limits.maxX - 1 { bulb.origin.x = limits.maxX - 1 - bulb.width }

        let path = UIBezierPath(roundedRect: bulb, cornerRadius: radius + 2)
        let neckX = max(keyFrame.minX, bulb.minX)
        let neckMaxX = min(keyFrame.maxX, bulb.maxX)
        path.append(UIBezierPath(rect: CGRect(x: neckX, y: bulb.maxY - radius,
                                              width: neckMaxX - neckX,
                                              height: keyFrame.minY + radius - (bulb.maxY - radius))))
        path.append(UIBezierPath(roundedRect: keyFrame, cornerRadius: radius))
        let combined = path.cgPath
        let box = combined.boundingBoxOfPath
        frame = box
        var shift = CGAffineTransform(translationX: -box.minX, y: -box.minY)
        let local = combined.copy(using: &shift) ?? combined

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.path = local
        shape.shadowPath = local
        shape.fillColor = theme.popupColor.cgColor

        clearOptions()
        label.isHidden = true
        highlightColor = theme.accentColor
        normalTextColor = theme.labelColor
        let font = UIFont.systemFont(ofSize: min(Metrics.popupFontSize * 0.75 * fontScale, bulbHeight * 0.7))
        for (index, option) in options.enumerated() {
            // Left-going rows put the first choice on the right, next to the key.
            let slot = goLeft ? options.count - 1 - index : index
            let cell = CGRect(x: bulb.minX + pad + CGFloat(slot) * cellWidth, y: bulb.minY + 3,
                              width: cellWidth, height: bulbHeight - 6)
            optionFrames.append(cell)
            let optionLabel = UILabel(frame: cell.offsetBy(dx: -box.minX, dy: -box.minY))
            optionLabel.text = option
            optionLabel.font = font
            optionLabel.textAlignment = .center
            optionLabel.adjustsFontSizeToFitWidth = true
            optionLabel.minimumScaleFactor = 0.5
            addSubview(optionLabel)
            optionLabels.append(optionLabel)
        }
        highlight.isHidden = false
        selectOption(0)
        CATransaction.commit()
        isHidden = false
    }

    /// Which choice is under the finger (x in the superview's coordinates).
    func optionIndex(atX x: CGFloat) -> Int {
        guard !optionFrames.isEmpty else { return 0 }
        var best = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, cell) in optionFrames.enumerated() {
            let distance = abs(cell.midX - x)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    func selectOption(_ index: Int) {
        guard index < optionLabels.count else { return }
        selectedOption = index
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlight.frame = optionLabels[index].frame
        highlight.backgroundColor = highlightColor.cgColor
        CATransaction.commit()
        for (i, optionLabel) in optionLabels.enumerated() {
            optionLabel.textColor = i == index ? .white : normalTextColor
        }
    }

    private func clearOptions() {
        optionLabels.forEach { $0.removeFromSuperview() }
        optionLabels.removeAll()
        optionFrames.removeAll()
        highlight.isHidden = true
        selectedOption = 0
    }

    func setText(_ text: String) {
        label.text = text
    }

    func hide() {
        isHidden = true
    }
}
