import UIKit

/// The balloon that appears above a letter key while it's pressed.
/// Shows the letter, then swaps to the symbol after the hold delay.
final class KeyPopupView: UIView {
    private let shape = CAShapeLayer()
    private let label = UILabel()

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
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// - Parameters:
    ///   - keyFrame: the pressed key's frame, in the superview's coordinates.
    ///   - limits: horizontal area the balloon must stay inside.
    func show(text: String, keyFrame: CGRect, limits: CGRect, theme: Theme, fontScale: CGFloat) {
        let radius = Metrics.cornerRadius
        let inflate = keyFrame.width * 0.3
        let bulbHeight = min(keyFrame.height * 1.05, 48)

        var bulb = CGRect(
            x: keyFrame.minX - inflate,
            y: keyFrame.minY - 4 - bulbHeight,
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

        let bulbPath = UIBezierPath(roundedRect: bulb, cornerRadius: radius + 2).cgPath
        let keyPath = UIBezierPath(roundedRect: keyFrame, cornerRadius: radius).cgPath
        let combined = bulbPath.union(neck.cgPath).union(keyPath)

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
        label.font = .systemFont(ofSize: Metrics.popupFontSize * fontScale)
        label.textColor = theme.labelColor
        label.text = text
        isHidden = false
    }

    func setText(_ text: String) {
        label.text = text
    }

    func hide() {
        isHidden = true
    }
}
