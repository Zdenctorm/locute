# P0 — Specifikace: Kvalita každodenního diktování

**Milestone návrh:** `v1.1-p0`  
**Cíl release:** Uživatel může Dictator používat denně bez strachu ze ztráty schránky, rozbitého textu uprostřed věty, nebo „nic se nestalo“. Kolegové nainstalují bez Gatekeeper boje.

**Research:** [voice-dictation-market-research.md](../research/voice-dictation-market-research.md) — clipboard a paste jsou #1 stížnost u konkurence.

**Závislosti mezi položkami:**

```
P0.5 (notarizace) — nezávislé, může běžet paralelně
P0.1 (clipboard) ──┐
P0.2 (space)     ├──► společně testovat paste flow
P0.3 (case)      ──┘   (case je před inject v pipeline)
P0.4 (HUD error) — závisí na TextInjectResult (už existuje)
```

---

## P0.1 — Obnova schránky při Cmd+V vkládání

### Problém

`TextInjector.injectViaClipboard` volá `pasteboard.clearContents()` a po vložení **neobnovuje** původní obsah. Uživatelé ztrácí zkopírovaný text, obrázky nebo formátovaný HTML obsah schránky.

**Současný kód:** [`Dictator/Core/TextInjector.swift`](../../Dictator/Core/TextInjector.swift) — AX větev schránku nemění; problém je jen u Cmd+V větve.

### Uživatelská hodnota

Stejná jistota jako u nativního copy/paste — Dictator je „host“ v systému, ne sabotér schránky.

### User stories

1. Jako uživatel mám ve schránce URL, nadiktuji větu do Slacku — po vložení je ve schránce zase URL (pokud jsem mezitím nic jiného nekopíroval).
2. Jako uživatel mám ve schránce obrázek — po diktátu přes Cmd+V cesta obrázek **nezachová** (realisticky: obnovíme co šlo uložit; viz technické omezení).

### Acceptance criteria

- [ ] Před zápisem diktovaného textu se uloží snapshot `NSPasteboard.general` včetně `changeCount`.
- [ ] Po úspěšném Cmd+V se obnoví předchozí obsah, **pokud** `changeCount` se změnil maximálně o očekávaný počet kroků (naše vložení).
- [ ] Pokud uživatel mezitím kopíruje jiný obsah (`changeCount` výrazně jiný), schránku **ne přepisujeme** zpět (nepoškodit nový obsah).
- [ ] AX větev se nemění (už nezasahuje do schránky).
- [ ] Log: `Paste: clipboard restored` / `Paste: clipboard restore skipped (user changed pasteboard)`.

### Technický návrh

1. Nový typ `PasteboardSnapshot` (soubor `Dictator/Core/PasteboardSnapshot.swift` nebo rozšíření `TextInjector`):
   - `changeCount: Int`
   - `string: String?`
   - `types: [NSPasteboard.PasteboardType]` — pro rozhodnutí, zda jde obnovit
   - Metoda `capture(from: NSPasteboard) -> PasteboardSnapshot`
   - Metoda `restore(to: NSPasteboard) -> Bool`
2. V `injectViaClipboard`:
   - `let snapshot = PasteboardSnapshot.capture(...)`
   - existující clear + setString + simulateCmdV
   - `await Task.sleep` 50–100 ms (paste dokončení)
   - `snapshot.restoreIfUnchanged(since: snapshot.changeCount)`
3. Pro **rich content** (obrázky): ideálně `declareTypes` + `setData` pro všechny typy ze snapshotu; MVP může obnovit `.string` + logovat varování, pokud snapshot měl jen non-string typy.

### Test plan

| # | Scénář | Očekávání |
|---|--------|-----------|
| 1 | Zkopírovat „A“, diktovat do Chrome | Schránka „A“ |
| 2 | Zkopírovat „A“, diktovat, během paste zkopírovat „B“ | Schránka „B“ |
| 3 | Diktovat do TextEdit (AX) | Schránka beze změny |
| 4 | Unit: mock changeCount logika | restore / skip |

