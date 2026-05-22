import AVFoundation
import Foundation
import WhisperKit
import os

struct TranscriptionMetrics: Sendable {
    let audioDurationSeconds: Float
    let decodeDurationSeconds: Double
    let timeToFirstPartialSeconds: Double?
    let usedStreaming: Bool

    var realTimeFactor: Double {
        guard audioDurationSeconds > 0 else { return 0 }
        return decodeDurationSeconds / Double(audioDurationSeconds)
    }
}

actor TranscriptionEngine {
    private var whisperKit: WhisperKit?
    private var loadedModelVariant: String?
    private let modelRepository = "argmaxinc/whisperkit-coreml"
    private let language = "cs"
    private let logger = Logger(subsystem: "com.example.dictator", category: "transcription")

    private var vocabulary: VocabularyDictionary = .empty
    private var streamingSession: StreamingTranscriptionSession?
    private var streamingStartedAt: Date?
    private var firstPartialAt: Date?

    func applyVocabulary(_ snapshot: VocabularyDictionary) {
        vocabulary = snapshot
        DiagnosticsLogger.log("Vocabulary applied: entries=\(snapshot.entries.count)")
    }

    var isLoaded: Bool { whisperKit != nil }

    var loadedVariantName: String? { loadedModelVariant }

    func unload() {
        whisperKit = nil
        loadedModelVariant = nil
        streamingSession = nil
        DiagnosticsLogger.log("WhisperKit model unloaded")
    }

    func load(progressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void) async throws {
        let preference = TranscriptionModelPreference.current
        let modelName = preference.whisperKitVariant
        let expectedBytes = preference.expectedDownloadBytes

        if let whisperKit, loadedModelVariant == modelName {
            progressHandler(ModelDownloadProgress(
                fraction: 1.0,
                downloadedBytes: expectedBytes,
                totalBytes: expectedBytes
            ))
            return
        }

        unload()

        let cacheRoot = ModelDownloadMonitor.cacheRoot(for: modelRepository)
        progressHandler(ModelDownloadMonitor.snapshot(for: cacheRoot, totalBytes: expectedBytes))
        DiagnosticsLogger.log("WhisperKit model load requested. model=\(modelName)")

        let progressTask = Task {
            let startedAt = Date()
            var lastLoggedMinute = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                progressHandler(ModelDownloadMonitor.snapshot(for: cacheRoot, totalBytes: expectedBytes))

                let elapsedMinute = Int(Date().timeIntervalSince(startedAt) / 60)
                if elapsedMinute > lastLoggedMinute {
                    lastLoggedMinute = elapsedMinute
                    DiagnosticsLogger.log(
                        "WhisperKit model load still running. model=\(modelName), elapsedMinutes=\(elapsedMinute)"
                    )
                }
            }
        }

        do {
            let modelFolder = try await WhisperKit.download(
                variant: modelName,
                from: modelRepository
            ) { progress in
                progressHandler(
                    ModelDownloadMonitor.snapshot(for: cacheRoot, progress: progress, totalBytes: expectedBytes)
                )
            }

            progressHandler(ModelDownloadMonitor.snapshot(for: cacheRoot, fraction: 1.0, totalBytes: expectedBytes))

            whisperKit = try await WhisperKit(
                WhisperKitConfig(
                    modelFolder: modelFolder.path,
                    verbose: false,
                    logLevel: .none,
                    prewarm: true,
                    load: true,
                    download: false
                )
            )
            loadedModelVariant = modelName
            progressTask.cancel()
            progressHandler(ModelDownloadMonitor.snapshot(for: cacheRoot, fraction: 1.0, totalBytes: expectedBytes))
            logger.info("WhisperKit model loaded")
            DiagnosticsLogger.log("WhisperKit model loaded (\(modelName))")
        } catch {
            progressTask.cancel()
            DiagnosticsLogger.log("WhisperKit model load error: \(error.localizedDescription)")
            throw error
        }
    }

    func beginStreaming() async throws {
        guard let whisperKit else { throw TranscriptionError.modelNotLoaded }
        let promptTokens = vocabularyPromptTokens(using: whisperKit)
        streamingSession = try StreamingTranscriptionSession(
            whisperKit: whisperKit,
            language: language,
            promptTokens: promptTokens
        )
        streamingStartedAt = Date()
        firstPartialAt = nil
        DiagnosticsLogger.log("Streaming transcription session started")
    }

    func endStreaming() {
        streamingSession = nil
        streamingStartedAt = nil
        firstPartialAt = nil
    }

    /// Partial přepis během nahrávání; vrací náhled pro overlay.
    func streamingPreview(for samples: [Float]) async -> StreamingPreview? {
        guard let session = streamingSession else { return nil }
        if let preview = await session.processSamplesIfNeeded(samples) {
            if firstPartialAt == nil {
                firstPartialAt = Date()
            }
            return preview
        }
        return session.preview(from: samples)
    }

    func transcribe(
        audioSamples: [Float],
        peakRMS: Float,
        audioURL: URL? = nil
    ) async throws -> (raw: RawTranscription, metrics: TranscriptionMetrics) {
        let decodeStart = Date()
        let duration = Float(audioSamples.count) / Float(WhisperKit.sampleRate)

        guard peakRMS >= 0.002 else {
            DiagnosticsLogger.log("Transcription skipped: audio too quiet")
            throw TranscriptionError.audioTooQuiet
        }

        let raw: RawTranscription
        var usedStreaming = false

        if let session = streamingSession {
            let (segments, streamed) = try await session.finish(samples: audioSamples)
            endStreaming()
            if streamed, !segments.isEmpty {
                usedStreaming = true
                raw = try Self.rawTranscription(from: segments)
            } else {
                raw = try await batchTranscribe(samples: audioSamples)
            }
        } else {
            raw = try await batchTranscribe(samples: audioSamples)
        }

        _ = audioURL

        let decodeDuration = Date().timeIntervalSince(decodeStart)
        let ttft: Double?
        if let streamingStartedAt, let firstPartialAt {
            ttft = firstPartialAt.timeIntervalSince(streamingStartedAt)
        } else {
            ttft = nil
        }

        let metrics = TranscriptionMetrics(
            audioDurationSeconds: duration,
            decodeDurationSeconds: decodeDuration,
            timeToFirstPartialSeconds: ttft,
            usedStreaming: usedStreaming
        )
        DiagnosticsLogger.log(
            "Transcription metrics: audio=\(String(format: "%.2f", duration))s decode=\(String(format: "%.2f", decodeDuration))s rtf=\(String(format: "%.2f", metrics.realTimeFactor)) ttft=\(ttft.map { String(format: "%.2f", $0) } ?? "n/a") streaming=\(usedStreaming)"
        )

        return (raw, metrics)
    }

    /// Kompatibilní vstup z WAV na disku — preferuje in-memory vzorky pokud jsou k dispozici.
    func transcribe(audioURL: URL, peakRMS: Float, audioSamples: [Float]? = nil) async throws -> RawTranscription {
        let samples: [Float]
        if let audioSamples, !audioSamples.isEmpty {
            samples = audioSamples
        } else {
            samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
        }
        let result = try await transcribe(audioSamples: samples, peakRMS: peakRMS, audioURL: audioURL)
        return result.raw
    }

    private func batchTranscribe(samples: [Float]) async throws -> RawTranscription {
        guard let whisperKit else { throw TranscriptionError.modelNotLoaded }

        let promptTokens = vocabularyPromptTokens(using: whisperKit)
        let options = DecodingOptions(
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

        let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
        let segments = results.flatMap(\.segments)
        return try Self.rawTranscription(from: segments)
    }

    private static func rawTranscription(from segments: [TranscriptionSegment]) throws -> RawTranscription {
        let raw = segments
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let sanitized = TranscriptionSanitizer.sanitized(raw) else {
            DiagnosticsLogger.log("Transcription empty after sanitization (hallucination)")
            throw TranscriptionError.hallucinatedTranscript(raw)
        }

        let words = extractWordTokens(from: segments, fallbackText: sanitized)
        let duration = segments.last.map { Float($0.end) } ?? 0
        return RawTranscription(rawText: sanitized, words: words, durationSeconds: duration)
    }

    private static func extractWordTokens(
        from segments: [TranscriptionSegment],
        fallbackText: String
    ) -> [WordToken] {
        var tokens: [WordToken] = []
        var hasAnyWordTiming = false

        for segment in segments {
            if let words = segment.words, !words.isEmpty {
                hasAnyWordTiming = true
                for timing in words {
                    let trimmed = timing.word.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { continue }
                    let probability = max(0, min(1, timing.probability))
                    tokens.append(WordToken(text: trimmed, confidence: probability))
                }
            } else {
                let segmentConfidence = max(0, min(1, Foundation.exp(segment.avgLogprob)))
                let pieces = segment.text
                    .split(whereSeparator: { $0.isWhitespace })
                    .map(String.init)
                for piece in pieces {
                    let trimmed = piece.trimmingCharacters(in: .punctuationCharacters)
                    guard !trimmed.isEmpty else { continue }
                    tokens.append(WordToken(text: trimmed, confidence: segmentConfidence))
                }
            }
        }

        if !hasAnyWordTiming && tokens.isEmpty {
            let pieces = fallbackText
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init)
            for piece in pieces {
                let trimmed = piece.trimmingCharacters(in: .punctuationCharacters)
                guard !trimmed.isEmpty else { continue }
                tokens.append(WordToken(text: trimmed, confidence: 0.5))
            }
        }

        return tokens
    }

    private func vocabularyPromptTokens(using whisperKit: WhisperKit) -> [Int]? {
        guard !vocabulary.isEmpty else { return nil }
        guard let tokenizer = whisperKit.tokenizer else { return nil }
        let prompt = vocabulary.whisperPrompt
        guard !prompt.isEmpty else { return nil }

        var tokens = tokenizer.encode(text: " " + prompt)
        let maxPromptTokens = 200
        if tokens.count > maxPromptTokens {
            tokens = Array(tokens.suffix(maxPromptTokens))
        }
        DiagnosticsLogger.log("Vocabulary prompt tokens: count=\(tokens.count), preview=\(prompt.prefix(60))")
        return tokens
    }
}

