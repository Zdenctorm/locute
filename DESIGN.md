# Locute — DESIGN.md

> Google Stitch format (Impeccable). Generováno ze `Locute/UI/AppTheme.swift` a implementovaných komponent. Aktualizujte po změně vizuálního systému; příkazy `/impeccable *` čtou tento soubor. Hub: [IMPECCABLE.md](./IMPECCABLE.md).

---

## 01 Overview

**Creative North Star: „The Quiet Study.“**

Locute vypadá jako **papír a inkoust na stole** — teplé neutrály, jedna hluboká bordó barva, žádný vizuální hluk. Utilita v menu baru, která se objeví jen když mluvíte: HUD nahoře, případně okno historie. Pocit: **důvěryhodný nástroj pro práci**, ne AI experiment.

**Layout philosophy**

- Okna: jeden hlavní vertikální flow (header → obsah → status/actions), padding **40pt** (`windowPadding`).
- Karty: `PanelCardView` — zaoblení **16pt**, border 1pt warm separator, padding **24pt**.
- Menu bar popover / word popover: kořen přes `AppTheme.popoverRootView` (warm `surface`), typografie a tlačítka z `AppTheme`.

**Motion**

- Recording HUD: pulz tečky ~**0.45s** při nahrávání.
- Transient feedback overlay: auto-hide ~**4.5s** chyb.
- Žádné dramatické přechody oken; respektovat macOS.

**Density**

- Střední — více vzduchu u hero/header (`hero` 32pt), těsnější footer (`intimate` 8pt).
- Helper text max **2–3 věty** nad složitými funkcemi; dlouhé legendy do „?“ nebo sekundárního panelu.

---

## 02 Colors

Pojmenování pro copy a AI — mapování v `AppTheme.Color`.

| Token | Descriptive name | Role | sRGB (light baseline) |
|-------|------------------|------|------------------------|
| `accent` | **Deep Claret** | Brand ink — logo, emphasis, transcribing dot | ~107, 33, 41 |
| `brandPaper` | **Cream Paper** | Text/glyph on claret (logo „) | ~247, 239, 232 |
| `surface` | **Warm Desk** | Window background (dynamic) | light ~252,250,247 / dark ~31,26,26 |
| `panel` | **Pressed Paper** | Card fill (dynamic) | light ~239,232,224 / dark ~43,33,33 |
| `separator` | **Warm Rule** | Card borders | light ~217,201,194 / dark ~71,56,56 |
| `title` | **Ink Primary** | `labelColor` | system |
| `body` | **Ink Secondary** | `secondaryLabelColor` | system |
| `recording` | **Live Ember** | Recording / key-held dot | ~209, 71, 56 |
| `danger` | **Claret Alert** | Errors in brand family | ~158, 46, 51 |
| `success` / `warning` | **System Grove / Amber** | Permission granted, busy | system green / orange |

**Color rules**

- **Never** introduce purple/indigo AI gradients or second brand hue.
- **Never** use `systemRed` for brand-adjacent errors on HUD dot — prefer `danger` or `recording` family.
- **Always** tint neutrals warm (surface/panel/separator), not cool gray.
- Accent na tlačítkách: zatím převážně **system rounded** — accent reserved pro logo, čísla kroků, stavy přepisu; zvážit accent fill jen pro jedno primární CTA per window.

---

## 03 Typography

**Stack:** macOS **system** sans (`NSFont.systemFont`) — žádný custom web font. Logo glyph: **Georgia Bold** (fallback Times) pro znak „.

| Role | Token | Size / weight |
|------|-------|----------------|
| Window title | `Font.largeTitle` | 26pt semibold |
| Section title | `Font.title` | 20pt semibold |
| Card headline | `Font.headline` | 14pt semibold |
| Body | `Font.body` | 13pt regular |
| Helper / legend | `Font.footnote` | 12pt regular |
| HUD / status line | `Font.status` | 14pt medium |

**Typography rules**

- Hierarchy: **jeden** largeTitle per window; card titles = headline.
- **Never** ALL CAPS pro celé věty (kromě badge stavů pokud nutné).
- České uvozovky: preferovat „ “ v copy; logo používá jediný glyph „.
- Line length: wrapping labels `lines: 0` pro permission copy; HUD status **1 line** truncate.

---

## 04 Elevation

**Flat by default.** Hloubka = **vrstvy povrchu**, ne drop shadow.

