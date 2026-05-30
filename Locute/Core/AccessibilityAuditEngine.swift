import AppKit
import ApplicationServices
import Foundation

// MARK: - Public API

/// Automatická kontrola VoiceOver / NSAccessibility v \(AppBrand.displayName) a stručné srovnání s referenčními macOS appkami.
enum AccessibilityAuditEngine {
    static let reportDirectory: URL = DiagnosticsLogger.logDirectory

    /// Referenční aplikace s obvykle dobrou podporou přístupnosti (menu bar, Nastavení, nativní UI).
    static let referenceApplications: [AccessibilityReferenceApplication] = [
        .init(
            bundleIdentifier: "com.apple.systempreferences",
            displayName: "Nastavení (System Settings)",
            rationale: "Nativní AppKit, bohaté popisky u přepínačů a seznamů."
        ),
        .init(
            bundleIdentifier: "com.apple.Notes",
            displayName: "Poznámky",
            rationale: "Editor textu, podobný kontext vkládání obsahu."
        ),
        .init(
            bundleIdentifier: "com.apple.VoiceMemos",
            displayName: "Hlasové poznámky",
            rationale: "Audio + stav nahrávání — srovnatelné s diktováním."
        ),
        .init(
            bundleIdentifier: "com.apple.shortcuts",
            displayName: "Zkratky",
            rationale: "Utility appka s panelem a akcemi."
        )
    ]

    struct AuditContext: Sendable {
        var openWindowTitles: [String]
        var axTrusted: Bool
        var appVersion: String
        var bundlePath: String
    }

