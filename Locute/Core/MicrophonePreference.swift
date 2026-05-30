import AVFoundation
import Foundation

enum MicrophonePreference {
    private static let deviceUIDKey = "preferredMicrophoneDeviceUID"

    static var selectedDeviceUID: String? {
        get { UserDefaults.standard.string(forKey: deviceUIDKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: deviceUIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: deviceUIDKey)
            }
            NotificationCenter.default.post(name: .locuteMicrophonePreferenceChanged, object: nil)
        }
    }

    static func discoveredDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    static func resolvedDevice() -> AVCaptureDevice? {
        if let uid = selectedDeviceUID,
           let match = discoveredDevices().first(where: { $0.uniqueID == uid }) {
            return match
        }
        return AVCaptureDevice.default(for: .audio)
    }
}

extension Notification.Name {
    static let locuteMicrophonePreferenceChanged = Notification.Name("LocuteMicrophonePreferenceChanged")
}
