import Cocoa
import Foundation

enum AppAppearancePreference {
    private static let showInDockKey = "showInDock"

    /// Výchozí: skrýt ikonu v Docku (čistá menu bar appka).
    static var showInDock: Bool {
        get {
            if UserDefaults.standard.object(forKey: showInDockKey) == nil {
                return false
            }
            return UserDefaults.standard.bool(forKey: showInDockKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: showInDockKey)
            applyActivationPolicy()
            NotificationCenter.default.post(name: .locuteAppearancePreferenceChanged, object: nil)
        }
    }

    static func applyActivationPolicy() {
        let app = NSApplication.shared
        if showInDock {
            app.setActivationPolicy(.regular)
        } else {
            app.setActivationPolicy(.accessory)
        }
    }
}

extension Notification.Name {
    static let locuteAppearancePreferenceChanged = Notification.Name("LocuteAppearancePreferenceChanged")
}
