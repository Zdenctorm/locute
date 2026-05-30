import AppKit

enum AccessibilitySupport {
    private static var lastAnnouncement = ""
    private static var lastAnnouncementTime: Date = .distantPast

    /// Systémové „Snížit pohyb“ — vypne pulzující animace v HUD a menu baru.
    static var shouldReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func configure(
        _ view: NSView,
        label: String,
        help: String? = nil,
        role: NSAccessibility.Role? = nil,
        hidden: Bool = false
    ) {
        view.setAccessibilityElement(!hidden)
        guard !hidden else { return }
        view.setAccessibilityLabel(label)
        if let help {
            view.setAccessibilityHelp(help)
        }
        if let role {
            view.setAccessibilityRole(role)
        }
    }

    static func configure(_ button: NSButton, label: String? = nil, help: String? = nil) {
        if let label {
            button.setAccessibilityLabel(label)
        }
        if let help {
            button.setAccessibilityHelp(help)
        }
    }

    static func configure(_ textField: NSTextField, label: String, help: String? = nil) {
        textField.setAccessibilityElement(true)
        textField.setAccessibilityLabel(label)
        if let help {
            textField.setAccessibilityHelp(help)
        }
    }

    static func configure(_ menuItem: NSMenuItem, help: String?) {
        menuItem.toolTip = help
        if let help {
            menuItem.setAccessibilityHelp(help)
        } else {
            menuItem.setAccessibilityHelp(nil)
        }
    }

    /// VoiceOver oznámení při změně stavu (overlay, úspěšné vložení).
    static func announce(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let now = Date()
        if trimmed == lastAnnouncement, now.timeIntervalSince(lastAnnouncementTime) < 1.5 {
            return
        }
        lastAnnouncement = trimmed
        lastAnnouncementTime = now

        NSAccessibility.post(
            element: NSApp,
            notification: .announcementRequested,
            userInfo: [
                .announcement: trimmed,
                .priority: NSAccessibilityPriorityLevel.high
            ]
        )
    }

    static func wordMarkupHelp(confidence: Double, original: String?) -> String {
        if let original {
            return "Slovo už bylo opraveno z „\(original)“. Klikni pro další úpravu."
        }
        if confidence < 0.65 {
            return "Nízká jistota přepisu. Klikni pro opravu slova."
        }
        if confidence < 0.85 {
            return "Střední jistota přepisu. Klikni pro opravu slova."
        }
        return ""
    }
}

extension LocuteState {
    /// Popis pro VoiceOver u ikony v menu baru.
    var statusBarAccessibilityLabel: String {
        switch self {
        case .launching:
            return "\(AppBrand.displayName), spouštím"
        case .permissionsNeeded:
            return "\(AppBrand.displayName), chybí oprávnění"
        case .modelDownloading(let progress):
            let percent = Int((progress.fraction * 100).rounded())
            return "\(AppBrand.displayName), stahuji model, \(percent) procent"
        case .modelLoading:
            return "\(AppBrand.displayName), načítám model"
        case .idle:
            return "\(AppBrand.displayName), připraveno k diktování"
        case .recording:
            return "\(AppBrand.displayName), nahrávám"
        case .transcribing:
            return "\(AppBrand.displayName), přepisuji"
        case .injecting:
            return "\(AppBrand.displayName), vkládám text"
        case .error(let message):
            return "\(AppBrand.displayName), chyba: \(message)"
        }
    }

    var statusBarAccessibilityHelp: String {
        switch self {
        case .idle:
            return "Podrž \(HotkeyPreference.current.hintLabel) a mluv, nebo otevři menu a zvol Začít diktování."
        case .recording:
            return "Pusť klávesu nebo v menu zvol Ukončit diktování."
        case .transcribing:
            return "Přepis probíhá lokálně na tomto Macu."
        case .injecting:
            return "Text se vkládá do aktivního pole."
        case .modelDownloading, .modelLoading, .launching:
            return "Po dokončení přípravy modelu můžeš diktovat."
        case .permissionsNeeded:
            return "Otevři Nastavení a oprávnění v menu \(AppBrand.displayName)."
        case .error:
            return "Podrobnosti najdeš v menu \(AppBrand.displayName)."
        }
    }

    /// Proč je diktování z menu dočasně nedostupné.
    var dictationMenuDisabledHelp: String? {
        switch self {
        case .transcribing:
            return "Počkej, dokud proběhne přepis."
        case .injecting:
            return "Počkej, dokud se text vloží."
        case .modelDownloading, .modelLoading, .launching:
            return "Diktování bude dostupné po přípravě modelu."
        case .permissionsNeeded:
            return "Nejdřív dokonči nastavení mikrofonu a Zpřístupnění."
        case .error:
            return "Nejdřív vyřeš chybu zobrazenou v menu."
        case .idle, .recording:
            return nil
        }
    }
}

extension RecordingOverlayMode {
    var accessibilityLabel: String {
        switch self {
        case .hidden:
            return ""
        case .keyHeld:
            return "Držíš \(HotkeyPreference.current.hintLabel)"
        case .recording:
            return "Nahrávám, mluv"
        case .streamingPreview(let confirmed, let draft):
            let combined = [confirmed, draft]
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if combined.isEmpty {
                return "Nahrávám, mluv"
            }
            return "Nahrávám. Dosud: \(combined)"
        case .transcribing:
            return "Přepisuji"
        case .injecting:
            return "Vkládám text"
        case .injectionSuccess:
            return "Vloženo"
        case .injectionFailed(let reason):
            return "Text se nevložil. \(reason). Otevři okno \(AppBrand.displayName)."
        case .busy(let message):
            return message
        case .wrongKey:
            return "Špatná klávesa. Drž \(HotkeyPreference.current.hintLabel)."
        }
    }

    var shouldAnnounce: Bool {
        switch self {
        case .recording, .streamingPreview, .transcribing, .injecting, .injectionSuccess, .injectionFailed, .busy, .wrongKey:
            return true
        case .hidden, .keyHeld:
            return false
        }
    }
}
