import Foundation

// MARK: - Public types

enum CorrectionSource: String, Codable, Sendable {
    case retryDetected
    case userClickInHistory
    case userTypedInDict
    case migratedFromSeed
}

struct LearnedVariant: Codable, Equatable, Sendable {
    let text: String
    var occurrences: Int
    var lastSeenAt: Date

    init(text: String, occurrences: Int = 1, lastSeenAt: Date = Date()) {
        self.text = text
        self.occurrences = occurrences
        self.lastSeenAt = lastSeenAt
    }
}

struct LearnedEntry: Codable, Equatable, Sendable {
    let id: UUID
    let canonical: String
    var variants: [LearnedVariant]
    var firstSeenAt: Date
    var lastConfirmedAt: Date
    /// Použití kanonické formy v přepisech (zobrazuje se v UI „3× použito").
    var usageCount: Int
    /// ≥2 = aktivní v decoderu a post-procesu, =1 = pending (čeká na druhý výskyt).
    var confirmationCount: Int
    let source: CorrectionSource

    init(
        id: UUID = UUID(),
        canonical: String,
        variants: [LearnedVariant] = [],
        firstSeenAt: Date = Date(),
        lastConfirmedAt: Date = Date(),
        usageCount: Int = 0,
        confirmationCount: Int,
        source: CorrectionSource
    ) {
        self.id = id
        self.canonical = canonical
        self.variants = variants
        self.firstSeenAt = firstSeenAt
        self.lastConfirmedAt = lastConfirmedAt
        self.usageCount = usageCount
        self.confirmationCount = confirmationCount
        self.source = source
    }
}

extension Notification.Name {
    /// Nahrazuje `dictatorVocabularyChanged`. Posílá `LearningEngine` po každém commitu.
    static let dictatorLearnedTermsChanged = Notification.Name("DictatorLearnedTermsChanged")
}

// MARK: - LearningEngine

@MainActor
final class LearningEngine {
    static let shared = LearningEngine()

    private(set) var learnedEntries: [LearnedEntry] = []

    private var saveDebounceTimer: Timer?
    private let storeURL: URL
    private let schemaVersion = 1

    private init() {
        self.storeURL = LearningEngine.defaultStoreURL()
        ensureContainerExists()
        if !loadFromDisk() {
            bootstrapFromLegacyVocabularyStore()
            persistImmediately()
        }
        DiagnosticsLogger.log("LearningEngine ready: entries=\(learnedEntries.count)")
    }

    // MARK: - Public API

    /// Vrátí slovník pro `TranscriptionEngine`, jen aktivní termíny (`confirmationCount ≥ 2`).
    func currentActiveVocabulary() -> VocabularyDictionary {
        let active = learnedEntries.filter { $0.confirmationCount >= 2 }
        let vocabEntries = active.map { entry in
            VocabularyEntry(
                canonical: entry.canonical,
                variants: entry.variants.map(\.text)
            )
        }
        return VocabularyDictionary(entries: vocabEntries)
    }

    /// Volá AppDelegate po každém úspěšném přepisu. Pro entries, jejichž varianta se v textu
    /// uplatnila (originalText != nil), inkrementuje counters — pro „3× použito, naposledy dnes".
    func observeTranscriptionDone(entry: TranscriptionHistoryEntry) {
        var changed = false
        for word in entry.words {
            guard word.originalText != nil else { continue }
            if let idx = learnedEntries.firstIndex(where: { $0.canonical == word.text }) {
                learnedEntries[idx].usageCount += 1
                learnedEntries[idx].lastConfirmedAt = Date()
                if let original = word.originalText,
                   let varIdx = learnedEntries[idx].variants.firstIndex(where: { $0.text.caseInsensitiveCompare(original) == .orderedSame }) {
                    learnedEntries[idx].variants[varIdx].occurrences += 1
                    learnedEntries[idx].variants[varIdx].lastSeenAt = Date()
                }
                changed = true
            }
        }
        if changed { commit(notify: false) }
    }

    /// Pasivní učení: dvě nahrávky <8 s od sebe = pravděpodobně retry. Vyextrahuje
    /// kandidáta variant → canonical a zapíše ho jako pending (nebo aktivuje, pokud už existuje).
    func observeRetry(
        previous: TranscriptionHistoryEntry,
        current: TranscriptionHistoryEntry
    ) {
        guard let pair = RetryDiff.extractCandidate(previous: previous, current: current) else {
            return
        }
        let variant = pair.variantText
        let canonical = pair.canonicalText

        DiagnosticsLogger.log("LearningEngine retry candidate: variant=\"\(variant)\" canonical=\"\(canonical)\"")
        applyCandidate(variant: variant, canonical: canonical, source: .retryDetected, explicit: false)
    }

