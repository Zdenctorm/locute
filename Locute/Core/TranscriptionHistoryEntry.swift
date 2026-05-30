import Foundation

struct TranscriptionHistoryEntry: Equatable, Codable {
    let id: UUID
    let recordedAt: Date
    let text: String
    let words: [WordToken]
    let audioCacheURL: URL?
    let targetAppBundleID: String?

    init(
        id: UUID = UUID(),
        recordedAt: Date,
        text: String,
        words: [WordToken] = [],
        audioCacheURL: URL? = nil,
        targetAppBundleID: String? = nil
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.text = text
        self.words = words
        self.audioCacheURL = audioCacheURL
        self.targetAppBundleID = targetAppBundleID
    }
}

struct WordToken: Equatable, Codable, Sendable {
    let text: String
    /// 0…1, 1 = Whisper si byl jistý. Spočítáno z `WordTiming.probability` nebo
    /// fallback `exp(mean(tokenLogProbs))` pro slovo.
    let confidence: Float
    /// Pokud byl text nahrazen post-procesem ze slovníku, originál Whisper výstupu.
    let originalText: String?

    init(text: String, confidence: Float, originalText: String? = nil) {
        self.text = text
        self.confidence = confidence
        self.originalText = originalText
    }
}
