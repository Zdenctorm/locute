import AppKit
import ApplicationServices
import Foundation

enum DiagnosticsLogger {
    static let logDirectory: URL = {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let logsParent = base.appendingPathComponent("Logs", isDirectory: true)
        StorageDirectoryMigration.migrateIfNeeded(
            parent: logsParent,
            to: AppBrand.storageDirectoryName,
            from: AppBrand.legacyStorageDirectoryName
        )
        return logsParent.appendingPathComponent(AppBrand.storageDirectoryName, isDirectory: true)
    }()

    static let logFileURL = logDirectory.appendingPathComponent("diagnostics.log")

    private static let lock = NSLock()
    private static var lastFlagsChangedLog = Date.distantPast
    /// Full UUID string for grep in Console.crash logs + diagnostics.log.
    private static var dictationCorrelationID: UUID?

    static func enterDictationSession(id: UUID) {
        lock.lock()
        dictationCorrelationID = id
        lock.unlock()
        log("Dictation correlation id=\(id.uuidString)")
    }

    static func exitDictationSession() {
        lock.lock()
        dictationCorrelationID = nil
        lock.unlock()
    }

    static func log(_ message: String) {
        lock.lock()
        let prefix = dictationCorrelationID.map { "[dict=\($0.uuidString)] " } ?? ""
        lock.unlock()
        let line = "\(timestamp()) \(prefix)\(message)\n"
        lock.lock()
        defer { lock.unlock() }
        do {
            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                let handle = try FileHandle(forWritingTo: logFileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
                try handle.close()
            } else {
                try line.write(to: logFileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            // Diagnostics must never break dictation.
        }
    }

    static func logStartupContext() {
        log("Bundle path: \(Bundle.main.bundleURL.path)")
        log("AXIsProcessTrusted: \(AXIsProcessTrusted())")
        log("CGPreflightListenEventAccess: \(CGPreflightListenEventAccess())")
    }

    static func logFlagsChanged(keycode: Int, alt: Bool, numericPad: Bool, key58Down: Bool, key61Down: Bool) {
        let now = Date()
        lock.lock()
        let shouldLog = now.timeIntervalSince(lastFlagsChangedLog) >= 0.5
        if shouldLog {
            lastFlagsChangedLog = now
        }
        lock.unlock()
        guard shouldLog else { return }
        log("flagsChanged keycode=\(keycode) alt=\(alt) numericPad=\(numericPad) key58=\(key58Down) key61=\(key61Down)")
    }

    static func tailLines(_ count: Int) -> String {
        guard let data = try? Data(contentsOf: logFileURL),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(count).joined(separator: "\n")
    }

    static func copyTailToPasteboard(_ count: Int) {
        let text = tailLines(count)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func openLogDirectory() {
        NSWorkspace.shared.activateFileViewerSelecting([logFileURL])
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
