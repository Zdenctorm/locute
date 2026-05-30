import Foundation

enum StorageDirectoryMigration {
    /// Přesune `~/Library/.../Dictator` → `Locute`, pokud nová složka ještě neexistuje.
    static func migrateIfNeeded(parent: URL, to name: String, from legacyName: String) {
        guard name != legacyName else { return }
        let legacy = parent.appendingPathComponent(legacyName, isDirectory: true)
        let target = parent.appendingPathComponent(name, isDirectory: true)
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        guard !FileManager.default.fileExists(atPath: target.path) else { return }
        try? FileManager.default.moveItem(at: legacy, to: target)
    }
}
