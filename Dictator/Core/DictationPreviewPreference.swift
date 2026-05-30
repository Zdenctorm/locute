import Foundation

/// Live partial transcript in the recording HUD (Whisper streaming while key is held).
enum DictationPreviewPreference {
    private static let storageKey = "showLiveTranscriptionPreview"

    /// Default off — user sees recording indicator only, not progressive text.
    static var isEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: storageKey) != nil else { return false }
            return UserDefaults.standard.bool(forKey: storageKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: storageKey)
            NotificationCenter.default.post(name: .dictatorPreviewPreferenceChanged, object: nil)
        }
    }
}

extension Notification.Name {
    static let dictatorPreviewPreferenceChanged = Notification.Name("DictatorPreviewPreferenceChanged")
}
