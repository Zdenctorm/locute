import AppKit
import ApplicationServices

/// „Monitorování vstupu“ (Listen Event) — nutné pro globální klávesu v cizích aplikacích.
/// Bez něj může CGEventTap / HID polling fungovat jen když je Locute v popředí.
enum InputMonitoringSettings {
    static func isGranted() -> Bool {
        CGPreflightListenEventAccess()
    }

    @discardableResult
    static func requestAccess() -> Bool {
        CGRequestListenEventAccess()
    }

    static func openPrivacyPane() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                DiagnosticsLogger.log("InputMonitoringSettings: opened \(candidate)")
                return
            }
        }
        DiagnosticsLogger.log("InputMonitoringSettings: failed to open privacy pane")
    }

    static func revealRunningAppBundle() {
        AccessibilitySettings.revealRunningAppBundle()
    }
}
