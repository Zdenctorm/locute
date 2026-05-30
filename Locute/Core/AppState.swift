import Combine
import Foundation
import os

struct ModelDownloadProgress: Equatable, Sendable {
    /// Legacy estimate (large-v3); nové modely používají `TranscriptionModelPreference.expectedDownloadBytes`.
    static let whisperLargeV3TotalBytes: Int64 = 3_090_319_899

    let fraction: Double
    let downloadedBytes: Int64
    let totalBytes: Int64

    static var empty: ModelDownloadProgress {
        ModelDownloadProgress(
            fraction: 0,
            downloadedBytes: 0,
            totalBytes: TranscriptionModelPreference.current.expectedDownloadBytes
        )
    }
}

enum LocuteState: Equatable {
    case launching
    case permissionsNeeded
    case modelDownloading(ModelDownloadProgress)
    case modelLoading
    case idle
    case recording
    case transcribing
    case injecting
    case error(String)

    var displayText: String {
        switch self {
        case .launching:
            return "Spouštím"
        case .permissionsNeeded:
            return "Chybí oprávnění"
        case .modelDownloading:
            return "Připravuji model"
        case .modelLoading:
            return "Načítám model"
        case .idle:
            return "Připraveno"
        case .recording:
            return "Nahrávám"
        case .transcribing:
            return "Přepisuji"
        case .injecting:
            return "Vkládám text"
        case .error:
            return "Vyžaduje pozornost"
        }
    }
}

@MainActor
final class AppStateMachine: ObservableObject {
    @Published private(set) var state: LocuteState = .launching

    private let logger = Logger(subsystem: "com.example.locute", category: "state")

    var isRecording: Bool { state == .recording }
    var isReady: Bool { state == .idle }

    /// Diktování lze spustit i během stahování/načítání modelu — přepis počká na model na konci.
    var canStartDictation: Bool {
        switch state {
        case .idle, .modelDownloading, .modelLoading:
            return true
        default:
            return false
        }
    }

    var blocksDictation: Bool {
        switch state {
        case .injecting, .transcribing, .modelLoading, .launching:
            return true
        case .modelDownloading, .permissionsNeeded, .idle, .recording, .error:
            return false
        }
    }

    func transition(to newState: LocuteState) {
        logger.info("State changed to \(newState.displayText, privacy: .public)")
        state = newState
    }
}
