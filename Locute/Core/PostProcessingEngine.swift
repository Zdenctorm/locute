import Foundation
import MLXLMCommon
import MLXLLM
import os

/// Lokální LLM post-procesor pro opravu Whisper přepisů.
///
/// Pouze interpunkce a velká písmena — nikdy konverzace ani odpovědi.
/// Funguje výhradně offline na Apple Silicon (Neural Engine + GPU).
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
    private let logger = Logger(subsystem: "com.example.locute", category: "postprocessing")

    var isLoaded: Bool { state == .ready }

    // MARK: - Prompts (formátování, ne chat)

    private static let systemPrompt = """
        Nejsi chatbot. Nepřidávej vlastní věty, odpovědi, rady ani pozdravy. \
        Jediný úkol: z přepisu uživatele udělat správně interpunkovaný český text. \
        Pravidla: věty končí . ? ! ; čárka před že, když, protože, pokud, aby, který, jestli, zda; \
        otázky končí ? ; zachovej stejná slova ve stejném pořadí (smíš jen doplnit znaki a opravit velikost písmen). \
        Nikdy nepoužívej pomlčku (znaky — – −). Místo pomlčky použij čárku nebo tečku. \
        Neměň význam. Vrať výhradně upravený přepis — bez uvozovek kolem celého textu, bez komentářů.
        """

    // MARK: - Cache

    private static var cacheURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("\(AppBrand.storageDirectoryName)/LLM", isDirectory: true)
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
        progressHandler(0.02)

        do {
            let config = ModelConfiguration(id: repo)
            state = .loading

            let loaded = try await loadModelContainer(
                from: HuggingFaceHubDownloader(),
                using: HuggingFaceTokenizerLoader(),
                configuration: config
            ) { progress in
                let fraction = min(1, max(0, progress.fractionCompleted))
                progressHandler(0.02 + fraction * 0.88)
            }
            container = loaded
            progressHandler(0.92)

            do {
                try await warmUp(container: loaded)
            } catch {
                logger.warning("PostProcessing: warm-up failed — \(error.localizedDescription, privacy: .public)")
                DiagnosticsLogger.log("PostProcessing: warm-up failed — \(error.localizedDescription)")
            }
            progressHandler(0.98)

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

    private func warmUp(container: ModelContainer) async throws {
        let session = ChatSession(container, instructions: Self.systemPrompt)
        _ = try await session.respond(to: Self.formattingRequest(for: "dobrý den posílám přílohu"))
    }

    // MARK: - Processing

    func process(_ text: String, targetAppBundleID: String? = nil) async throws -> String {
        guard let container else { throw PostProcessingError.notLoaded }

        var instructions = Self.systemPrompt
        if let context = AppContextPostProcessingStore.instruction(for: targetAppBundleID) {
            instructions += "\n\(context)"
        }

        let session = ChatSession(container, instructions: instructions)
        let raw = try await session.respond(to: Self.formattingRequest(for: text))

        let cleaned = PostProcessingOutputSanitizer.cleaned(raw, originalInput: text)
        guard let validated = validateOutput(cleaned, input: text) else {
            logger.warning("PostProcessing: output rejected")
            DiagnosticsLogger.log("PostProcessing: output rejected — input=\(text.count)c output=\(raw.count)c")
            return text
        }
        return PostProcessingOutputSanitizer.replaceForbiddenDashes(validated)
    }

    private static func formattingRequest(for transcript: String) -> String {
        """
        [PŘEPIS K ÚPRAVĚ]
        \(transcript)
        [KONEC PŘEPISU]
        Uprav pouze interpunkci a velká písmena. Nevysvětluj a neodpovídej na obsah.
        """
    }

    // MARK: - Validation

    private func validateOutput(_ output: String, input: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !input.isEmpty else { return trimmed }

        if PostProcessingOutputSanitizer.looksLikeAssistantReply(output: trimmed, input: input) {
            DiagnosticsLogger.log("PostProcessing: rejected — assistant reply")
            return nil
        }

        for dash in CzechPunctuationRules.forbiddenDashes where trimmed.contains(dash) {
            DiagnosticsLogger.log("PostProcessing: rejected — contains dash")
            return nil
        }

        let ratio = Double(trimmed.count) / Double(input.count)
        guard ratio >= 0.65, ratio <= 1.45 else { return nil }

        let retention = PostProcessingOutputSanitizer.wordRetentionRatio(output: trimmed, input: input)
        guard retention >= 0.78 else {
            DiagnosticsLogger.log("PostProcessing: rejected — word retention \(retention)")
            return nil
        }

        let inputWords = input.split(whereSeparator: { $0.isWhitespace }).count
        let novel = PostProcessingOutputSanitizer.novelWordCount(output: trimmed, input: input)
        let novelLimit = max(2, inputWords / 15)
        guard novel <= novelLimit else {
            DiagnosticsLogger.log("PostProcessing: rejected — novel words \(novel) > \(novelLimit)")
            return nil
        }

        if inputWords >= 12, CzechHeuristicPunctuator.needsMorePunctuation(trimmed) {
            DiagnosticsLogger.log("PostProcessing: rejected — output lacks punctuation")
            return nil
        }

        return trimmed
    }
}

enum PostProcessingError: LocalizedError {
    case notLoaded

    var errorDescription: String? {
        "PostProcessing model is not loaded."
    }
}