    /// Spustí audit a vrátí cestu k uložené zprávě Markdown.
    @MainActor
    static func runAndSaveReport(
        extraMenu: NSMenu? = nil,
        context: AuditContext? = nil
    ) -> URL? {
        let ctx = context ?? AuditContext(
            openWindowTitles: NSApp.windows.map { $0.title.isEmpty ? "(bez titulku)" : $0.title },
            axTrusted: AccessibilitySettings.isTrusted(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            bundlePath: Bundle.main.bundleURL.path
        )

        let locuteFindings = auditLocuteUI(extraMenu: extraMenu)
        let menuFindings = extraMenu.map { auditMenu($0, path: "Menu bar") } ?? []
        let referenceSnapshots = auditReferenceApplications()
        let inventory = AccessibilitySurfaceInventory.current()

        let report = AccessibilityAuditReportBuilder.build(
            context: ctx,
            inventory: inventory,
            locuteFindings: locuteFindings + menuFindings,
            referenceSnapshots: referenceSnapshots
        )

        let url = saveReport(report)
        DiagnosticsLogger.log("Accessibility audit saved: \(url?.path ?? "failed")")
        return url
    }

    @MainActor
    static func openLatestReportInFinder() {
        guard let url = latestReportURL() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func latestReportURL() -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: reportDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return files
            .filter { $0.lastPathComponent.hasPrefix("accessibility-audit-") && $0.pathExtension == "md" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l > r
            }
            .first
    }

    // MARK: - \(AppBrand.displayName) UI

    @MainActor
    private static func auditLocuteUI(extraMenu: NSMenu?) -> [AccessibilityAuditFinding] {
        var findings: [AccessibilityAuditFinding] = []
        for window in NSApp.windows where window.isVisible || window.isMiniaturized == false {
            guard let content = window.contentView else { continue }
            let title = window.title.isEmpty ? String(describing: type(of: window)) : window.title
            findings.append(contentsOf: auditView(content, path: "Okno: \(title)"))
        }
        if NSApp.windows.isEmpty {
            findings.append(
                AccessibilityAuditFinding(
                    severity: .info,
                    surface: "Obecně",
                    path: "NSApp.windows",
                    issue: "V době auditu nebylo otevřené žádné okno \(AppBrand.displayName).",
                    suggestion: "Před auditem otevři Nastavení… a případně Co se \(AppBrand.displayName) naučil…, pak audit zopakuj."
                )
            )
        }
        return findings
    }

    @MainActor
    private static func auditView(_ view: NSView, path: String, depth: Int = 0) -> [AccessibilityAuditFinding] {
        guard depth < 40 else { return [] }
        var findings: [AccessibilityAuditFinding] = []
        findings.append(contentsOf: evaluateView(view, path: path))

        let childPath: String
        if let stack = view as? NSStackView {
            childPath = "\(path) > \(view.axShortDescription) [\(stack.views.count) children]"
        } else {
            childPath = "\(path) > \(view.axShortDescription)"
        }

        for subview in view.subviews {
            findings.append(contentsOf: auditView(subview, path: childPath, depth: depth + 1))
        }
        return findings
    }

    @MainActor
    private static func evaluateView(_ view: NSView, path: String) -> [AccessibilityAuditFinding] {
        guard !view.isHidden, view.alphaValue > 0.01 else { return [] }

        var findings: [AccessibilityAuditFinding] = []
        let isIgnored = view.accessibilityIsIgnored()
        let isElement = !isIgnored
        let label = view.accessibilityLabel()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = view.accessibilityTitle()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let help = view.accessibilityHelp()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let role = view.accessibilityRole()
        let combinedName = [label, title].first { !$0.isEmpty } ?? ""

        let looksInteractive = view is NSControl || view is NSButton || view is NSTextField || view is NSTextView
        let isStatusOnly = isIgnored && (view is NSTextField || view is NSTextView)

        if looksInteractive && !isElement && view.userInteractionEnabled {
            findings.append(
                .init(
                    severity: .critical,
                    surface: surfaceName(for: view),
                    path: path,
                    issue: "Interaktivní prvek není v accessibility stromu.",
                    suggestion: "Zavolej AccessibilitySupport.configure nebo setAccessibilityElement(true) s popisem."
                )
            )
        }

        if isElement && combinedName.isEmpty && role != .group && role != .unknown {
            let decorative = view is NSImageView || (view is NSBox && (view as? NSBox)?.title == "")
            if !decorative {
                findings.append(
                    .init(
                        severity: .critical,
                        surface: surfaceName(for: view),
                        path: path,
                        issue: "Prvek je v accessibility stromu bez label/title.",
                        suggestion: "Doplň setAccessibilityLabel nebo setAccessibilityTitle (česky, s kontextem akce)."
                    )
                )
            }
        }

        if isElement && combinedName.isEmpty && (view is NSImageView || view is NSBox) {
            findings.append(
                .init(
                    severity: .warning,
                    surface: surfaceName(for: view),
                    path: path,
                    issue: "Dekorativní prvek je stále označen jako accessibility element.",
                    suggestion: "Skryj dekoraci: setAccessibilityElement(false) nebo hidden: true v AccessibilitySupport.configure."
                )
            )
        }

        if isElement && help.isEmpty && looksInteractive {
            findings.append(
                .init(
                    severity: .warning,
                    surface: surfaceName(for: view),
                    path: path,
                    issue: "Interaktivní prvek nemá accessibility help.",
                    suggestion: "U složitějších akcí doplň setAccessibilityHelp (co se stane po aktivaci)."
                )
            )
        }

        if isStatusOnly && !combinedName.isEmpty {
            findings.append(
                .init(
                    severity: .info,
                    surface: surfaceName(for: view),
                    path: path,
                    issue: "Text má popisek, ale není accessibility element (záměrný šum?).",
                    suggestion: "U živého stavu (overlay) nech vypnuté; u statického textu v panelu zvaž role .staticText."
                )
            )
        }

        if let button = view as? NSButton, button.image != nil, button.title.isEmpty, combinedName.isEmpty {
            findings.append(
                .init(
                    severity: .critical,
                    surface: surfaceName(for: view),
                    path: path,
                    issue: "Tlačítko jen s ikonou bez textového ani accessibility popisku.",
                    suggestion: "AccessibilitySupport.configure(button, label: \"…\") nebo accessibilityDescription u NSImage."
                )
            )
        }

        return findings
    }

    @MainActor
    private static func auditMenu(_ menu: NSMenu, path: String) -> [AccessibilityAuditFinding] {
        var findings: [AccessibilityAuditFinding] = []
        for (index, item) in menu.items.enumerated() {
            let itemPath = "\(path) > položka \(index): \(item.title.isEmpty ? "(separator)" : item.title)"
            if item.isSeparatorItem { continue }
            let label = item.accessibilityLabel() ?? item.title
            if label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                findings.append(
                    .init(
                        severity: .critical,
                        surface: "Menu bar",
                        path: itemPath,
                        issue: "Položka menu bez titulku a label.",
                        suggestion: "Nastav title u NSMenuItem."
                    )
                )
            }
            if item.isEnabled, (item.accessibilityHelp() ?? "").isEmpty {
                let disabledReason = item.toolTip ?? ""
                if item.action != nil, disabledReason.isEmpty, !item.title.contains("(") {
                    findings.append(
                        .init(
                            severity: .info,
                            surface: "Menu bar",
                            path: itemPath,
                            issue: "Aktivní položka menu bez accessibility help (tooltip).",
                            suggestion: "Pro položky s nejasnou akcí použij AccessibilitySupport.configure(menuItem, help: …)."
                        )
                    )
                }
            }
            if let submenu = item.submenu {
                findings.append(contentsOf: auditMenu(submenu, path: itemPath))
            }
        }
        return findings
    }

