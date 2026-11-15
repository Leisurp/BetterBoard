import AVFoundation
import AudioToolbox
import UIKit

/// Click sound and vibration on key presses (Gboard "Sound on keypress" /
/// "Vibrate on keypress", with volume and strength). iOS only allows both when
/// Full Access is on.
final class KeyFeedback {
    private let settings = KeyboardSettings.shared
    private lazy var impact = UIImpactFeedbackGenerator(style: .medium)

    private enum Kind: Int { case letter = 0, delete, modifier }

    /// iPhone's own keyboard sounds, played through AVAudioPlayer so the volume
    /// can be set. A few players per sound so fast typing doesn't cut clicks off.
    private static let soundFiles = [
        "/System/Library/Audio/UISounds/key_press_click.caf",
        "/System/Library/Audio/UISounds/key_press_delete.caf",
        "/System/Library/Audio/UISounds/key_press_modifier.caf",
    ]
    /// Used if the sound files can't be read.
    private static let systemSounds: [SystemSoundID] = [1104, 1155, 1156]
    private var players: [[AVAudioPlayer]] = []
    private var nextPlayer = [0, 0, 0]
    private var audioReady = false
    private var lastPreview: CFTimeInterval = 0

    func keyDown(_ action: KeyAction, hasFullAccess: Bool) {
        guard hasFullAccess else { return }
        if settings.vibrate {
            vibrate(strength: settings.vibrationStrength)
        }
        if settings.keySound {
            switch action {
            case .character, .space: play(.letter)
            case .backspace: play(.delete)
            default: play(.modifier)
            }
        }
    }

    /// Lighter tick, e.g. while sliding the cursor along the space bar.
    func tick(hasFullAccess: Bool) {
        guard hasFullAccess, settings.vibrate else { return }
        vibrate(strength: settings.vibrationStrength * 0.5)
    }

    /// While dragging the volume / strength sliders in settings.
    func preview(hasFullAccess: Bool) {
        let now = CACurrentMediaTime()
        guard now - lastPreview > 0.15 else { return }
        lastPreview = now
        keyDown(.character, hasFullAccess: hasFullAccess)
    }

    /// Call when the keyboard appears so the first click / vibration isn't delayed.
    func prepare(hasFullAccess: Bool) {
        guard hasFullAccess else { return }
        if settings.vibrate { impact.prepare() }
        if settings.keySound { setUpAudio() }
    }

    private func vibrate(strength: Double) {
        guard strength > 0.01 else { return }
        impact.impactOccurred(intensity: CGFloat(0.15 + 0.85 * strength))
        impact.prepare()
    }

    private func play(_ kind: Kind) {
        let volume = Float(settings.soundVolume)
        guard volume > 0.01 else { return }
        setUpAudio()
        let list = kind.rawValue < players.count ? players[kind.rawValue] : []
        guard !list.isEmpty else {
            AudioServicesPlaySystemSound(Self.systemSounds[kind.rawValue])
            return
        }
        let index = nextPlayer[kind.rawValue] % list.count
        nextPlayer[kind.rawValue] = index + 1
        let player = list[index]
        player.volume = volume
        player.currentTime = 0
        player.play()
    }

    private func setUpAudio() {
        guard !audioReady else { return }
        audioReady = true
        // Ambient: respects the silent switch and doesn't stop music.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        players = Self.soundFiles.map { path in
            (0..<3).compactMap { _ in
                guard let player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) else { return nil }
                player.prepareToPlay()
                return player
            }
        }
    }
}
