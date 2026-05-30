import Foundation

/// Veřejný brand a legacy technické názvy (složky na disku, Xcode target).
enum AppBrand {
    /// Zobrazovaný název v menu, oknech a systémových dialozích.
    static let displayName = "Locute"

    /// `~/Library/Application Support/` a `~/Library/Logs/` — beze změny kvůli migraci dat.
    static let storageDirectoryName = "Dictator"

    /// Aktuální název `.app` balíčku (např. `Dictator.app` dokud není přejmenován Xcode target).
    static var bundleFileName: String {
        Bundle.main.bundleURL.lastPathComponent
    }

    static var canonicalInstallPath: String {
        "/Applications/\(bundleFileName)"
    }
}