    /// Explicitní uživatelská korekce z UI (klik na slovo v historii nebo ruční přidání).
    /// Skipne pending gate — rovnou `confirmationCount = 2`.
    func observeUserCorrection(variant: String, canonical: String, source: CorrectionSource) {
        applyCandidate(variant: variant, canonical: canonical, source: source, explicit: true)
    }

    /// Smaže kanonický záznam i všechny jeho varianty.
    func removeEntry(canonical: String) {
        learnedEntries.removeAll { $0.canonical == canonical }
        commit(notify: true)
    }

    func reloadFromDisk() {
        _ = loadFromDisk()
        NotificationCenter.default.post(name: .dictatorLearnedTermsChanged, object: nil)
    }

    // MARK: - Core mutation

    private func applyCandidate(
        variant: String,
        canonical: String,
        source: CorrectionSource,
        explicit: Bool
    ) {
        let trimmedCanonical = canonical.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVariant = variant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCanonical.isEmpty, !trimmedVariant.isEmpty else { return }
        guard trimmedCanonical.caseInsensitiveCompare(trimmedVariant) != .orderedSame else { return }

        if let idx = learnedEntries.firstIndex(where: { $0.canonical.caseInsensitiveCompare(trimmedCanonical) == .orderedSame }) {
            // Existující entry: přidej / zvedni variantu, pak možná zvedni confirmationCount.
            let varIdx = learnedEntries[idx].variants.firstIndex {
                $0.text.caseInsensitiveCompare(trimmedVariant) == .orderedSame
            }
            if let varIdx {
                learnedEntries[idx].variants[varIdx].occurrences += 1
                learnedEntries[idx].variants[varIdx].lastSeenAt = Date()
            } else {
                learnedEntries[idx].variants.append(LearnedVariant(text: trimmedVariant))
            }

            let wasInactive = learnedEntries[idx].confirmationCount < 2
            if explicit {
                learnedEntries[idx].confirmationCount = max(learnedEntries[idx].confirmationCount, 2)
            } else {
                learnedEntries[idx].confirmationCount += 1
            }
            learnedEntries[idx].lastConfirmedAt = Date()
            let nowActive = learnedEntries[idx].confirmationCount >= 2
            commit(notify: true)
            if wasInactive && nowActive {
                postLearnedToast(canonical: learnedEntries[idx].canonical)
            }
        } else {
            // Nový entry.
            let initialCount = explicit ? 2 : 1
            let entry = LearnedEntry(
                canonical: trimmedCanonical,
                variants: [LearnedVariant(text: trimmedVariant)],
                confirmationCount: initialCount,
                source: source
            )
            learnedEntries.append(entry)
            commit(notify: true)
            if initialCount >= 2 {
                postLearnedToast(canonical: trimmedCanonical)
            } else {
                DiagnosticsLogger.log("LearningEngine: pending entry \(trimmedCanonical) (count=1)")
            }
        }
    }

    private func postLearnedToast(canonical: String) {
        DiagnosticsLogger.log("LearningEngine activated: \(canonical)")
        NotificationCenter.default.post(
            name: .dictatorLearnedTermsChanged,
            object: nil,
            userInfo: ["activatedCanonical": canonical]
        )
    }

    private func commit(notify: Bool) {
        scheduleSave()
        if notify {
            NotificationCenter.default.post(name: .dictatorLearnedTermsChanged, object: nil)
        }
    }

    // MARK: - Persistence

    private struct Storage: Codable {
        let schemaVersion: Int
        let entries: [LearnedEntry]
    }

