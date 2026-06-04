import Combine
import Foundation

/// Viditelný stav volitelného doladění textu (bez technických detailů modelu).
@MainActor
final class PostProcessingReadiness: ObservableObject {
    enum Phase: Equatable {
        case off
        case preparing(progress: Double)
        case ready
        case unavailable
    }

    @Published private(set) var phase: Phase = .off

    var isPreparing: Bool {
        if case .preparing = phase { return true }
        return false
    }

    var isReady: Bool { phase == .ready }

    /// Řádek v menu baru, pokud má uživatel vidět průběh přípravy.
    var menuStatusLine: String? {
        switch phase {
        case .off, .ready:
            return nil
        case .preparing(let progress):
            let pct = Int((progress * 100).rounded())
            return "Připravuji formátování (\(pct) %)"
        case .unavailable:
            return "Formátování nedostupné"
        }
    }

    func syncWithPreference() {
        if PostProcessingPreference.isEnabled {
            if case .off = phase {
                phase = .preparing(progress: 0)
            }
        } else {
            phase = .off
        }
    }

    func beganPreparing() {
        guard PostProcessingPreference.isEnabled else {
            phase = .off
            return
        }
        phase = .preparing(progress: 0)
    }

    func updateProgress(_ progress: Double) {
        guard PostProcessingPreference.isEnabled else {
            phase = .off
            return
        }
        let clamped = min(0.99, max(0, progress))
        phase = .preparing(progress: clamped)
    }

    func becameReady() {
        phase = PostProcessingPreference.isEnabled ? .ready : .off
    }

    func becameUnavailable() {
        phase = PostProcessingPreference.isEnabled ? .unavailable : .off
    }

    func turnedOff() {
        phase = .off
    }
}
