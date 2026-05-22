import Foundation
import WhisperKit

/// Náhled průběžného přepisu pro overlay (potvrzený + návrh).
struct StreamingPreview: Equatable, Sendable {
    let confirmedText: String
    let draftText: String

    var displayText: String {
        let confirmed = confirmedText.trimmingCharacters(in: .whitespaces)
        let draft = draftText.trimmingCharacters(in: .whitespaces)
        if confirmed.isEmpty { return draft }
        if draft.isEmpty { return confirmed }
        return "\(confirmed) \(draft)"
    }
}

/// Stateful streamovací přepis během držení diktovací klávesy (logika inspirovaná AudioStreamTranscriber).
final class StreamingTranscriptionSession: @unchecked Sendable {
    private let whisperKit: WhisperKit
    private let language: String
    private let promptTokens: [Int]?
    private let requiredSegmentsForConfirmation: Int
    private let minNewAudioSeconds: Float = 1.0
    private let voiceRMSThreshold: Float = 0.003

    private var confirmedSegments: [TranscriptionSegment] = []
    private var unconfirmedSegments: [TranscriptionSegment] = []
    private var lastConfirmedSegmentEndSeconds: Float = 0
    private var lastTranscribedSampleCount = 0
    private var isTranscribing = false
    private var firstPartialLogged = false

    private let transcribeTask: TranscribeTask

    init(
        whisperKit: WhisperKit,
        language: String,
        promptTokens: [Int]?,
        requiredSegmentsForConfirmation: Int = 2
    ) throws {
        guard let tokenizer = whisperKit.tokenizer else {
            throw TranscriptionError.modelNotLoaded
        }
        self.whisperKit = whisperKit
        self.language = language
        self.promptTokens = promptTokens
        self.requiredSegmentsForConfirmation = requiredSegmentsForConfirmation
        self.transcribeTask = TranscribeTask(
            currentTimings: TranscriptionTimings(),
            progress: Progress(),
            audioProcessor: whisperKit.audioProcessor,
            audioEncoder: whisperKit.audioEncoder,
            featureExtractor: whisperKit.featureExtractor,
            segmentSeeker: whisperKit.segmentSeeker,
            textDecoder: whisperKit.textDecoder,
            tokenizer: tokenizer
        )
    }

    func preview(from samples: [Float]) -> StreamingPreview {
        StreamingPreview(
            confirmedText: text(from: confirmedSegments),
            draftText: text(from: unconfirmedSegments)
        )
    }

    /// Spustí partial decode pokud je dost nového audia a není jiný decode aktivní.
    func processSamplesIfNeeded(_ samples: [Float]) async -> StreamingPreview? {
        guard !isTranscribing else { return nil }

        let newSamples = samples.count - lastTranscribedSampleCount
        let newSeconds = Float(newSamples) / Float(WhisperKit.sampleRate)
        guard newSeconds >= minNewAudioSeconds else { return nil }
        guard hasVoice(in: samples) else { return nil }

        isTranscribing = true
        defer { isTranscribing = false }

        do {
            try await transcribeBuffer(samples)
            lastTranscribedSampleCount = samples.count
            if !firstPartialLogged {
                firstPartialLogged = true
                DiagnosticsLogger.log("Streaming: first partial transcript available")
            }
            return preview(from: samples)
        } catch {
            DiagnosticsLogger.log("Streaming partial failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Finální sloučení segmentů; případně krátký tail pass pokud přibylo audio od posledního partial.
    func finish(samples: [Float]) async throws -> (segments: [TranscriptionSegment], usedStreaming: Bool) {
        if samples.count > lastTranscribedSampleCount, hasVoice(in: samples) {
            isTranscribing = true
            defer { isTranscribing = false }
            try await transcribeBuffer(samples)
            lastTranscribedSampleCount = samples.count
        }

        let allSegments = confirmedSegments + unconfirmedSegments
        let usedStreaming = !allSegments.isEmpty
        return (allSegments, usedStreaming)
    }

    private func transcribeBuffer(_ samples: [Float]) async throws {
        var options = baseDecodingOptions()
        options.clipTimestamps = [lastConfirmedSegmentEndSeconds]

        let result = try await transcribeTask.run(audioArray: samples, decodeOptions: options)
        mergeSegments(result.segments)
    }

    private func mergeSegments(_ segments: [TranscriptionSegment]) {
        guard !segments.isEmpty else { return }

        if segments.count > requiredSegmentsForConfirmation {
            let confirmCount = segments.count - requiredSegmentsForConfirmation
            let toConfirm = Array(segments.prefix(confirmCount))
            let remaining = Array(segments.suffix(requiredSegmentsForConfirmation))

            if let last = toConfirm.last, last.end > lastConfirmedSegmentEndSeconds {
                lastConfirmedSegmentEndSeconds = last.end
                confirmedSegments.append(contentsOf: toConfirm)
            } else if toConfirm.isEmpty == false, confirmedSegments.isEmpty {
                confirmedSegments.append(contentsOf: toConfirm)
            }
            unconfirmedSegments = remaining
        } else {
            unconfirmedSegments = segments
        }
    }

    private func baseDecodingOptions() -> DecodingOptions {
        DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0.0,
            temperatureIncrementOnFallback: 0.2,
            temperatureFallbackCount: 1,
            usePrefillPrompt: true,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            wordTimestamps: false,
            promptTokens: promptTokens,
            suppressBlank: true,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            noSpeechThreshold: 0.75
        )
    }

    private func hasVoice(in samples: [Float]) -> Bool {
        let window = min(samples.count, Int(WhisperKit.sampleRate))
        guard window > Int(WhisperKit.sampleRate / 10) else { return false }
        let slice = samples.suffix(window)
        var sum: Float = 0
        for sample in slice {
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(slice.count))
        return rms >= voiceRMSThreshold
    }

    private func text(from segments: [TranscriptionSegment]) -> String {
        segments
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
