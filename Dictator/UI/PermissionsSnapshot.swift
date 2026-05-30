import AVFoundation
import Cocoa

enum PermissionCheckState: Equatable {
    case allowed
    case missing
    case needsReview

    var label: String {
        switch self {
        case .allowed: return "Povoleno"
        case .missing: return "Chybí"
        case .needsReview: return "Zkontrolujte"
        }
    }

    var color: NSColor {
        switch self {
        case .allowed: return AppTheme.Color.success
        case .missing: return AppTheme.Color.warning
        case .needsReview: return AppTheme.Color.danger
        }
    }
}

struct PermissionsSnapshot: Equatable {
    let microphone: PermissionCheckState
    let accessibility: PermissionCheckState
    let inputMonitoring: PermissionCheckState

    var allGranted: Bool {
        microphone == .allowed && accessibility == .allowed && inputMonitoring == .allowed
    }
}

enum PermissionsSnapshotProvider {
    static var current: PermissionsSnapshot {
        PermissionsSnapshot(
            microphone: microphoneState,
            accessibility: AccessibilitySettings.isTrusted() ? .allowed : .needsReview,
            inputMonitoring: InputMonitoringSettings.isGranted() ? .allowed : .needsReview
        )
    }

    static var isMicrophoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func isAccessibilityGranted(prompt: Bool) -> Bool {
        if prompt {
            return AccessibilitySettings.requestTrustPrompt()
        }
        return AccessibilitySettings.isTrusted()
    }

    private static var microphoneState: PermissionCheckState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .allowed
        case .notDetermined:
            return .missing
        case .denied, .restricted:
            return .needsReview
        @unknown default:
            return .needsReview
        }
    }
}
