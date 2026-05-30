# Dictator — PRODUCT.md

> Impeccable design context. Vytvořeno `/impeccable teach` (init) z existujícího kódu, OVERVIEW.md a konkurenční analýzy. Upravte sekce, které neodpovídají vaší vizi.

---

## Register

**product** — nativní macOS utilita (menu bar + pomocná okna). Design **slouží produktu**: rychlé diktování, důvěra, minimum rušení. Ne marketingový web; žádný „AI SaaS landing“ vzhled.

---

## What

Dictator je **soukromé české push-to-talk diktování** pro macOS. Uživatel podrží diktovací klávesu, mluví, pustí — text se vloží tam, kde má kurzor, v libovolné aplikaci. Přepis běží **lokálně** (WhisperKit na Apple Silicon). Po jednorázovém stažení modelu **žádná data neopouštějí Mac**.

Hlavní loop: **klávesa → mikrofon → přepis → vložení**. Vedlejší: historie přepisů, oprava slov, vlastní slovník, volitelná lokální úprava textu.

---

## Who

**Primární:** znalostní pracovníci v českém prostředí (firma, tým), kteří:

- píší hodiny denně do Mailu, Slacku, Notion, IDE, CRM;
- **nesmí nebo nechtějí** posílat hlas/text do cloudu (NDA, compliance, zdravý rozum);
- chtějí **Option-style** gesto bez přepínání do samostatné diktovací appky.

**Sekundární:** technicky zdatní uživatelé na Macu (Apple Silicon), kteří už zkoušeli Wispr Flow / Superwhisper / Apple Dictation a chtějí **česky + offline**.

**Ne cílovka:** uživatelé bez Macu M-series; ti, kdo potřebují 100 jazyků a cloud auto-edit jako hlavní hodnotu; uživatelé, kteří chtějí přepis hodinových nahrávek (→ spíš MacWhisper).

---

## Goals (product)

1. **Bez tření** — po nastavení oprávnění diktovat bez otevírání okna; menu bar + HUD stačí.
2. **Důvěra** — na první pohled jasné: audio a přepis zůstávají na zařízení (kromě jednorázového stažení modelu).
3. **Předvídatelnost** — stav systému viditelný (nahrávám / přepisuji / vkládám); hotkey konzistentní v celém UI.
4. **Opravitelnost** — historie, znovu vložit, oprava podtržených slov, vlastní slovník.
5. **Ne přeplnit** — nastavení a diagnostika nepatří do stejné vrstvy jako „podrž klávesu a mluv“.

---

## Brand voice (3 words)

**Klidný. Přímý. Důvěryhodný.**

- Čeština, tykání v UI (současný stav).
- Vysvětlovat *co se děje*, ne *jaký model běží* — technické detaily do Pokročilého / diagnostiky.
- Privacy jako fakt architektury, ne jako marketingový superlativ.

---

## References (named)

- **macOS System Settings / native utilities** — známé vzory, sidebar u větších oken, systémové fonty.
- **Whispur** (open-source menu bar dictation) — minimální menu dropdown, recording pill s waveform, setup checklist 5/5.
- **Pindrop / „quiet utility“** ethos — menu bar first, žádný Dock pokud user nechce.
- **Editorial print / knižní papír** — warm cream surfaces, jedna committed ink barva (claret), ne rainbow UI.

---

## Anti-references (named)

- **Wispr Flow marketing** — fialové gradienty, „4× faster“, generic AI startup hero.
- **Superwhisper dark premium SaaS** — těžký „transform your voice“ glow, power-user API grid v první vrstvě.
- **WhisperClip-style dark sidebar app** jako *primární* shell — Dictator není „další Electron dashboard“.
- **Apple Dictation** frustrace — dlouhé pauzy bez opravy, nutnost diktovat interpunkci.
- **Diagnostic-first menu bar** — logy, test přepisu, bundle path v hlavním onboardingu (jen pro support režim).

---

## Design principles

1. **Menu bar is home** — hlavní práce probíhá v cílové aplikaci; Dictator je doprovod.
2. **One accent, warm neutrals** — claret + cream/warm gray; systémové success/warning jen pro stav.
3. **Progressive disclosure** — Setup (permissions + první diktát) ≠ Preferences (model, mikrofon, chování) ≠ Advanced (diagnostika, LLM).
4. **Status before settings** — uživatel vždy ví: připraveno / nahrávám / přepisuji / chyba; HUD + menu bar souhlasí.
5. **Hotkey is law** — všechny user-facing stringy používají aktuální `HotkeyPreference` label, ne hardcoded „Option“.
6. **Native AppKit** — `AppTheme` jediný zdroj barev a spacing; žádné web tokeny; light/dark přes dynamic `NSColor`.
7. **Accessibility by default** — VoiceOver labely, oznámení stavů; overlay nesmí být jediný kanál informace.
8. **Competitive bar** — streaming preview a offline jsou diferenciátory; viz `research/competitive-analysis/COMPETITIVE_ANALYSIS.md`.

---

## Success metrics (UX, ne business)

- Čas od key-up do viditelného textu v cílové appce (subjektivně „rychlé“).
- Počet kroků do prvního úspěšného diktátu po instalaci (cíl: ≤ 3 viditelné kroky po grant permissions).
- Uživatel nikdy nehledá „kam šel můj přepis“ — historie / poslední přepis na jedno kliknutí.

---

## Open decisions (k doplnění týmem)

- [ ] Výchozí: zobrazovat hlavní okno po startu, nebo jen menu bar?
- [ ] Výchozí: review-before-paste on nebo off pro firemní rollout?
- [ ] Veřejný název produktu: Dictator vs jiný (právní / brand)?
