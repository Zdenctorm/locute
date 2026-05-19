# Research: trh hlasového diktování (macOS, 2024–2026)

> **Účel:** Podklad pro rozhodování o roadmapě Dictatoru.  
> **Metoda:** Veřejná dokumentace konkurentů, GitHub issues populárních open-source nástrojů, help centra (Wispr, Dragon, SuperWhisper), diskuse o bolestech uživatelů.  
> **Poznámka:** Dictator **nepoužívá** cloudový přepis — research slouží k pochopení očekávání, ne ke kopírování architektury Wispr/SuperWhisper cloud částí.

---

## Segmenty produktů

| Segment | Příklady | Silná stránka | Slabina vůči Dictatoru |
|---------|----------|---------------|------------------------|
| **Cloud PTT** | Wispr Flow, Otter (meeting) | Rychlost, „funguje hned“, formátování LLM | Data na serveru, účet, compliance |
| **Lokální Mac PTT** | SuperWhisper, VoiceInk, Dictator | Soukromí, offline po stažení modelu | Instalace, velikost modelu, Gatekeeper |
| **Open-source** | Handy, OpenWhisper, Speak2 | Zdarma, forkovatelnost | UX, podpora, kvalita na okrajích |
| **Legacy enterprise** | Dragon (Nuance) | Hlasové příkazy, školení firem | Drahé, zastaralý UX, Windows-first |
| **Systémové** | macOS/iOS diktování | Žádná instalace | Přesnost CZ, cloud závislost, málo kontroly |

**Pozice Dictatoru:** lokální Mac PTT pro češtinu + firemní soukromí bez účtu. Konkuruje hlavně SuperWhisper / Handy / Wispr u uživatelů, kteří **nesmí** nebo **nechtějí** cloud.

---

## Co uživatelé nejčastěji chtějí (signály z trhu)

### 1. Spolehlivé vložení textu (P0 u nás)

