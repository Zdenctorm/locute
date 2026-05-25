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
        case .standard: return "Standardní (Qwen2.5 1.5B)"
        case .compact:  return "Kompaktní (Llama 1B)"
        }
    }

    var detail: String {
        switch self {
        case .standard:
            return "~950 MB, lepší čeština. Doporučeno."
        case .compact:
            return "~620 MB, rychlejší, méně přesné v češtině."
        }
    }
}

/// Preference pro opt-in AI opravu přepisů (interpunkce, kapitalizace, ALL-CAPS normalizace).
enum PostProcessingPreference {
    private static let enabledKey   = "postProcessingEnabled"
    private static let modelSizeKey = "postProcessingModelSize"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            NotificationCenter.default.post(name: .dictatorPostProcessingPreferenceChanged, object: nil)
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
            NotificationCenter.default.post(name: .dictatorPostProcessingPreferenceChanged, object: nil)
        }
    }
}

extension Notification.Name {
    static let dictatorPostProcessingPreferenceChanged = Notification.Name(
        "DictatorPostProcessingPreferenceChanged"
    )
}