- **Level 0:** `surface` — window background.
- **Level 1:** `panel` + `separator` border — cards, transcription panel.
- **Level 2:** `NSVisualEffectView` `.hudWindow` — floating recording overlay (jediný „glass“ prvek).
- Shadows: pouze systémový shadow na HUD panel (`hasShadow = true`), ne na každé kartě.

**Elevation rules**

- **Never** card-in-card-in-card (max 2 úrovně: surface → panel).
- **Never** heavy drop shadows on settings cards.
- Dark mode: stejná logika vrstev, tmavší warm ink než pure #000.

---

## 05 Components

### Logo (`AppLogoView`)

- 64×64 (settings/launch), rounded rect **22%** radius, fill **Deep Claret**, glyph **Cream Paper** „.
- Accessibility: „Logo Locute“, role image.

### Cards (`AppTheme.card` / `PanelCardView`)

- Corner **16pt**, padding **24pt**, vertical stack spacing **12pt** (`row`).
- `applyPanelChrome` on appearance change — **always** resolve dynamic colors via `effectiveAppearance`.

### Buttons

- Primary: `primaryButton` — rounded, large, keyEquivalent Return.
- Secondary: `secondaryButton` — regular control size.
- Popovery: `AppTheme` tlačítka a `popoverRootView`; bez dalšího chrome karty (plochý surface).

### Recording overlay (`RecordingOverlayController`)

- Top center, **~420×72** min, non-activating panel.
- Dot **10pt**, corner **5pt**; states: recording = Live Ember pulse; transcribing/injecting = Deep Claret; success = system green; failure = avoid systemRed.
- Optional second line: streaming preview footnote (confirmed + draft).

### Menu bar

- Status item square; states change icon (mic / waveform / error) — template where idle.
- **Target pattern** (Whispur): Ready badge, last transcript, Paste again — viz PRODUCT principles.

### Permission rows

- Numbered **32pt semibold claret** digit + stack — **not** nested card per permission.

### History (`TranscriptionPanelView`)

- Panel chrome, internal scroll, separators 1pt Warm Rule.
- Word links: green = learned, orange dotted = low confidence, gray = medium.

### Windows

- Main: `configureMainWindow` min **520×480**, titled.
- Utility/floating: `configureUtilityWindow` level floating.

---

## 06 Do's and Don'ts

### Do

- Držet **jednu** committed accent (Deep Claret) a warm papírové neutrály.
- Ukazovat **aktuální hotkey** ze `HotkeyPreference.current.hintLabel` všude v UI.
- Dávat **okamžitou** zpětnou vazbu při nahrávání (HUD + menu bar + volitelně waveform — roadmap).
- Oddělit **Setup checklist** od dlouhého settings scrollu.
- Používat `AppTheme` factory (`label`, `button`, `badge`, `card`) pro nové views.
- Respektovat light/dark přes named dynamic `NSColor` a `resolved(_:for:)`.

### Don't

- Nepřidávat gradient text, glassmorphism na celé okno, nebo fialovou AI paletu.
- Nevyhazovat diagnostiku, bundle path a „test přepisu“ do prvního onboardingu bez „Pokročilé“.
- Nepiš „Whisper“, „LLM“, „AI“ v primární copy — piš „lokální přepis“, „oprava textu na Macu“.
- Neduplikovat „poslední přepis“ na třech místech bez jasné hierarchie.
- Nepoužívat hardcoded „Option“ pokud user zvolil jinou klávesu.
- Nevytvářet nové barvy mimo `AppTheme.Color` bez aktualizace tohoto souboru.

### Named rules (for AI commands)

| Rule | Meaning |
|------|---------|
| **Quiet Study** | Warm flat surfaces, one ink color, minimal chrome |
| **Menu Home** | Primary UX = menu bar + HUD, not dashboard |
| **Hotkey Law** | All activation copy uses live hotkey label |
| **Trust Surface** | Privacy/offline messaging ≤ 3 bullets near first run |
| **No AI Slop** | No purple gradients, nested marketing cards, generic SaaS hero |

---

## Source of truth in code

- `Locute/UI/AppTheme.swift` — tokens, spacing, fonts, card chrome
- `Locute/UI/AppLogoView.swift` — brand mark
- `Locute/UI/RecordingOverlayController.swift` — HUD behavior
- `research/competitive-analysis/COMPETITIVE_ANALYSIS.md` — UX benchmarks

**Refresh:** po větší UI změně spusť `/impeccable document` (scan) nebo ručně sladit tento soubor s `AppTheme`.