private enum ModelDownloadMonitor {
    static func cacheRoot(for repository: String) -> URL {
        let repo = HubApiWrapper.Repo(id: repository, type: .models)
        return HubApiWrapper.shared.localRepoLocation(repo)
    }

    static func snapshot(
        for cacheRoot: URL,
        progress: Progress? = nil,
        fraction forcedFraction: Double? = nil,
        totalBytes: Int64? = nil
    ) -> ModelDownloadProgress {
        let total = totalBytes ?? TranscriptionModelPreference.current.expectedDownloadBytes
        let downloadedBytes = min(directorySize(at: cacheRoot), total)
        let diskFraction = total > 0 ? Double(downloadedBytes) / Double(total) : 0
        let callbackFraction = progress?.fractionCompleted ?? 0
        let fraction = forcedFraction ?? max(diskFraction, callbackFraction)

        return ModelDownloadProgress(
            fraction: min(max(fraction, 0), 1),
            downloadedBytes: downloadedBytes,
            totalBytes: total
        )
    }

    private static func directorySize(at url: URL) -> Int64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: []
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize else {
                continue
            }
            total += Int64(fileSize)
        }
        return total
    }
}

struct RawTranscription {
    let rawText: String
    let words: [WordToken]
    let durationSeconds: Float
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case audioTooQuiet
    case hallucinatedTranscript(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "WhisperKit model is not loaded."
        case .audioTooQuiet:
            return "Audio is too quiet."
        case .hallucinatedTranscript:
            return "Whisper produced a known silence hallucination."
        }
    }
}
