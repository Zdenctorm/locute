# P1 — Specifikace: Profesionální diktování

**Milestone návrh:** `v1.2-p1` (po dokončení P0 / v1.1)  
**Cíl release:** Dictator pokrývá očekávání power userů a konkurence (Dragon příkazy, SuperWhisper slovník, Wispr zálohy) — stále **offline a bez účtu**.

**Research:** viz [voice-dictation-market-research.md](../research/voice-dictation-market-research.md).

**Doporučené pořadí implementace:**

```
P1.8 (export slovníku) ──► P1.10 (editor) ──► P1.9 (profily app)
P1.5 (volba modelu)    ──► P1.7 (warm-up)  ──► P1.6 (streaming, poslední)
P1.1 (interpunkce)     ──► P1.2 (čísla)
P1.11 (EN)             ──► P1.12 (SK)     ──► P1.13 (auto-detect)
P1.4 (review mode)     ──► P1.3 (undo)
```

---

## P1.1 — Interpunkční a formátovací hlasové příkazy (čeština)

### Problém

Whisper občas dává interpunkci sám; uživatelé z Dragon zvyklí říkat „tečka“, „nový odstavec“. Bez podpory musí opravovat v historii.

### Research

- Dragon: explicitní příkazy, pauza před/po interpunkci zvyšuje přesnost.
- SuperWhisper: spíš auto + LLM — my zůstáváme u lokálního post-process.

### User stories

1. „Dobrý den tečka“ → `Dobrý den.`
2. „Seznam čárka první položka čárka druhá tečka“ → `Seznam, první položka, druhá.`
3. „Nový odstavec Druhý odstavec“ → `\n\nDruhý odstavec`
4. Vypnutí v nastavení: „Nechat jen Whisper“.

### Acceptance criteria

- [ ] `VoiceCommandProcessor` mapuje fráze → náhrady (case-insensitive, word boundaries).
- [ ] Minimální sada CZ:

| Řeč | Výstup |
|-----|--------|
| tečka | `.` |
| čárka | `,` |
| středník | `;` |
| dvojtečka | `:` |
| vykřičník | `!` |
| otazník | `?` |
| uvozovky / uvozovka | `"` |
| nový řádek | `\n` |
| nový odstavec | `\n\n` |

- [ ] Příkazy se aplikují **po** přepisu, před case normalizerem.
- [ ] `UserDefaults`: `voiceCommandsEnabled` default `true`.
- [ ] Dokumentace v okně Nastavení — tabulka příkazů.

### Technický návrh

`Dictator/Core/VoiceCommandProcessor.swift` — pure, unit testy.

### GitHub issue

**Title:** `P1.1: Czech voice commands for punctuation and paragraphs`

---

## P1.2 — Normalizace čísel a dat

### Problém

Mluvená čísla a data jsou nekonzistentní (`dvacet tři` vs `23`, `prvního května`).

### User stories

1. Režim „formální“: slova → číslice kde bezpečné.
2. Režim „slovní“: ponechat mluvenou formu (default pro běžný prose).

### Acceptance criteria

- [ ] Fáze 1 (MVP): normalizace **řadových číslovek 0–99** v češtině (`jedna`…`devadesát devět`) → číslice, s výjimkou whitelist kontextů.
- [ ] Fáze 2 (volitelně v P1.2): data `prvního ledna 2026` → `1. 1. 2026` (knihovna nebo pravidla).
- [ ] Vypínatelné v nastavení.
- [ ] Unit testy pro 20+ vět.

### Technický návrh

`Dictator/Core/SpokenNumberNormalizer.swift` — odděleně od VoiceCommandProcessor.

### GitHub issue

**Title:** `P1.2: Spoken number normalization (Czech)`

---

## P1.3 — Undo posledního vložení

### Problém

Po špatném přepisu uživatel maže ručně. Dragon i iOS diskuse zmiňují undo.

### User stories

1. Po úspěšném vložení: menu „Vrátit poslední vložení“ aktivní 30 s.
2. Zkratka (návrh): `⌃⌥Z` pouze když Dictator poslední vložil text.

### Acceptance criteria

- [ ] Uložit `{text, targetApp, method, timestamp}` po úspěšném inject.
- [ ] Undo:
  - AX: pokud známe předchozí hodnotu pole — obnovit (MVP: selektovat vložený text a smazat simulací Backspace / AX replace prázdným).
  - Cmd+V větev: smazat vložený substring pokud je stále na konci pole (heuristika).
