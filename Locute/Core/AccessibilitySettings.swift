import AppKit
import ApplicationServices

/// Otevření System Settings → Zpřístupnění a trust prompt pro CGEvent tap.
enum AccessibilitySettings {
    /// Zobrazí systémový dialog „Locute chce ovládat…" (max. jednou za instalaci; macOS pak
    /// typicky přesměruje do Nastavení, ale **nepřidá** appku do seznamu automaticky).
    @discardableResult
    static func requestTrustPrompt() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func isTrusted() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Otevře panel Zpřístupnění (Ventura+ Settings, starší System Preferences jako fallback).
    static func openPrivacyPane() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                DiagnosticsLogger.log("AccessibilitySettings: opened \(candidate)")
                return
            }
        }
        DiagnosticsLogger.log("AccessibilitySettings: failed to open privacy pane")
    }

    /// Aktivuje Finder na přesné `.app`, kterou právě spouštíte (důležité po rebuildu z Xcode / dist).
    static func revealRunningAppBundle() {
        let url = Bundle.main.bundleURL
        DiagnosticsLogger.log("AccessibilitySettings: reveal \(url.path)")
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
