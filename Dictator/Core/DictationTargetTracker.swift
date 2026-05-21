import AppKit

/// Pamatuje poslední appku mimo Dictator — menu v menu baru jinak přepíše frontmost na Dictator.
@MainActor
final class DictationTargetTracker {
    private(set) var lastExternalApplication: NSRunningApplication?
    private let ownBundleID = Bundle.main.bundleIdentifier

    func startObserving() {
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            self?.noteActivated(app)
        }
        if let front = NSWorkspace.shared.frontmostApplication {
            noteActivated(front)
        }
    }

    /// Volat z `menuWillOpen` — ještě před kliknutím na položku menu.
    func snapshotForMenuAction() {
        menuSessionExternalTarget = nil
        if let front = NSWorkspace.shared.frontmostApplication, !isOwnApp(front) {
            lastExternalApplication = front
            menuSessionExternalTarget = front
            DiagnosticsLogger.log(
                "Dictation target snap (menu): \(front.localizedName ?? "?") (\(front.bundleIdentifier ?? "?"))"
            )
        }
    }

    func resolveTarget(atHotkeyDown frontmost: NSRunningApplication?, menuTriggered: Bool) -> NSRunningApplication? {
        if menuTriggered {
            if let menuSessionExternalTarget {
                return menuSessionExternalTarget
            }
            if let frontmost, !isOwnApp(frontmost) {
                return frontmost
            }
            return nil
        }
        if let frontmost, !isOwnApp(frontmost) {
            lastExternalApplication = frontmost
            return frontmost
        }
        // Uživatel diktuje z okna Dictatoru — přepis jen do historie, ne do staré externí appky.
        return nil
    }

    /// `true` pokud má smysl vkládat text do jiné aplikace (ne jen do panelu přepisů).
    func shouldInjectExternally(into target: NSRunningApplication?) -> Bool {
        guard let target else { return false }
        return !isOwnApp(target)
    }

    private func noteActivated(_ app: NSRunningApplication) {
        guard !isOwnApp(app) else { return }
        lastExternalApplication = app
    }

    private func isOwnApp(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier == ownBundleID
    }
}
