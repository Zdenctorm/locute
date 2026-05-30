import Foundation

/// Společné umístění pro persistentní data Dictatoru.
enum PersistentStorage {
    static let containerURL: URL = {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent(AppBrand.storageDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}

/// Audio cache pro retry-detektor. Soubory tu žijí maximálně 1 h, pak je `purgeStale`
/// při periodickém běhu odstraní.
enum AudioCache {
    static let directoryURL: URL = {
        let dir = PersistentStorage.containerURL.appendingPathComponent("audio-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let retention: TimeInterval = 60 * 60

    /// Přesune WAV ze stávajícího (typicky `/tmp`) umístění do cache pojmenovaného podle entry ID.
    /// Po úspěchu vrátí novou URL. Selhání → `nil` a původní soubor zůstane.
    static func store(audioURL: URL, entryID: UUID) -> URL? {
        let target = directoryURL.appendingPathComponent("\(entryID.uuidString).wav")
        do {
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.moveItem(at: audioURL, to: target)
            return target
        } catch {
            DiagnosticsLogger.log("AudioCache: failed to move \(audioURL.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    static func purgeStale() {
        let now = Date()
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var purged = 0
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate else { continue }
            if now.timeIntervalSince(modified) > retention {
                try? FileManager.default.removeItem(at: url)
                purged += 1
            }
        }
        if purged > 0 {
            DiagnosticsLogger.log("AudioCache: purged \(purged) stale files")
        }
    }
}

/// History persistence — držíme posledních N přepisů s confidence info pro UI a learning.
enum HistoryStore {
    static let maxEntries = 200

    private static let storeURL: URL = PersistentStorage.containerURL.appendingPathComponent("history.json")
    private static let schemaVersion = 1

    private struct Storage: Codable {
        let schemaVersion: Int
        let entries: [TranscriptionHistoryEntry]
    }

    static func load() -> [TranscriptionHistoryEntry] {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: storeURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Storage.self, from: data).entries
        } catch {
            DiagnosticsLogger.log("HistoryStore: failed to load: \(error.localizedDescription)")
            return []
        }
    }

    static func save(_ entries: [TranscriptionHistoryEntry]) {
        let limited = Array(entries.prefix(maxEntries))
        let storage = Storage(schemaVersion: schemaVersion, entries: limited)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(storage)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            DiagnosticsLogger.log("HistoryStore: failed to persist: \(error.localizedDescription)")
        }
    }
}
