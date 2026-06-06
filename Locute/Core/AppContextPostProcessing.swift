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
            E-mail: po pozdravu čárka a nový odstavec; závěr (S pozdravem, Děkuji) v novém odstavci. \
            Jen interpunkce a odstavce — žádné vlastní věty.
            """
        ),
        AppContextPostProcessingPreset(
            bundleID: "com.todesktop.230313mzl4w4u92",
            instruction: "Kód / poznámky: zachovej identifikátory a syntaxi; pouze interpunkce tam, kde dává smysl."
        ),
        AppContextPostProcessingPreset(
            bundleID: "com.tinyspeck.slackmacgap",
            instruction: "Chat: krátké věty, tečky nebo otazníky; nepřidávej nic mimo přepis."
        ),
        AppContextPostProcessingPreset(
            bundleID: "com.apple.Terminal",
            instruction: "Terminál: neměň příkazy ani cesty; jen doplň . ? kde je to zjevná věta."
        ),
    ]
}