    private static func defaultStoreURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent(AppBrand.storageDirectoryName, isDirectory: true)
            .appendingPathComponent("learning.json")
    }

    private func ensureContainerExists() {
        let dir = storeURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    @discardableResult
    private func loadFromDisk() -> Bool {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return false }
        do {
            let data = try Data(contentsOf: storeURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let storage = try decoder.decode(Storage.self, from: data)
            self.learnedEntries = storage.entries
            return true
        } catch {
            DiagnosticsLogger.log("LearningEngine: failed to load \(storeURL.lastPathComponent): \(error.localizedDescription)")
            return false
        }
    }

    private func scheduleSave() {
        saveDebounceTimer?.invalidate()
        saveDebounceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.persistImmediately()
            }
        }
    }

    private func persistImmediately() {
        let storage = Storage(schemaVersion: schemaVersion, entries: learnedEntries)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(storage)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            DiagnosticsLogger.log("LearningEngine: failed to persist: \(error.localizedDescription)")
        }
    }

    // MARK: - Migration ze starého VocabularyStore (one-shot)

    private func bootstrapFromLegacyVocabularyStore() {
        let raw = VocabularyStore.legacyRawTextForMigration()
        let vocab = VocabularyDictionary(rawText: raw)
        let now = Date()
        let distantPast = Date.distantPast

        learnedEntries = vocab.entries.map { entry in
            LearnedEntry(
                canonical: entry.canonical,
                variants: entry.variants.map { LearnedVariant(text: $0, occurrences: 0, lastSeenAt: distantPast) },
                firstSeenAt: distantPast,
                lastConfirmedAt: now,
                usageCount: 0,
                confirmationCount: 999,
                source: .migratedFromSeed
            )
        }
        DiagnosticsLogger.log("LearningEngine bootstrapped from legacy vocabulary: \(learnedEntries.count) entries")
        VocabularyStore.clearLegacyStorage()
    }
}

// MARK: - Retry diff

enum RetryDiff {
    struct Candidate {
        let variantText: String
        let canonicalText: String
    }

    /// Vrátí kandidát variant → canonical, pokud diff dvou přepisů vypadá jako
    /// "uživatel řekl totéž znovu a opravil jedno slovo". Žádný kandidát → nil.
    static func extractCandidate(
        previous: TranscriptionHistoryEntry,
        current: TranscriptionHistoryEntry
    ) -> Candidate? {
        let prevWords = previous.words.isEmpty
            ? tokenize(previous.text)
            : previous.words.map { WordToken(text: $0.text, confidence: $0.confidence) }
        let currWords = current.words.isEmpty
            ? tokenize(current.text)
            : current.words.map { WordToken(text: $0.text, confidence: $0.confidence) }
        guard !prevWords.isEmpty, !currWords.isEmpty else { return nil }
        guard abs(prevWords.count - currWords.count) <= 2 else { return nil }
        if normalizedTextEqual(prevWords, currWords) { return nil }

        // Najdi nejdelší společný prefix.
        var prefix = 0
        while prefix < prevWords.count, prefix < currWords.count,
              normalizedEqual(prevWords[prefix].text, currWords[prefix].text) {
            prefix += 1
        }

        // Nejdelší společný suffix (po prefixu).
        var suffix = 0
        while suffix < (prevWords.count - prefix), suffix < (currWords.count - prefix),
              normalizedEqual(
                  prevWords[prevWords.count - 1 - suffix].text,
                  currWords[currWords.count - 1 - suffix].text
              ) {
            suffix += 1
        }

        let prevSlice = prevWords[prefix ..< (prevWords.count - suffix)]
        let currSlice = currWords[prefix ..< (currWords.count - suffix)]
        guard !prevSlice.isEmpty, !currSlice.isEmpty else { return nil }

        // Akceptujeme jen drobné slice rozdíly. Příklady: 1↔1, 1↔2, 2↔1, 3↔1.
        guard prevSlice.count <= 3, currSlice.count <= 3 else { return nil }

        // Confidence filter: pokud byl Whisper na previous slice velmi jistý, je to spíš
        // nová informace, ne oprava.
        let prevConfidence = prevSlice.map(\.confidence).reduce(0, +) / Float(prevSlice.count)
        guard prevConfidence < 0.85 else {
            DiagnosticsLogger.log("RetryDiff skip: prev slice confidence too high (\(prevConfidence))")
            return nil
        }

        let variantText = prevSlice.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
        let canonicalText = currSlice.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
        guard !variantText.isEmpty, !canonicalText.isEmpty else { return nil }
        return Candidate(variantText: variantText, canonicalText: canonicalText)
    }

    private static func tokenize(_ text: String) -> [WordToken] {
        text
            .split(whereSeparator: { $0.isWhitespace })
            .map { piece -> WordToken in
                let trimmed = String(piece).trimmingCharacters(in: .punctuationCharacters)
                return WordToken(text: trimmed, confidence: 0.5)
            }
            .filter { !$0.text.isEmpty }
    }

    private static func normalizedEqual(_ lhs: String, _ rhs: String) -> Bool {
        let a = lhs
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .punctuationCharacters)
        let b = rhs
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .punctuationCharacters)
        return a == b
    }

    private static func normalizedTextEqual(_ lhs: [WordToken], _ rhs: [WordToken]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (a, b) in zip(lhs, rhs) where !normalizedEqual(a.text, b.text) {
            return false
        }
        return true
    }
}