    // MARK: - Reference apps (AX)

    private static func auditReferenceApplications() -> [AccessibilityReferenceSnapshot] {
        guard AccessibilitySettings.isTrusted() else {
            return referenceApplications.map {
                AccessibilityReferenceSnapshot(
                    application: $0,
                    status: .skippedNoAXTrust,
                    metrics: nil,
                    samplePaths: []
                )
            }
        }

        return referenceApplications.map { sampleReferenceApp($0) }
    }

    private static func sampleReferenceApp(_ app: AccessibilityReferenceApplication) -> AccessibilityReferenceSnapshot {
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).first else {
            return AccessibilityReferenceSnapshot(
                application: app,
                status: .notRunning,
                metrics: nil,
                samplePaths: []
            )
        }

        let axApp = AXUIElementCreateApplication(running.processIdentifier)
        var focusedWindow: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        guard windowResult == .success, let windowValue = focusedWindow else {
            return AccessibilityReferenceSnapshot(
                application: app,
                status: .noFocusedWindow,
                metrics: nil,
                samplePaths: ["Spusť \(app.displayName) a nech jedno okno v popředí, pak audit zopakuj."]
            )
        }

        let windowElement = windowValue as! AXUIElement
        var collector = AXTreeCollector(limit: 400, maxDepth: 10)
        collector.walk(element: windowElement, path: app.displayName)
        return AccessibilityReferenceSnapshot(
            application: app,
            status: .sampled,
            metrics: collector.metrics,
            samplePaths: collector.labeledSamples.prefix(6).map(\.path)
        )
    }

    private static func saveReport(_ markdown: String) -> URL? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = reportDirectory.appendingPathComponent("accessibility-audit-\(stamp).md")
        do {
            try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            DiagnosticsLogger.log("Accessibility audit write failed: \(error.localizedDescription)")
            return nil
        }
    }

    @MainActor
    private static func surfaceName(for view: NSView) -> String {
        let typeName = String(describing: type(of: view))
        if typeName.contains("Permission") || typeName.contains("Launch") { return "Nastavení / onboarding" }
        if typeName.contains("Transcription") { return "Panel přepisu" }
        if typeName.contains("Learned") { return "Naučené termíny" }
        if typeName.contains("Overlay") || typeName.contains("Recording") { return "Overlay nahrávání" }
        if typeName.contains("WordCorrection") { return "Oprava slova" }
        return "UI"
    }
}

// MARK: - Models

struct AccessibilityReferenceApplication: Sendable {
    let bundleIdentifier: String
    let displayName: String
    let rationale: String
}

enum AccessibilityAuditSeverity: String, Sendable, Comparable {
    case critical
    case warning
    case info

    static func < (lhs: Self, rhs: Self) -> Bool {
        let order: [Self] = [.critical, .warning, .info]
        return (order.firstIndex(of: lhs) ?? 0) > (order.firstIndex(of: rhs) ?? 0)
    }
}

