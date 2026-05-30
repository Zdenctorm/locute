import AppKit

@MainActor
enum AppWindowPresenter {
    /// Activates Locute and brings it to front. Call only when the user explicitly requested
    /// to interact with a Locute window (e.g. permissions setup).
    static func activateApp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Shows a window without stealing focus from the currently active app.
    static func present(_ window: NSWindow?) {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