### Odhad složitosti

Střední — 1–2 soubory, edge cases u multi-type pasteboard.

### GitHub issue

**Title:** `P0.1: Restore clipboard after Cmd+V injection`

**Body:** (zkopírovat Acceptance criteria + odkaz na tento spec)

---

## P0.2 — Smart leading space

### Problém

Při vložení doprostřed věty chybí mezera (`word|cursor` + `next` → `wordnext`). AX větev částečně řeší separator v `injectViaAccessibility`; Cmd+V vkládá text bez kontextu kurzoru.

### Research

Běžný požadavek u paste-based diktování; Dragon řeší kontextem v editoru.

### User stories

1. Kurzor uprostřed věty `…prosím|poslat…` → po diktátu `…prosím zítra poslat…` (jedna mezera).
2. Kurzor na konci slova bez mezery před dalším slovem → doplnit jednu mezeru.
3. Kurzor na začátku řádku / za mezerou → **nepřidávat** leading space.
4. Výběr textu (selected range) → nahradit výběr bez leading space navíc.

### Acceptance criteria

- [ ] Nová pure funkce `InsertionSpacing.leadingSpacePolicy(context:) -> String` (prefix `""` nebo `" "`).
- [ ] Kontext pro AX: přečíst `kAXSelectedText` / pozici v `kAXValue` kde API dovolí; fallback: stávající separator logika.
- [ ] Pro Cmd+V: pokud nelze číst kontext, prefix mezera když vkládaný text **nezačíná** mezerou/newline a heuristika „vložení do prostřed textu“ (min. délka vkládaného textu > 0).
- [ ] Nastavení v UserDefaults: `smartLeadingSpaceEnabled` default `true`.
- [ ] Unit testy v `DictatorTests/` pro 8+ případů řetězců.

### Technický návrh

1. `Dictator/Core/InsertionSpacing.swift` — testovatelná logika.
2. Volání z `TextInjector` před `inject(text:)` — upravit `text` na `prefix + text`.
3. AX selected text replace: leading space **nepřidávat** (nahrazuje výběr).

### Test plan

Unit testy + manuálně: TextEdit (prostřed věty), Slack (Cmd+V), Terminal (bez leading space u příkazů — volitelně vyloučit bundle IDs terminálů z leading space).

### GitHub issue

**Title:** `P0.2: Smart leading space when inserting mid-sentence`

---

## P0.3 — Normalizace velikosti písmen (ALL-CAPS)

### Problém

Whisper občas vrátí krátká slova ALL CAPS (`ECHO`, `API` jako `A P I`). Uživatelé to musí ručně opravovat.

### Research

