import Foundation

/// Veřejný brand a technické názvy (složky na disku, Xcode target).
enum AppBrand {
    /// Zobrazovaný název v menu, oknech a systémových dialozích.
    static let displayName = "Locute"

    /// `~/Library/Application Support/` a `~/Library/Logs/`.
    static let storageDirectoryName = "Locute"

    /// Složka před přejmenováním produktu (migrace při prvním spuštění).
    static let legacyStorageDirectoryName = "Dictator"

    /// Aktuální název `.app` balíčku (např. `Locute.app`).
    static var bundleFileName: String {
        Bundle.main.bundleURL.lastPathComponent
    }

    static var canonicalInstallPath: String {
        "/Applications/\(bundleFileName)"
    }
}