struct AccessibilityAuditFinding: Sendable {
    let severity: AccessibilityAuditSeverity
    let surface: String
    let path: String
    let issue: String
    let suggestion: String
}

enum AccessibilityReferenceSampleStatus: String, Sendable {
    case sampled
    case notRunning
    case noFocusedWindow
    case skippedNoAXTrust
}

struct AccessibilityReferenceMetrics: Sendable {
    let visitedNodes: Int
    let accessibilityElements: Int
    let labeledElements: Int
    let withHelp: Int
    let interactiveRoles: Int

    var labelCoverage: Double {
        guard accessibilityElements > 0 else { return 0 }
        return Double(labeledElements) / Double(accessibilityElements)
    }

    var helpCoverage: Double {
        guard accessibilityElements > 0 else { return 0 }
        return Double(withHelp) / Double(accessibilityElements)
    }
}

struct AccessibilityReferenceSnapshot: Sendable {
    let application: AccessibilityReferenceApplication
    let status: AccessibilityReferenceSampleStatus
    let metrics: AccessibilityReferenceMetrics?
    let samplePaths: [String]
}

/// Statický inventář povrchů appky — pomáhá pochopit, co audit nemusí vidět bez otevřeného okna.
struct AccessibilitySurfaceInventory: Sendable {
    let surfaces: [AccessibilitySurfaceEntry]

    static func current() -> AccessibilitySurfaceInventory {
        AccessibilitySurfaceInventory(surfaces: [
            .init(
                name: "Menu bar (stav + akce)",
                voiceOverNotes: "Status item má dynamický label dle LocuteState; oznámení stavu přes AccessibilitySupport.announce.",
                manualChecks: [
                    "Projdi celé menu šipkami — každá položka musí být srozumitelná bez vizuálního kontextu.",
                    "Vyzkoušej Začít/Ukončit diktování jen z menu.",
                    "Zkontroluj disabled položky — VoiceOver musí přečíst důvod (accessibilityHelp)."
                ]
            ),
            .init(
                name: "Overlay nahrávání (bez okna)",
                voiceOverNotes: "Panel NSPanel s title; stav jako label+value; živý náhled přepisu v announce.",
                manualChecks: [
                    "Drž hotkey a poslouchej oznámení při přechodu recording → transcribing → injecting.",
                    "Ověř, že overlay nekrade focus z cílové aplikace déle než nutné."
                ]
            ),
            .init(
                name: "Nastavení / oprávnění",
                voiceOverNotes: "Dlouhý onboarding text; badge stavů; tlačítka do System Settings.",
                manualChecks: [
                    "Všechny přepínače (model, hotkey, vzhled) musí mít jednoznačný label.",
                    "Test diktovací klávesy musí být čitelný jako živý stav."
                ]
            ),
            .init(
                name: "Panel přepisu + oprava slov",
                voiceOverNotes: "Klikacelná slova s confidence; popover opravy; legend v help textu.",
                manualChecks: [
                    "Naviguj po slovech s nízkou jistotou — help musí vysvětlit akci.",
                    "Popover: pole „Slovo z přepisu“ a „Správný tvar“."
                ]
            ),
            .init(
                name: "Push-to-talk (globální)",
                voiceOverNotes: "Primární cesta bez UI — uživatel VoiceOver musí znát klávesu z menu help.",
                manualChecks: [
                    "Ověř hint v menu baru a v Nastavení pro aktuální HotkeyPreference.",
                    "Chyba „špatná klávesa“ musí být slyšitelná přes announce."
                ]
            )
        ])
    }
}

struct AccessibilitySurfaceEntry: Sendable {
    let name: String
    let voiceOverNotes: String
    let manualChecks: [String]
}

// MARK: - AX tree sampling

private struct AXLabeledSample {
    let path: String
    let label: String
}

private struct AXTreeCollector {
    let limit: Int
    let maxDepth: Int
    var visited = 0
    var accessibilityElements = 0
    var labeledElements = 0
    var withHelp = 0
    var interactiveRoles = 0
    var labeledSamples: [AXLabeledSample] = []

