import Foundation

/// Pure ordering for clipboard / Accessibility paste attempts — testable without CGEvent.
enum PasteInsertionStep: String, CaseIterable {
    case commandV
    case accessibility

    /// When `prefersCommandVFirst` is true (Electron browsers, web wrappers, …): try ⌘V before AX.
    static func ordered(prefersCommandVFirst: Bool) -> [PasteInsertionStep] {
        prefersCommandVFirst ? [.commandV, .accessibility] : [.accessibility, .commandV]
    }
}

/// Bundle IDs that reliably paste better via simulated ⌘V than raw AX writes.
///
/// Dva typy "preferuj Cmd+V":
/// 1. **Electron / web wrappers** (Discord, VSCode, browsery, …) — AX zápis tam funguje
///    nedeterministicky, Cmd+V je spolehlivější.
/// 2. **Terminály** — AX `setAttributeValue` na kAXSelectedText vrací success, ale shell text
///    input je mimo Cocoa text view, takže text reálně nikdy nedorazí. Cmd+V projde přes
///    standardní clipboard paste flow, který terminály respektují.
enum CommandVPastePreferringBundles {
    private static let commandVPreferredBundleIDs: Set<String> = [
        // Electron / web-wrapper chat apps
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "com.microsoft.VSCode",
        // Cursor (ToDesktop / Electron) — AX reports success but Monaco never shows the text.
        "com.todesktop.230313mzl4w4u92",
        "com.microsoft.teams2",
        "com.tdesktop.Telegram",
        "com.spotify.client",

        // Browsers
        "com.google.Chrome",
        "com.brave.Browser",
        "org.mozilla.firefox",
        "com.apple.Safari",
        "company.thebrowser.Browser",

        // Design / productivity Electron apps
        "com.figma.Desktop",
        "com.notion.id",
        "com.linear",
        "com.openai.chat",

        // Terminals — AX is a black hole for these; clipboard paste works.
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "co.zeit.hyper",
        "dev.warp.Warp-Stable",
        "com.github.wez.wezterm",
        "io.alacritty",
        "net.kovidgoyal.kitty",
        "org.gnu.Emacs",
        "com.sublimemerge",
    ]

    static func prefersCommandV(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        if commandVPreferredBundleIDs.contains(bundleID) { return true }
        // ToDesktop-wrapped Electron apps (Cursor and similar) do not use "electron" in the bundle ID.
        if bundleID.hasPrefix("com.todesktop.") { return true }
        if bundleID.hasPrefix("com.anysphere.") { return true }
        if bundleID.contains("electron") { return true }
        if bundleID.hasPrefix("com.google.Chrome") { return true }
        // Heuristika: nezachycené terminálové appky často obsahují "term" v bundle ID.
        let lower = bundleID.lowercased()
        if lower.contains("terminal") || lower.contains("iterm") || lower.contains("wezterm") {
            return true
        }
        return false
    }
}
