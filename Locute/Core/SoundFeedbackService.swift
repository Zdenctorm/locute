import AppKit
import Foundation

/// Krátké systémové zvuky pro start/stop/chybu diktování (TypeWhisper-style).
enum SoundFeedbackService {
    private static let enabledKey = "soundFeedbackEnabled"

    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static func playRecordingStart() {
        play(name: "Tink")
    }

    static func playRecordingStop() {
        play(name: "Pop")
    }

    static func playSuccess() {
        play(name: "Glass")
    }

    static func playError() {
        play(name: "Basso")
    }

    private static func play(name: String) {
        guard isEnabled else { return }
        NSSound(named: name)?.play()
    }
}
