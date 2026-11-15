import AudioToolbox
import UIKit

/// Click sound and vibration on key presses (Gboard "Sound on keypress" /
/// "Vibrate on keypress"). iOS only allows both when Full Access is on.
final class KeyFeedback {
    private let settings = KeyboardSettings.shared
    private lazy var impact = UIImpactFeedbackGenerator(style: .light)

    /// iPhone's own keyboard sounds.
    private enum Sound {
        static let letter: SystemSoundID = 1104
        static let delete: SystemSoundID = 1155
        static let modifier: SystemSoundID = 1156
    }

    func keyDown(_ action: KeyAction, hasFullAccess: Bool) {
        guard hasFullAccess else { return }
        if settings.vibrate {
            impact.impactOccurred(intensity: 0.75)
            impact.prepare()
        }
        if settings.keySound {
            switch action {
            case .character, .space:
                AudioServicesPlaySystemSound(Sound.letter)
            case .backspace:
                AudioServicesPlaySystemSound(Sound.delete)
            default:
                AudioServicesPlaySystemSound(Sound.modifier)
            }
        }
    }

    /// Lighter tick, e.g. while sliding the cursor along the space bar.
    func tick(hasFullAccess: Bool) {
        guard hasFullAccess, settings.vibrate else { return }
        impact.impactOccurred(intensity: 0.4)
    }

    /// Call when the keyboard appears so the first vibration isn't delayed.
    func prepare(hasFullAccess: Bool) {
        if hasFullAccess && settings.vibrate { impact.prepare() }
    }
}
