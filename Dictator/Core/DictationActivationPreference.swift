import Foundation

enum DictationActivationMode: String, CaseIterable, Sendable {
    case pushToTalk
    case toggle

    var label: String {
        switch self {
        case .pushToTalk: return "Podrž a mluv (push-to-talk)"
        case .toggle: return "Stiskni pro start / znovu pro konec"
        }
    }

    var detail: String {
        switch self {
        case .pushToTalk:
            return "Drž diktovací klávesu, mluv, pusť — přepis se spustí po puštění."
        case .toggle:
            return "První stisk začne nahrávání, druhý stisk ukončí (nemusíš držet klávesu)."
        }
    }
}

enum DictationActivationPreference {
    private static let storageKey = "dictationActivationMode"

    static var current: DictationActivationMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: storageKey),
                  let value = DictationActivationMode(rawValue: raw) else {
                return .pushToTalk
            }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
            NotificationCenter.default.post(name: .dictatorActivationModeChanged, object: nil)
        }
    }
}

extension Notification.Name {
    static let dictatorActivationModeChanged = Notification.Name("DictatorActivationModeChanged")
}