| Signál | Zdroj | Dopad na Dictator |
|--------|--------|-------------------|
| Text se po diktátu **nevloží** do pole | [Wispr troubleshooting — paste](https://docs.wisprflow.ai/articles/7971211038-fix-text-not-pasting-after-dictation) | P0.4 HUD + záloha v historii; dokumentace oprávnění |
| **Schránka se přepíše** a neobnoví | [Handy #921](https://github.com/cjpais/Handy/issues/921), [Kalam #11](https://github.com/afaraha8403/kalam/issues/11) | **P0.1** obnova clipboardu kolem Cmd+V |
| Citrix / VDI / některé corporate appky blokují paste | Wispr help | Backlog: detekce + varování; AX-first kde jde |
| Dlouhé vkládání bez feedbacku | vlastní watchdog v `AppDelegate` | P0.4 rozšířit HUD (ne jen status bar) |

### 2. Kvalita textu bez ručního přepisování (P0 + P1)

| Signál | Zdroj | Dopad |
|--------|--------|--------|
| Špatná **velikost písmen** (ECHO, API) | [FUTO voice-input #90](https://github.com/futo-org/voice-input/issues/90), vlastní OVERVIEW | **P0.3** normalizace + whitelist |
| Chybějící **mezera** při vložení do věty | běžná stížnost u paste-based nástrojů | **P0.2** smart space |
| **Interpunkce** — někdo chce říkat „tečka“, jiný auto | Dragon explicitní příkazy; SuperWhisper auto | **P1.1** české příkazy + volitelný auto režim |
| Odstranění **výplňových slov** („ehm“, „jako“) | Wispr marketing feature | Backlog **R1** (post-process) |
| **Filler / halucinace** při tichu | iOS diskuse, Whisper komunita | už máme sanitizer; rozšířovat seznam |

### 3. Kontrola a oprava (P1)

| Signál | Zdroj | Dopad |
|--------|--------|--------|
| **Undo** posledního vložení | Dragon, iOS diskuse (undo před „druhým průchodem“) | **P1.3** |
| **Zkontroluj před vložením** | power users, citlivá data | **P1.4** |
| **Záložní vložení** — hotkey „vlož poslední přepis“ | Wispr Scratchpad, Alt+Shift+Z | Backlog **R2** |
| Ztráta dlouhého diktátu bez recovery | [Codex #18223](https://github.com/openai/codex/issues/18223) | historie na disku už máme; zvýraznit v UI při chybě |

### 4. Personalizace a přesnost domény (P1)

| Signál | Zdroj | Dopad |
|--------|--------|--------|
| **Vlastní slovník** / jména / produkty | SuperWhisper Pro, Wispr dictionary | máme LearningEngine → **P1.8–P1.10** |
| **Kontext z obrazovky** zlepšuje přepis | Wispr, SuperWhisper „context aware“ | Backlog **R3** — jen opt-in, lokálně |
| Slovník **podle aplikace** (Slack vs. terminál) | power users | **P1.9** |
| **Export/import** slovníku | standard u Pro nástrojů | **P1.8** |

### 5. Jazyk a model (P1)

| Signál | Zdroj | Dopad |
|--------|--------|--------|
| **Více jazyků** / CZ+EN mix | VoiceInk recenze, SuperWhisper 100+ langs | **P1.11–P1.13** |
| Volba **rychlost vs. přesnost** | SuperWhisper lokální modely (Turbo vs Ultra) | **P1.5** |
| **První diktát pomalý** po startu Macu | WhisperKit warm-up | **P1.7** (částečně warm-up už je) |
| Streaming / průběžný text při dlouhém držení | Wispr real-time | **P1.6** (náročné) |

### 6. Soukromí a enterprise (naše výhoda → P2, messaging)

| Signál | Zdroj | Dopad |
|--------|--------|--------|
| HIPAA / PHI **nesmí na cloud** | SuperWhisper sensitive data guide, Microsoft local AI blog | marketing + P2.5 privacy report |
| „Privacy mode“ u cloudu = **pořád server** | [Wispr data controls](https://wisprflow.ai/data-controls) | zdůraznit: Dictator = processing on device |
| Požadavek na **MDM**, air-gap model | Ottex Enterprise, on-prem Whisper | P2.2, P2.6 |
| Audit log bez obsahu textu | enterprise články | P2.4 |

### 7. Distribuce a důvěra (P0.5)

| Signál | Zdroj | Dopad |
|--------|--------|--------|
| Gatekeeper **„cannot check“** | každý ne-notarized Mac app | **P0.5** Developer ID + notarizace |
| Oprávnění Accessibility **matoucí** | všechny PTT appky | už máme setup okno; doplnit troubleshooting do docs |

---

## Konkurenční matice (zjednodušená)

| Funkce | Dictator dnes | SuperWhisper | Wispr Flow | Handy (OSS) | Dragon |
|--------|---------------|--------------|------------|-------------|--------|
| Offline přepis | ✅ | ✅ (local models) | ❌ | ✅ | ✅ (desktop) |
| Účet nutný | ❌ | Pro features | ✅ | ❌ | ✅ |
| Čeština kvalitně | ✅ (large-v3) | ✅ | ✅ | závisí na modelu | ✅ |
| Push-to-talk | ✅ | ✅ | ✅ | ✅ | ✅ |
| Vlastní slovník | ✅ (learning) | ✅ Pro | ✅ | ? | ✅ |
| Auto interpunkce | částečně (Whisper) | ✅ LLM | ✅ | ? | ✅ |
| Hlasové příkazy interpunkce | ❌ | méně | méně | ? | ✅ |
| Obnova schránky | ❌ | ? | dokumentováno | issue #921 | ? |
| Context ze obrazovky | ❌ | ✅ | ✅ | ❌ | částečně |
| Notarizovaný build | ❌ | ✅ | ✅ | varies | ✅ |

---

## Doporučené priority z researchu

### Zařadit / posílit v roadmapě

| ID | Položka | Proč |
|----|---------|------|
| P0.1–P0.4 | Clipboard, mezery, case, HUD chyby | Nejčastější důvody „přestanu to používat“ |
| P0.5 | Notarizace | Bariéra adopce u kolegů |
| P1.1 | České hlasové příkazy | Očekávání z Dragon; bez LLM cloud |
| P1.3–P1.4 | Undo + review mode | Citlivá data + chyby přepisu |
| P1.8 | Export slovníku | Sdílení v týmu bez cloudu |
| P1.5, P1.7 | Model + warm-up | Latence = vnímaná kvalita |

### Backlog z researchu (mimo P0/P1, pro budoucí rozhodování)

| ID | Název | Popis | Priorita návrhu |
|----|-------|--------|-----------------|
| **R1** | Odstranění výplňových slov | Post-process „ehm“, „jako“, „no“ (volitelné) | po P1.1 |
| **R2** | Hotkey „Vlož poslední přepis“ | Globální zkratka jako Wispr backup | po P0.4 |
| **R3** | Kontext z aktivního pole (opt-in) | AX přečte okolní text → Whisper prompt, **lokálně** | P2 / opatrně |
| **R4** | Seznam problematických aplikací | Citrix, některé RDP — zobrazit hint místo tichého failu | po P0.4 |
| **R5** | Snippety / šablony | Krátké makra („s pozdravem…“) — Wispr snippets | P2 |
| **R6** | Režim tichého mikrofonu | Nižší práh / gain hint — SuperWhisper „whisper mode“ | P2 |
| **R7** | Mazání historie po N dnech | SuperWhisper history management | P2.3 |
| **R8** | Dvojjazyčný mix v jedné větě | CS+EN bez přepínání — auto-detect | P1.13 |

### Co **nedělat** (potvrzeno research + principy)

- Cloudový přepis „pro rychlost“ — porušuje diferenciaci.
- Posílat obsah obrazovky na server pro kontext (Wispr model) — jen lokální R3.
- Nepřetržité poslouchání jako default — enterprise odpor.

---

## Citace a odkazy

- Wispr Flow — paste troubleshooting: https://docs.wisprflow.ai/articles/7971211038-fix-text-not-pasting-after-dictation  
- Wispr Flow — data controls (cloud processing): https://wisprflow.ai/data-controls  
- SuperWhisper — sensitive data / local models: https://superwhisper.com/docs/security/sensitive-data  
- Handy — clipboard issue: https://github.com/cjpais/Handy/issues/921  
- FUTO Voice Input — capitalization: https://github.com/futo-org/voice-input/issues/90  
- Nuance Dragon — dictation commands: https://www.nuance.com/products/help/dragon/dragon-for-pc/enx/dps/main/Content/Dictation/dictating_punctuation.htm  
- Handy repo: https://github.com/cjpais/Handy  

---

## Revize

| Datum | Autor | Změna |
|-------|-------|--------|
| 2026-05 | Cursor agent | První verze research dokumentu |
