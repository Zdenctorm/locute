import Cocoa

@main
struct LocuteMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()

        app.delegate = delegate
        AppAppearancePreference.applyActivationPolicy()
        app.run()
    }
}