[FUTO voice-input #90](https://github.com/futo-org/voice-input/issues/90) — granular capitalization je žádaná feature.

### User stories

1. „Spusť echo server“ → `echo`, ne `ECHO`.
2. „Potřebujeme KYC dokumenty“ → `KYC` zůstane (whitelist).
3. „API klíč“ → `API` zůstane.

### Acceptance criteria

- [ ] Post-process krok `TranscriptionCaseNormalizer` po sanitizeru, před inject.
- [ ] Pravidlo: token celý uppercase, délka ≥ 2, není v whitelistu → `lowerercased()` (respektovat českou diakritiku).
- [ ] Whitelist: výchozí seed (KYC, AML, SEPA, EUR, USD, API, HTTP, …) + termíny z `LearningEngine` canonical uppercase.
- [ ] První slovo věty po `.!?` může zůstat capitalized (volitelná fáze 2); MVP: jen ALL-CAPS token fix.
- [ ] Unit testy v `DictatorTests/TranscriptionCaseNormalizerTests.swift`.

### Technický návrh

```swift
enum TranscriptionCaseNormalizer {
    static func normalize(_ text: String, whitelist: Set<String>) -> String
}
```

Volat v `AppDelegate` po sestavení `finalText`, před historií a inject.

### GitHub issue

**Title:** `P0.3: Lowercase spurious ALL-CAPS tokens (whitelist acronyms)`

---

## P0.4 — HUD a feedback při selhání vložení

### Problém

Při selhání inject už existuje status bar + otevření okna (`finalizeInjectUI`), ale HUD overlay nemá režim **chyba** — uživatel kouká na obrazovku a nevidí proč text není v poli.

### Současný stav

- `RecordingOverlayMode` — chybí `.injectionFailed`
- `finalizeInjectUI` — volá `showLastTranscription()` + transient status

### User stories

1. Vložení selže → červený/oranžový HUD: „Text se nevložil — otevři Dictator“ + zmizí po 5 s.
2. Watchdog 5 s → stejný HUD text jako dnes status bar.
3. Klik na HUD (volitelně) otevře hlavní okno na historii.

### Acceptance criteria

- [ ] Nový `RecordingOverlayMode.injectionFailed(message: String)`.
- [ ] `AppDelegate.finalizeInjectUI` při `!succeeded` zobrazí HUD failed místo success flash.
- [ ] Tlačítko v menu „Vložit poslední přepis“ zůstane; HUD text odkazuje na Option+? **ne** — jen „Okno Dictator“.
- [ ] Accessibility: oznámení chyby přes `AccessibilitySupport.announce`.
- [ ] Žádná telemetrie — jen lokální log.

### Technický návrh

1. Rozšířit `RecordingOverlayController` styling (červená tečka / ikona).
2. `AppDelegate` volat `recordingOverlay.show(.injectionFailed(...))` + `scheduleHide(after: 5)`.

### GitHub issue

**Title:** `P0.4: HUD overlay for injection failures`

---

## P0.5 — Apple Developer ID + notarizace produkčního buildu

### Problém

Distribuce mimo App Store bez notarizace = Gatekeeper „Apple cannot check“. Blokuje adopci u kolegů (viz OVERVIEW).

### Současný stav

- Skripty: [`scripts/sign_and_notarize.sh`](../../scripts/sign_and_notarize.sh), [`scripts/release.sh`](../../scripts/release.sh)
- Vyžaduje env: `DEVELOPER_ID_APPLICATION`, `NOTARY_KEYCHAIN_PROFILE` nebo Apple ID + app-specific password

### User stories

1. IT stáhne DMG z GitHub Release — dvojklik, appka běží bez pravého kliku „Otevřít“.
2. Maintainer spustí `./scripts/release.sh X.Y.Z` a notarizace proběhne automaticky.

### Acceptance criteria

- [ ] Zakoupený **Apple Developer Program** ($99/rok) účet týmu.
- [ ] Certifikát **Developer ID Application** v Keychain CI nebo maintainer Mac.
- [ ] `spctl --assess --type execute` na `.app` a DMG vrací `accepted`.
- [ ] Dokumentace v `RELEASING.md`: krok za krokem první notarizace, obnova certifikátu.
- [ ] GitHub Actions (volitelné): workflow `release.yml` s secrets — **neblokující** pro P0 pokud zůstane manuální release.
- [ ] `README` / install guide: co uživatel vidí při prvním spuštění **po** notarizaci (jen mic + accessibility).

### Technický / provozní checklist

1. [ ] Vytvořit App ID / bundle `ai.anycoin.dictator` (nebo aktuální) v Apple Developer.
2. [ ] Hardened Runtime + entitlements audit ([`Dictator.entitlements`](../../Dictator/Resources/Dictator.entitlements)).
3. [ ] Notarytool submit + staple DMG.
4. [ ] Ověřit na čistém Macu bez dev tools.

### GitHub issue

**Title:** `P0.5: Production Developer ID signing and notarization`

**Labels:** `P0`, `area:release`, `blocked:apple-account` (pokud čeká na cert)

---

## P0 — Release checklist (v1.1)

- [ ] Všechny P0.1–P0.4 v `main`, testováno na Sonoma + Sequoia
- [ ] P0.5: první notarized DMG na GitHub Releases
- [ ] Release notes v češtině pro kolegy
- [ ] Aktualizovat [ROADMAP.md](../../ROADMAP.md) — P0 sekce `[x]`