- [ ] Pokud undo nelze bezpečně → zobrazit dialog „Zkopíruj původní z historie“.
- [ ] Po 30 s nebo novém diktátu undo expiruje.

### Rizika

Nespolehlivé v terminálech a web editorech — dokumentovat omezení.

### GitHub issue

**Title:** `P1.3: Undo last dictation insertion (best-effort)`

---

## P1.4 — Režim „zkontroluj před vložením“

### Problém

U citlivých textů (smlouvy, hesla blízko) chce uživatel vidět přepis před odesláním do cílové appky.

### Research

Wispr scratchpad; naše historie je blízká, ale příchod je až po pokusu o vložení.

### User stories

1. V nastavení zapnu „Vždy zobrazit přepis před vložením“.
2. Po puštění klávesy se otevře panel s textem — tlačítka **Vložit**, **Upravit**, **Zahodit**.
3. Enter = Vložit, Esc = Zahodit.

### Acceptance criteria

- [ ] `UserDefaults.reviewBeforeInsert` (default `false`).
- [ ] Stav `DictatorState.awaitingReview` nebo modální sheet v `LaunchWindowController`.
- [ ] Vložit volá stávající `pasteWithWatchdog`.
- [ ] Upravit = focus textové pole v panelu.
- [ ] Funguje i s menu „Začít diktování“.

### Technický návrh

Rozšířit state machine v [`AppState.swift`](../../Dictator/Core/AppState.swift); UI v `TranscriptionPanelView` nebo nový `ReviewSheetController`.

### GitHub issue

**Title:** `P1.4: Optional review-before-insert mode`

---

## P1.5 — Volba Whisper modelu

### Problém

Jen `large-v3` (~3 GB) — na starších M1 nebo při potřebě rychlosti uživatelé chtějí menší model (Handy, SuperWhisper Turbo).

### User stories

1. Nastavení: Přesnost (large-v3) / Rychlost (medium nebo small — ověřit WhisperKit varianty).
2. Změna modelu = stáhnout nový balík + restart load.

### Acceptance criteria

- [ ] UI výběr modelu s velikostí souboru a odhadem RAM.
- [ ] `TranscriptionEngine` bere `modelName` z `UserDefaults`.
- [ ] Jednorázové stažení per model; nesmaže ostatní modely v cache bez souhlasu.
- [ ] Downgrade když model neexistuje → fallback large-v3 + log.

### Technický návrh

Refactor `TranscriptionEngine` — config struct; tabulka variant v dokumentaci.

### GitHub issue

**Title:** `P1.5: User-selectable WhisperKit model variant`

---

## P1.6 — Průběžný přepis (streaming)

### Problém

Dlouhé držení Option — uživatel nevidí text, dokud nepustí.

### Research

Wispr real-time; WhisperKit podpora chunk/stream — ověřit API.

### User stories

1. Po 3 s nahrávání HUD ukazuje průběžný draft text (může se měnit).
2. Po puštění — finální přepis nahradí draft.

### Acceptance criteria

- [ ] Feature flag `streamingPreviewEnabled` default **off** (beta).
- [ ] Interval chunk 2–3 s; nezhoršit stabilitu audio tap.
- [ ] CPU/baterie: měření — na M1 varování v UI.

### Rizika

Vysoká složitost; může být rozděleno na P1.6a (UI placeholder) a P1.6b (engine).

### GitHub issue

**Title:** `P1.6: Streaming transcription preview (beta)`

---

## P1.7 — Agresivnější warm-up po startu

### Problém

První diktát po cold start je pomalý. `warmUp()` už existuje v `TranscriptionEngine`.

### User stories

1. Po načtení modelu na idle — tichý warm-up už proběhl.
2. Volitelně: po přihlášení + 60 s idle znovu warm-up.

### Acceptance criteria

- [ ] Warm-up běží na background queue, neblokuje UI.
- [ ] Log délky warm-up; cíl první diktát < 2× medián dalších.
- [ ] Vypnutí v pokročilém nastavení.

### GitHub issue

**Title:** `P1.7: Improve cold-start latency via background warm-up`

---

## P1.8 — Export / import slovníku

### Problém

Učení je v `LearningEngine` JSON; chybí záloha a sdílení mezi Macy / kolegy bez cloudu.

### Research

