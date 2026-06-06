import Foundation

/// Volba velikosti lokálního LLM modelu pro AI post-processing přepisů.
enum PostProcessingModelSize: String, CaseIterable, Sendable {
    case standard
    case compact

    var huggingFaceRepo: String {
        switch self {
        case .standard: return "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
        case .compact:  return "mlx-community/Llama-3.2-1B-Instruct-4bit"
        }
    }

    var expectedDownloadBytes: Int64 {
        switch self {
        case .standard: return 950_000_000
        case .compact:  return 620_000_000
        }
    }

    var label: String {
        switch self {
        case .standard: return "Kvalitní (~950 MB)"
        case .compact:  return "Rychlé (~620 MB)"
        }
    }

    var detail: String {
        switch self {
        case .standard:
            return "Doporučeno. Jednorázové stažení na tento Mac."
        case .compact:
            return "Menší stažení. Horší u delších textů."
        }
    }
}

/// Preference pro volitelnou lokální opravu přepisů (interpunkce, kapitalizace, ALL-CAPS normalizace).
enum PostProcessingPreference {
    private static let enabledKey   = "postProcessingEnabled"
    private static let modelSizeKey = "postProcessingModelSize"

    static var isEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: enabledKey) != nil else { return false }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            NotificationCenter.default.post(name: .locutePostProcessingPreferenceChanged, object: nil)
        }
    }

    static var modelSize: PostProcessingModelSize {
        get {
            guard let raw = UserDefaults.standard.string(forKey: modelSizeKey),
                  let value = PostProcessingModelSize(rawValue: raw) else {
                return .standard
            }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: modelSizeKey)
            NotificationCenter.default.post(name: .locutePostProcessingPreferenceChanged, object: nil)
        }
    }
}

extension Notification.Name {
    static let locutePostProcessingPreferenceChanged = Notification.Name(
        "LocutePostProcessingPreferenceChanged"
    )
}
