import Foundation

/// Když je zapnuto, externí vložení textu vyžaduje potvrzení v okně Locute (Aqua-style review).
enum DictationReviewPreference {
    private static let storageKey = "reviewBeforePaste"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: storageKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: storageKey)
            NotificationCenter.default.post(name: .locuteReviewPreferenceChanged, object: nil)
        }
    }
}

extension Notification.Name {
    static let locuteReviewPreferenceChanged = Notification.Name("LocuteReviewPreferenceChanged")
}
