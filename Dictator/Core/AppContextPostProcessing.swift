import Foundation

/// Jednoduché per-app instrukce pro lokální LLM post-processing (bez cloudu).
struct AppContextPostProcessingPreset: Codable, Equatable, Sendable {
    var bundleID: String
    var instruction: String

    var trimmedInstruction: String {
        instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum AppContextPostProcessingStore {
    private static let storageKey = "appContextPostProcessingPresets"

    static func allPresets() -> [AppContextPostProcessingPreset] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([AppContextPostProcessingPreset].self, from: data) else {
            return defaultPresets
        }
        return decoded.isEmpty ? defaultPresets : decoded
    }

    static func save(_ presets: [AppContextPostProcessingPreset]) {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func instruction(for bundleID: String?) -> String? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        let preset = allPresets().first { $0.bundleID == bundleID }
        guard let text = preset?.trimmedInstruction, !text.isEmpty else { return nil }
        return text
    }

    private static let defaultPresets: [AppContextPostProcessingPreset] = [
        AppContextPostProcessingPreset(
            bundleID: "com.apple.mail",
            instruction: """
            Formátuj jako e-mail: zdvořilý tón, celé věty, správná interpunkce. \
            Po pozdravu čárka a nový odstavec; závěr v samostatném odstavci (např. S pozdravem).
            """
        ),
        AppContextPostProcessingPreset(
            bundleID: "com.todesktop.230313mzl4w4u92",
            instruction: "Formátuj jako text v editoru kódu: stručně, bez zdvořilostních frází, zachovej technické termíny."
        ),
        AppContextPostProcessingPreset(
            bundleID: "com.tinyspeck.slackmacgap",
            instruction: "Formátuj jako zprávu v chatu: stručně, neformálně, bez zbytečných oslovení."
        ),
        AppContextPostProcessingPreset(
            bundleID: "com.apple.Terminal",
            instruction: "Zachovej technické termíny a příkazy; minimum zdvořilostních frází."
        ),
    ]
}
