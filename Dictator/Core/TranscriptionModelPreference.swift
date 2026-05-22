import Foundation

/// Volba velikosti Whisper modelu — rychlost vs. přesnost (český přepis).
enum TranscriptionModelPreference: String, CaseIterable, Sendable {
    case speed
    case accuracy

    private static let storageKey = "transcriptionModelPreference"

    static var current: TranscriptionModelPreference {
        get {
            guard let raw = UserDefaults.standard.string(forKey: storageKey),
                  let value = TranscriptionModelPreference(rawValue: raw) else {
                return .speed
            }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
            NotificationCenter.default.post(name: .dictatorTranscriptionModelPreferenceChanged, object: nil)
        }
    }

    var label: String {
        switch self {
        case .speed: return "Rychlost (turbo)"
        case .accuracy: return "Přesnost (large-v3)"
        }
    }

    var detail: String {
        switch self {
        case .speed:
            return "Rychlejší přepis, menší stažení (~630 MB). Doporučeno pro denní diktování."
        case .accuracy:
            return "Nejpřesnější varianta (~626 MB v20240930). Pomalejší než turbo."
        }
    }

    /// WhisperKit `download(variant:)` — musí odpovídat složce v argmaxinc/whisperkit-coreml.
    var whisperKitVariant: String {
        switch self {
        case .speed: return "large-v3-v20240930_turbo"
        case .accuracy: return "large-v3-v20240930"
        }
    }

    var expectedDownloadBytes: Int64 {
        switch self {
        case .speed: return 632_000_000
        case .accuracy: return 626_000_000
        }
    }
}

extension Notification.Name {
    static let dictatorTranscriptionModelPreferenceChanged = Notification.Name(
        "DictatorTranscriptionModelPreferenceChanged"
    )
}