SuperWhisper custom vocabulary; týmy chtějí sdílený glossary (P2.1 příbuzné).

### User stories

1. Menu „Exportovat slovník…“ → `.dictator-vocab.json`.
2. „Importovat…“ → merge nebo replace s potvrzením.

### Acceptance criteria

- [ ] Formát verze `schemaVersion: 1`, pole `entries: [{canonical, variants, ...}]`.
- [ ] Import merge: nové termíny + konflikt → dialog (přepsat / přeskočit).
- [ ] Neexportovat audio ani historii přepisů.

### Technický návrh

Rozšířit `LearningEngine` + `NSOpenPanel` / `NSSavePanel` v `LearnedTermsView` nebo Settings.

### GitHub issue

**Title:** `P1.8: Export and import learned vocabulary (JSON)`

---

## P1.9 — Profil slovníku podle aplikace

### Problém

Jiné termíny ve Slacku (produkt) vs. Xcode (kód).

### User stories

1. Při `pendingDictationTarget.bundleID` sloučit **globální** + **app-specific** slovník.
2. UI: záložka v nastavení „Slovník pro Slack“.

### Acceptance criteria

- [ ] `AppVocabularyProfile`: `bundleID → [VocabularyEntry]`.
- [ ] Ukládání v `~/Library/Application Support/Dictator/profiles/`.
- [ ] `TranscriptionEngine.applyVocabulary` dostane merged snapshot.

### GitHub issue

**Title:** `P1.9: Per-app vocabulary profiles`

---

## P1.10 — Ruční editor celého slovníku

### Problém

„Co se Dictator naučil“ je read-only-ish; chybí hromadná úprava seed + learned.

### User stories

1. Jedno okno: seznam řádků `canonical: variant1, variant2`.
2. Validace stejná jako `VocabularyEntry.parse(line:)`.
3. Uložit → push do engine + LearningEngine.

### Acceptance criteria

- [ ] Textový editor s nápovědou syntaxe (jako dřívější raw vocabulary).
- [ ] Tlačítka Import/Export (navazuje na P1.8).
- [ ] Nesmí rozbít `confirmationCount` logiku — ruční záznam = `confirmationCount >= 2`.

### GitHub issue

**Title:** `P1.10: Full vocabulary text editor`

---

## P1.11 — Angličtina

### User stories

1. Nastavení jazyk: Čeština / English.
2. `DecodingOptions.language = "en"`.
3. UI stringy zůstávají CZ (lokalizace UI = backlog).

### Acceptance criteria

- [ ] Přepnutí jazyka vyžaduje restart engine nebo reload modelu (stejný weights).
- [ ] Seed slovník EN volitelný (prázdný default).

### GitHub issue

**Title:** `P1.11: English transcription language option`

---

## P1.12 — Slovenština

Stejné jako P1.11 s `language = "sk"`.

### GitHub issue

**Title:** `P1.12: Slovak transcription language option`

---

## P1.13 — Automatická detekce jazyka

### User stories

1. Režim „Auto (CS / EN / SK)“ — Whisper `language` nil nebo detect dle WhisperKit API.
2. HUD zobrazí detekovaný jazyk po přepisu (ikona / tooltip).

### Acceptance criteria

- [ ] Omezení na podporované jazyky (ne 100 jazyků najednou).
- [ ] Log detekovaného jazyka v DiagnosticsLogger.

### Rizika

Přesnost u krátkých utterancí — dokumentovat.

### GitHub issue

**Title:** `P1.13: Auto language detection (cs/en/sk)`

---

## P1 — Release checklist (v1.2)

- [ ] Minimálně P1.1, P1.4, P1.8, P1.11 dodáno (doporučený „thin“ v1.2)
- [ ] Zbytek P1 podle kapacity — neblokovat release pokud P1.6 odložen
- [ ] Aktualizace ROADMAP + release notes
- [ ] Research backlog R1–R8 prioritizován po retrospektivě

---

## Položky z researchu zařazené mimo P1 (k rozhodnutí)

| ID | Název | Doporučení |
|----|-------|------------|
| R1 | Filler words removal | P1.5+ nebo v1.3 |
| R2 | Hotkey paste last transcript | Po P0.4 |
| R3 | Screen/focus context (opt-in) | P2 — privacy review |
| R4 | Problematic app hints | Po P0.4 |

Viz [voice-dictation-market-research.md](../research/voice-dictation-market-research.md).