    var metrics: AccessibilityReferenceMetrics {
        AccessibilityReferenceMetrics(
            visitedNodes: visited,
            accessibilityElements: accessibilityElements,
            labeledElements: labeledElements,
            withHelp: withHelp,
            interactiveRoles: interactiveRoles
        )
    }

    mutating func walk(element: AXUIElement, path: String, depth: Int = 0) {
        guard visited < limit, depth < maxDepth else { return }
        visited += 1

        var roleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
           let role = roleValue as? String {
            if ["AXButton", "AXTextField", "AXTextArea", "AXPopUpButton", "AXMenuItem", "AXCheckBox", "AXRadioButton"]
                .contains(role) {
                interactiveRoles += 1
            }
        }

        var ignored: CFTypeRef?
        let ignoredResult = AXUIElementCopyAttributeValue(element, "AXIgnored" as CFString, &ignored)
        let isIgnored = ignoredResult == .success && (ignored as? Bool) == true
        if !isIgnored {
            accessibilityElements += 1
            let label = axString(element, kAXTitleAttribute) ?? axString(element, kAXDescriptionAttribute) ?? axString(element, kAXRoleDescriptionAttribute) ?? ""
            if !label.isEmpty {
                labeledElements += 1
                if labeledSamples.count < 12 {
                    labeledSamples.append(.init(path: path, label: label))
                }
            }
            let help = axString(element, kAXHelpAttribute) ?? ""
            if !help.isEmpty { withHelp += 1 }
        }

        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let childArray = children as? [AXUIElement] else { return }
        for (index, child) in childArray.enumerated() {
            walk(element: child, path: "\(path) > child[\(index)]", depth: depth + 1)
        }
    }

    private func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}

// MARK: - Report builder (testable)

enum AccessibilityAuditReportBuilder {
    static func build(
        context: AccessibilityAuditEngine.AuditContext,
        inventory: AccessibilitySurfaceInventory,
        locuteFindings: [AccessibilityAuditFinding],
        referenceSnapshots: [AccessibilityReferenceSnapshot]
    ) -> String {
        var lines: [String] = []
        lines.append("# \(AppBrand.displayName) — analýza zpřístupnění (VoiceOver)")
        lines.append("")
        lines.append("Vygenerováno: \(isoTimestamp())")
        lines.append("Verze: \(context.appVersion)")
        lines.append("Bundle: `\(context.bundlePath)`")
        lines.append("AX důvěra (System Settings → Zpřístupnění): \(context.axTrusted ? "ano" : "ne")")
        lines.append("Otevřená okna v době auditu: \(context.openWindowTitles.isEmpty ? "žádná" : context.openWindowTitles.joined(separator: ", "))")
        lines.append("")

        let critical = locuteFindings.filter { $0.severity == .critical }
        let warnings = locuteFindings.filter { $0.severity == .warning }
        let infos = locuteFindings.filter { $0.severity == .info }

        lines.append("## Shrnutí")
        lines.append("")
        lines.append("| Metrika | Hodnota |")
        lines.append("|---------|---------|")
        lines.append("| Kritické nálezy | \(critical.count) |")
        lines.append("| Varování | \(warnings.count) |")
        lines.append("| Informace | \(infos.count) |")
        lines.append("| Referenční appky vzorkované | \(referenceSnapshots.filter { $0.status == .sampled }.count)/\(referenceSnapshots.count) |")
        lines.append("")

        lines.append(summaryParagraph(critical: critical.count, warnings: warnings.count, context: context))
        lines.append("")

        lines.append("## Proč je to důležité (malá appka → velká odpovědnost)")
        lines.append("")
        lines.append(
            """
            \(AppBrand.displayName) začínal jako menu bar utilita s minimálním UI. Každý nový povrch (Nastavení, panel přepisu, overlay, \
            globální hotkey) přidává vrstvu, kterou VoiceOver musí popsat **slovně**. Referenční aplikace níže ukazují, \
            jaký podíl prvků má v reálném UI popisek — to není cíl „100 %“, ale signál, kde máme mezery.
            """
        )
        lines.append("")

        lines.append("## Srovnání s referenčními aplikacemi")
        lines.append("")
        lines.append(referenceComparisonTable(locuteFindings: locuteFindings, snapshots: referenceSnapshots))
        lines.append("")
        lines.append(referenceDetailSection(snapshots: referenceSnapshots))
        lines.append("")

        lines.append("## Inventář povrchů \(AppBrand.displayName)")
        lines.append("")
        for entry in inventory.surfaces {
            lines.append("### \(entry.name)")
            lines.append("")
            lines.append(entry.voiceOverNotes)
            lines.append("")
            lines.append("**Ruční kontrola (VoiceOver ON):**")
            for check in entry.manualChecks {
                lines.append("- \(check)")
            }
            lines.append("")
        }

        lines.append("## Nálezy automatického průchodu UI")
        lines.append("")
        if locuteFindings.isEmpty {
            lines.append("_Žádné automatické nálezy — buď je UI v pořádku, nebo nebyla viditelná okna._")
        } else {
            lines.append(findingsSection(findings: critical, title: "Kritické"))
            lines.append(findingsSection(findings: warnings, title: "Varování"))
            lines.append(findingsSection(findings: infos, title: "Informace"))
        }
        lines.append("")

        lines.append("## Doporučený postup úprav (priorita)")
        lines.append("")
        lines.append(roadmap(critical: critical, warnings: warnings, context: context))
        lines.append("")

        lines.append("## Kontrolní seznam před vydáním")
        lines.append("")
        for item in releaseChecklist() {
            lines.append("- [ ] \(item)")
        }
        lines.append("")

        lines.append("---")
        lines.append("_Soubor uložen v `~/Library/Logs/\(AppBrand.storageDirectoryName)/`. Znovu spusť audit z menu po úpravách UI._")
        return lines.joined(separator: "\n")
    }

