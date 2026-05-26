import Foundation
import MLXLMCommon
import MLXLLM
import os

/// Lokální LLM post-procesor pro opravu Whisper přepisů.
///
/// Přidává interpunkci, opravuje kapitalizaci a normalizuje ALL-CAPS slova.
/// Funguje výhradně offline na Apple Silicon (Neural Engine + GPU).
/// Celý životní cyklus je actor-isolated — žádný stav není přístupný z jiných vláken.
actor PostProcessingEngine {

    // MARK: - State

    enum State: Equatable {
        case idle
        case downloading
        case loading
        case ready
        case failed(String)
    }

    private(set) var state: State = .idle
    private var container: ModelContainer?
    private let logger = Logger(subsystem: "com.example.dictator", category: "postprocessing")

    var isLoaded: Bool { state == .ready }

    // MARK: - System prompt

    private static let systemPrompt = """
        Jsi asistent pro opravu přepisu řeči v češtině. \
        Přidej interpunkci (tečky, čárky, otazníky) a velká písmena na začátku vět. \
        Zkratky jako KYC, AML, API, SEPA, EUR, PDF, HTML, JSON, REST nech velkými. \
        Ostatní slova psaná celá velkými písmeny normalizuj na lowercase. \
        Vrať POUZE opravený text — bez uvozovek, bez vysvětlení, bez přidání slov navíc.
        """

    // MARK: - Cache

    private static var cacheURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Dictator/LLM", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Lifecycle

    func load(progressHandler: @escaping @Sendable (Double) -> Void) async throws {
        guard state != .ready else { return }
        let repo = PostProcessingPreference.modelSize.huggingFaceRepo
        logger.info("PostProcessing: loading model \(repo, privacy: .public)")
        DiagnosticsLogger.log("PostProcessing: load started — \(repo)")

        state = .downloading
        progressHandler(0.05)

        do {
            let config = ModelConfiguration(id: repo)
            state = .loading
            progressHandler(0.5)

            let loaded = try await loadModelContainer(
                from: HuggingFaceHubDownloader(),
                using: HuggingFaceTokenizerLoader(),
                configuration: config
            ) { progress in
                let fraction = progress.fractionCompleted
                if fraction < 0.5 {
                    progressHandler(0.05 + fraction * 0.9)
                } else {
                    progressHandler(0.5 + (fraction - 0.5))
                }
            }
            container = loaded
            state = .ready
            progressHandler(1.0)
            logger.info("PostProcessing: model ready")
            DiagnosticsLogger.log("PostProcessing: model ready")
        } catch {
            state = .failed(error.localizedDescription)
            logger.error("PostProcessing: load failed — \(error.localizedDescription, privacy: .public)")
            DiagnosticsLogger.log("PostProcessing: load failed — \(error.localizedDescription)")
            throw error
        }
    }

    func unload() {
        container = nil
        state = .idle
        DiagnosticsLogger.log("PostProcessing: model unloaded")
    }

    // MARK: - Processing

    /// Vrátí opravený text nebo originál při selhání / timeoutu / halucinaci.
    /// Timeout je řízen volajícím přes withTaskGroup v AppDelegate.
    func process(_ text: String, targetAppBundleID: String? = nil) async throws -> String {
        guard let container else { throw PostProcessingError.notLoaded }

        var prompt = Self.systemPrompt
        if let context = AppContextPostProcessingStore.instruction(for: targetAppBundleID) {
            prompt += "\nKontext aktivní aplikace: \(context)"
        }

        let session = ChatSession(container, instructions: prompt)
        let raw = try await session.respond(to: text)

        guard let validated = validateOutput(raw, input: text) else {
            logger.warning("PostProcessing: output rejected (length ratio out of range)")
            DiagnosticsLogger.log("PostProcessing: output rejected — input=\(text.count)c output=\(raw.count)c")
            return text
        }
        return validated
    }

    // MARK: - Validation

    /// Ochrana proti halucinacím: zahodí výstup který je příliš krátký nebo příliš dlouhý
    /// oproti vstupu, případně prázdný.
    private func validateOutput(_ output: String, input: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !input.isEmpty else { return trimmed }

        let ratio = Double(trimmed.count) / Double(input.count)
        guard ratio >= 0.5, ratio <= 2.5 else { return nil }

        return trimmed
    }
}

// MARK: - Errors

enum PostProcessingError: LocalizedError {
    case notLoaded

    var errorDescription: String? {
        "PostProcessing model is not loaded."
    }
}
