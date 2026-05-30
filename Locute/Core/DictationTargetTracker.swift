import AppKit

/// Pamatuje poslední appku mimo Locute — menu v menu baru jinak přepíše frontmost na Locute.
@MainActor
final class DictationTargetTracker {
    private(set) var lastExternalApplication: NSRunningApplication?
    private var lastExternalActivationAt: Date?
    /// Cíl zachycený při otevření menu — platí jen pro aktuální menu session.
    private var menuSessionExternalTarget: NSRunningApplication?
    private let ownBundleID = Bundle.main.bundleIdentifier
    /// Když `frontmostApplication` při hotkey down dočasně vrátí `nil` nebo vlastní appku,
    /// dovolíme krátký fallback na poslední externí appku.
    private let recentExternalFallbackWindow: TimeInterval = 8

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
            updateLastExternal(front)
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
            updateLastExternal(frontmost)
            return frontmost
        }
        // Když API vrátí nil, může jít o krátký focus race. V tom případě je bezpečné
        // použít čerstvě viděnou externí appku. Pokud je frontmost Locute, fallback
        // neděláme, aby diktování zůstalo "history only".
        if frontmost == nil, let fallback = recentExternalTarget() {
            DiagnosticsLogger.log(
                "Dictation target fallback to recent external app: \(fallback.localizedName ?? "?") (\(fallback.bundleIdentifier ?? "?"))"
            )
            return fallback
        }
        // Uživatel diktuje z okna Locute nebo neznáme bezpečný externí cíl.
        return nil
    }

    /// `true` pokud má smysl vkládat text do jiné aplikace (ne jen do panelu přepisů).
    func shouldInjectExternally(into target: NSRunningApplication?) -> Bool {
        guard let target else { return false }
        return !isOwnApp(target)
    }

    private func noteActivated(_ app: NSRunningApplication) {
        guard !isOwnApp(app) else { return }
        updateLastExternal(app)
    }

    private func isOwnApp(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier == ownBundleID
    }

    private func updateLastExternal(_ app: NSRunningApplication) {
        lastExternalApplication = app
        lastExternalActivationAt = Date()
    }

    private func recentExternalTarget() -> NSRunningApplication? {
        guard let app = lastExternalApplication,
              !isOwnApp(app),
              !app.isTerminated,
              let seenAt = lastExternalActivationAt,
              Date().timeIntervalSince(seenAt) <= recentExternalFallbackWindow else {
            return nil
        }
        return app
    }
}