    // Exposed for tests
    static func summaryParagraph(critical: Int, warnings: Int, context: AccessibilityAuditEngine.AuditContext) -> String {
        if !context.axTrusted {
            return "**Pozor:** \(AppBrand.displayName) nemá povolené Zpřístupnění v System Settings — srovnání s jinými appkami přeskočeno. Referenční metriky vyplň po povolení oprávnění."
        }
        if critical > 0 {
            return "**Stav:** Jsou kritické mezery — VoiceOver uživatel může narazit na prvky bez jména nebo mimo strom. Oprav kritické položky dřív než vylepšuješ help texty."
        }
        if warnings > 0 {
            return "**Stav:** Základní navigace by měla fungovat, ale chybí kontext (help) u části ovládání. Doplň help u akcí, které nejsou zřejmé z labelu."
        }
        return "**Stav:** Automatický průchod nenašel závažné problémy na viditelném UI. Stejně proveď ruční kontrolu podle inventáře — zejména overlay a globální hotkey."
    }

    static func referenceComparisonTable(
        locuteFindings: [AccessibilityAuditFinding],
        snapshots: [AccessibilityReferenceSnapshot]
    ) -> String {
        let locuteElements = max(1, locuteFindings.count + 20)
        let locuteLabeled = locuteFindings.filter { !$0.issue.contains("bez label") }.count
        let locuteLabelRatio = Double(locuteLabeled) / Double(locuteElements)

        var lines: [String] = []
        lines.append("| Aplikace | Stav vzorku | Prvků (≈) | Podíl s popiskem | Podíl s nápovědou |")
        lines.append("|----------|-------------|-----------|------------------|-------------------|")
        lines.append(
            String(
                format: "| \(AppBrand.displayName) (viditelné UI) | audit | %d | %.0f %% (orientační) | — |",
                locuteElements,
                locuteLabelRatio * 100
            )
        )
        for snap in snapshots {
            let status = snap.status.rawValue
            if let m = snap.metrics {
                lines.append(
                    String(
                        format: "| %@ | %@ | %d | %.0f %% | %.0f %% |",
                        snap.application.displayName,
                        status,
                        m.accessibilityElements,
                        m.labelCoverage * 100,
                        m.helpCoverage * 100
                    )
                )
            } else {
                lines.append("| \(snap.application.displayName) | \(status) | — | — | — |")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func referenceDetailSection(snapshots: [AccessibilityReferenceSnapshot]) -> String {
        var blocks: [String] = []
        for snap in snapshots {
            blocks.append("### \(snap.application.displayName)")
            blocks.append("")
            blocks.append("- Bundle: `\(snap.application.bundleIdentifier)`")
            blocks.append("- Proč je v sadě: \(snap.application.rationale)")
            blocks.append("- Stav: \(snap.status.rawValue)")
            if let m = snap.metrics {
                blocks.append("- Vzorkováno uzlů: \(m.visitedNodes), accessibility prvků: \(m.accessibilityElements)")
                blocks.append("- Interaktivní role (button, text field, …): \(m.interactiveRoles)")
            }
            if !snap.samplePaths.isEmpty {
                blocks.append("- Příklady popsaných prvků:")
                for p in snap.samplePaths {
                    blocks.append("  - `\(p)`")
                }
            }
            blocks.append("")
        }
        return blocks.joined(separator: "\n")
    }

    static func findingsSection(findings: [AccessibilityAuditFinding], title: String) -> String {
        guard !findings.isEmpty else { return "" }
        var lines = ["### \(title)", ""]
        for (index, f) in findings.enumerated() {
            lines.append("\(index + 1). **[\(f.surface)]** `\(f.path)`")
            lines.append("   - Problém: \(f.issue)")
            lines.append("   - Návrh: \(f.suggestion)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func roadmap(critical: [AccessibilityAuditFinding], warnings: [AccessibilityAuditFinding], context: AccessibilityAuditEngine.AuditContext) -> String {
        var steps: [String] = []
        var n = 1
        if !context.axTrusted {
            steps.append("\(n). Povolit \(AppBrand.displayName) v Nastavení → Soukromí → Zpřístupnění (jinak nelze vzorkovat referenční appky).")
            n += 1
        }
        if !critical.isEmpty {
            steps.append("\(n). Opravit všechny **kritické** nálezy (prvky bez label / mimo strom / ikonová tlačítka).")
            n += 1
        }
        steps.append("\(n). Otevřít všechna okna \(AppBrand.displayName) (Nastavení, Naučené termíny, panel přepisu) a audit zopakovat.")
        n += 1
        if !warnings.isEmpty {
            steps.append("\(n). Doplň `accessibilityHelp` u varování — zejména menu a přepínače v Nastavení.")
            n += 1
        }
        steps.append("\(n). Spusť referenční appky (Nastavení, Poznámky, …), přepni je do popředí, znovu audit — doplní metriky.")
        n += 1
        steps.append("\(n). Ruční VoiceOver průchod podle inventáře povrchů (hotkey, overlay, vložení textu).")
        n += 1
        steps.append("\(n). Po úpravách commitni změny v `AccessibilitySupport` / konkrétních view controllerech a přilož nový audit do PR.")
        return steps.joined(separator: "\n")
    }

    static func releaseChecklist() -> [String] {
        [
            "Menu bar: stav čitelný při idle / recording / transcribing / error",
            "Globální hotkey funguje s VoiceOver (uživatel slyší špatnou klávesu)",
            "Overlay: stav nahrávání bez nutnosti vidět obrazovku",
            "Nastavení: všechny přepínače a pickery s label + help",
            "Panel přepisu: slova s nízkou jistotou mají srozumitelný help",
            "Žádné čistě ikonové tlačítko bez accessibility label",
            "Dekorativní prvky nejsou v accessibility stromu",
            "Audit z referenčních appek proběhl s AX trust"
        ]
    }

    private static func isoTimestamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }
}

// MARK: - NSView helpers

private extension NSView {
    var axShortDescription: String {
        let type = String(describing: type(of: self))
        if let id = accessibilityIdentifier(), !id.isEmpty {
            return "\(type)#\(id)"
        }
        if let label = accessibilityLabel(), !label.isEmpty {
            return "\(type) «\(label.prefix(24))»"
        }
        return type
    }

    var userInteractionEnabled: Bool {
        if let control = self as? NSControl { return control.isEnabled }
        return window?.ignoresMouseEvents == false
    }
}
