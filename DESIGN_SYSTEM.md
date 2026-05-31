# Locute — Design System

> **Verze:** 2026-05-30
> **Zdroj tokenů:** `Locute/UI/AppTheme.swift` (ground truth)
> **Figma soubor:** [Locute — Design System](https://www.figma.com/design/q8vqYs24VmW1Inw6EylD88) *(Cover page vytvořena; Foundation + Components čekají na Editor seat)*
> **Vztah k ostatním dokumentům:** BRAND_MANUAL.md = brand pravidla; tento dokument = implementační spec komponent.

---

## Obsah

1. [Barevné tokeny](#1-barevné-tokeny)
2. [Typografická stupnice](#2-typografická-stupnice)
3. [Spacing systém](#3-spacing-systém)
4. [Elevation](#4-elevation)
5. [Motion](#5-motion)
6. [Komponenty](#6-komponenty)
   - [Logo](#61-logo--applogov-iew)
   - [Tlačítka](#62-tlačítka)
   - [Karty (PanelCardView)](#63-karty--panelcardview)
   - [Recording HUD](#64-recording-hud--recordingoverlaycont-roller)
   - [Menu bar](#65-menu-bar--statusbarcontroller)
   - [Permission rows](#66-permission-rows)
   - [Transcription history](#67-transcription-history--transcriptionpanelview)
   - [Popover](#68-popover)
   - [Window chrome](#69-window-chrome)
7. [Dark mode](#7-dark-mode)
8. [Ikony a ikonografie](#8-ikony-a-ikonografie)
9. [Grid a layout patterns](#9-grid-a-layout-patterns)
10. [Komponenty — stavové diagramy](#10-komponenty--stavové-diagramy)
11. [Accessibility spec](#11-accessibility-spec)

---

## 1 Barevné tokeny

Hodnoty přímo z `AppTheme.Color`. Hex = light mode baseline; tam kde je dynamic NSColor, jsou uvedeny obě varianty.

### Brand barvy (statické)

| Token | Název | Hex | sRGB | Použití |
|-------|-------|-----|------|---------|
| `accent` | Deep Claret | `#6B2129` | 0.42 · 0.13 · 0.16 | Logo pozadí, čísla kroků, transcribing dot, emphasis |
| `accentSoft` | Deep Claret 10 % | `#6B2129` @ 10 % | — | Subtilní brand tint, hover/selection backgrounds |
| `brandPaper` | Cream Paper | `#F7F0E8` | 0.97 · 0.94 · 0.91 | Glyph a text na claret površích |

### Surface barvy (dynamic NSColor)

| Token | Název | Light hex | Dark hex | Použití |
|-------|-------|-----------|---------|---------|
| `surface` | Warm Desk | `#FCFAF7` | `#1F1A1A` | Window background |
| `panel` | Pressed Paper | `#F0E8E0` | `#2B2121` | Card fill |
| `separator` | Warm Rule | `#D9C9C2` | `#473838` | Card border 1pt |

### Sémantické barvy

| Token | Název | Hex | Použití |
|-------|-------|-----|---------|
| `recording` | Live Ember | `#D14738` | Recording dot při aktivním nahrávání |
| `danger` | Claret Alert | `#9E2E33` | Error stavy — v brand rodině, ne systemRed |
| `success` | System Grove | `systemGreen` | Permission udělena, success stav |
| `warning` | System Amber | `systemOrange` | Busy / pending stav |
| `title` | Ink Primary | `labelColor` | Primární text |
| `body` | Ink Secondary | `secondaryLabelColor` | Sekundární / helper text |

### Pravidla

- Nikdy přidat fialovou/indigo jako druhý brand hue.
- Na HUD dot error: `danger` nebo `recording` — nikdy `systemRed`.
- Neutrály: vždy warm tint, nikdy cool gray.
- `accent` pouze pro logo, čísla kroků, stavy přepisu.

---

## 2 Typografická stupnice

Z `AppTheme.Font`. System sans (`NSFont.systemFont`) všude; výjimka: logo glyph = Georgia Bold.

| Role | Token | Size | Weight | NSFont |
|------|-------|------|--------|--------|
| Window title | `largeTitle` | 26 pt | Semibold | `systemFont(ofSize: 26, weight: .semibold)` |
| Section title | `title` | 20 pt | Semibold | `systemFont(ofSize: 20, weight: .semibold)` |
| Card headline | `headline` | 14 pt | Semibold | `systemFont(ofSize: 14, weight: .semibold)` |
| Body text | `body` | 13 pt | Regular | `systemFont(ofSize: 13)` |
| Helper / legend | `footnote` | 12 pt | Regular | `systemFont(ofSize: 12)` |
| HUD / status | `status` | 14 pt | Medium | `systemFont(ofSize: 14, weight: .medium)` |
| Logo glyph | — | 64 pt | Bold | Georgia Bold |

### Pravidla

1. **Jeden** `largeTitle` per okno.
2. Nikdy ALL CAPS pro celé věty.
3. České uvozovky: **„ "** (nikdy " " nebo « »).
4. HUD status: 1 řádka, truncate — nikdy wrap.
5. Permission copy: `lines: 0`, word-wrap zapnutý.

---

## 3 Spacing systém

Z `AppTheme.Spacing`.

| Token | Hodnota | Použití |
|-------|---------|---------|
| `windowPadding` | 40 pt | Vnější okraje okna |
| `stack` | 20 pt | Mezi hlavními sekcemi v okně |
| `hero` | 32 pt | Pod brand headerem (dýchání) |
| `intimate` | 8 pt | Footer, helper text grouping |
| `row` | 12 pt | Uvnitř karty — mezi položkami |
| `tight` | 6 pt | Ikona + label pair |
| `cardPadding` | 24 pt | Vnitřní padding `PanelCardView` |
| `section` | 14 pt | Mezera mezi kartami v scrollu |
| `contentInset` | 4 pt | Drobný inset uvnitř prvků |

### Layout grid (okna)

```
┌─────────────────────────────────────────────────────┐
│  40pt                                           40pt │
│  ┌──────────────────────────────────────────────┐   │
│  │  header (largeTitle)                         │   │
│  │                                              │   │
│  │  ── 32pt hero gap ──────────────────────     │   │
│  │                                              │   │
│  │  [PanelCardView]                             │   │
│  │                                              │   │
│  │  ── 14pt section gap ───────────────────     │   │
│  │                                              │   │
│  │  [PanelCardView]                             │   │
│  │                                              │   │
│  │  ── 20pt stack gap ─────────────────────     │   │
│  │                                              │   │
│  │  status / actions (footer)                   │   │
│  └──────────────────────────────────────────────┘   │
│  40pt                                               │
└─────────────────────────────────────────────────────┘
min width: 520 pt · min height: 480 pt
```

---

## 4 Elevation

**Flat by default.** Hloubka přes vrstvy povrchu, ne drop shadow.

| Úroveň | Povrch | Kde |
|--------|--------|-----|
| **0** | `surface` (Warm Desk) | Window background |
| **1** | `panel` + `separator` border 1pt | Cards, transcription panel |
| **2** | `NSVisualEffectView .hudWindow` | Floating recording overlay |

### Pravidla

- Max 2 úrovně: `surface` → `panel`. Card-in-card zakázáno.
- Drop shadow pouze na HUD panel (`hasShadow = true`).
- Settings karty: bez drop shadow.
- Dark mode: stejná logika vrstev, warm ink tón (ne pure `#000`).

---

## 5 Motion

| Prvek | Parametr | Hodnota |
|-------|----------|---------|
| Recording dot pulse | Perioda | ~0.45 s |
| HUD auto-hide (error) | Delay | ~4.5 s |
| Stavové přechody okna | Trvání | Systémové animace macOS |
| Reduced Motion | Override | Respektovat `NSWorkspace.accessibilityDisplayShouldReduceMotion` |

Žádné dramatické přechody oken. Animace jen tam kde přenáší informaci (pulse = nahrávám).

---

## 6 Komponenty

### 6.1 Logo — `AppLogoView`

```
┌──────────────────────────────┐
│                              │  Corner radius: 22% × side
│                              │  (64pt ref → radius 14pt)
│          „                   │
│   (Playfair Display Bold)    │
│                              │
└──────────────────────────────┘

Fill: Deep Claret #6B2129
Glyph: Cream Paper #F7F0E8
```

**Rozměry a kontext:**

| Kontext | Velikost | Corner radius |
|---------|----------|---------------|
| Menu bar status item (nepoužívat logo přímo) | 18×18 pt | — |
| Thumbnail, favicon | 32×32 pt | 7 pt |
| Settings / launch (reference) | 64×64 pt | 14 pt |
| Marketing / web | 256×256 pt+ | 22 % strany |

**Accessibility:** label `"Logo Locute"`, role `.image`.

**Zakázáno:** měnit typeface, přebarvit glyph, přidat shadow, vložit mikrofon/waveform.

---

### 6.2 Tlačítka

#### Primary button — `AppTheme.primaryButton`

```
┌─────────────────────────────────────┐
│         [Title]                     │  bezelStyle: .rounded
│                                     │  controlSize: .large
└─────────────────────────────────────┘
keyEquivalent: Return (\r)
```

- Jeden primary button per okno nebo flow.
- Return key equivalent vždy nastaven.
- VoiceOver: label = title, role = `.button`.

#### Secondary button — `AppTheme.secondaryButton`

```
┌───────────────────────┐
│  [Title]              │  bezelStyle: .rounded
│                       │  controlSize: .regular
└───────────────────────┘
```

- Pro vedlejší akce (Zrušit, Zpět, Přeskočit).
- Bez Return key equivalent.

#### Stavové varianty

| Stav | Chování |
|------|---------|
| Normal | System default bezel |
| Hovered | System default highlight |
| Pressed | System default pressed |
| Disabled | `isEnabled = false`, alpha auto |
| Focused (VoiceOver) | System focus ring |

---

### 6.3 Karty — `PanelCardView`

```
┌─────────────────────────────────────────────┐  ← corner: 16pt
│  24pt padding                               │  ← fill: panel
│                                             │  ← border: 1pt separator
│  [content row]                              │
│  ─── 12pt row gap ──────────────────────    │
│  [content row]                              │
│  ─── 12pt row gap ──────────────────────    │
│  [content row]                              │
│                                     24pt   │
└─────────────────────────────────────────────┘
```

- `applyPanelChrome` volat z `viewDidChangeEffectiveAppearance`.
- Dynamic colors resolve přes `effectiveAppearance` — nikdy přímé `.cgColor`.
- Klíč: `AppTheme.card([views])` vrací `PanelCardView`.

---

### 6.4 Recording HUD — `RecordingOverlayController`

Floating non-activating panel, top center obrazovky.

```
Velikost: ~420 × 72 pt (minimum)
Level: .hudWindow
hasShadow: true
```

#### Layout HUD

```
┌──────────────────────────────────────────────┐
│  ●  [Status text — 14pt medium]              │
│     [Streaming preview — 12pt regular]  opt  │
└──────────────────────────────────────────────┘

●  = dot 10pt, corner 5pt
```

#### Stavové varianty

| Stav | Dot barva | Animace | Status text (CS) | Status text (EN) |
|------|-----------|---------|-----------------|-----------------|
| **Recording** | Live Ember `#D14738` | Pulse 0.45 s | Drž [hotkey] — mluv | Hold [hotkey] — speak |
| **Transcribing** | Deep Claret `#6B2129` | Statická | Přepisuji… | Transcribing… |
| **Injecting** | Deep Claret `#6B2129` | Statická | Vkládám… | Inserting… |
| **Success** | systemGreen | Statická | Vloženo | Done |
| **Failure** | Claret Alert `#9E2E33` | Statická | Nepodařilo se vložit | Could not insert |

**Streaming preview (volitelný 2. řádek):**
- `footnote` (12 pt regular)
- Confirmed text: `body` color; draft text: `body` @ 50 % opacity
- Max 1 řádka, truncate s `…` zleva

**Pravidla:**
- Nikdy `systemRed` pro failure dot.
- Auto-hide na Success/Failure po ~4.5 s.
- VoiceOver announcement při každém stavovém přechodu (`NSAccessibility.post`).
- HUD nesmí být jediný informační kanál — menu bar ikona musí zrcadlit stav.

#### State machine diagram

```
idle ──[key down]──▶ Recording
                         │
                    [key up]
                         ▼
                   Transcribing
                         │
                   [text ready]
                         ▼
                    Injecting
                    /        \
             [success]     [failure]
                ▼               ▼
             Success         Failure
                \               /
                 [auto-hide 4.5s]
                        ▼
                       idle
```

---

### 6.5 Menu bar — `StatusBarController`

#### Ikony (status item)

| Stav | Ikona | Template |
|------|-------|---------|
| Idle / Ready | mic.fill nebo vlastní | Ano (template) |
| Recording | waveform nebo mic.fill + badge | Ne (Live Ember tint) |
| Transcribing | waveform | Ano (template) |
| Error | exclamationmark.circle | Ano (template) |

Stavové změny musí být rozlišitelné labelem, ne jen barvou.

#### Menu struktura (cílový stav — Whispur pattern)

```
┌──────────────────────────────────────────┐
│  ● Připraveno                            │  ← status badge
├──────────────────────────────────────────┤
│  Poslední přepis: „Ahoj světe…"          │  ← kliknutelné (copy)
│  Vložit znovu                            │
├──────────────────────────────────────────┤
│  Nastavení…                              │
├──────────────────────────────────────────┤
│  Diagnostika                           ▶ │  ← submenu
├──────────────────────────────────────────┤
│  Ukončit Locute                          │
└──────────────────────────────────────────┘
```

**Zakázáno v primární vrstvě:**
- Test přepisu, bundle path, logy — patří do Diagnostika submenu.
- Více než 2 akce nad Nastavením.

---

### 6.6 Permission rows

Číslované řádky v Setup checklistu. **Ne** nested card per permission.

```
  ┌────────────────────────────────────────────────────┐
  │  32pt                                              │
  │ ┌──┐                                              │
  │ │ 1 │  Název oprávnění       [Stav / Tlačítko]    │
  │ └──┘  Helper text (1–2 věty, footnote, body@50%)  │
  │  32pt gap                                         │
  │ ┌──┐                                              │
  │ │ 2 │  Název oprávnění       [Stav / Tlačítko]    │
  │ └──┘  Helper text                                 │
  └────────────────────────────────────────────────────┘

Číslo: 32pt semibold, Deep Claret #6B2129
Název: headline (14pt semibold)
Helper: footnote (12pt regular), body color @ 50%
```

**Stavové ikony vedle tlačítka:**

| Stav | Symbol | Barva |
|------|--------|-------|
| Neuděleno | circle | body @ 30 % |
| Čeká | clock | warning |
| Uděleno | checkmark.circle.fill | success |
| Odepřeno | xmark.circle | danger |

---

### 6.7 Transcription history — `TranscriptionPanelView`

```
┌─────────────────────────────────────────────┐  ← panel chrome
│  [Přepis text]                              │
│  ─── 1pt Warm Rule ─────────────────────    │
│  [Přepis text s podtrženými slovy]          │
│    ┌────────────────────┐                  │
│    │ word popover       │  ← popoverRootView│
│    └────────────────────┘                  │
│  ─── 1pt Warm Rule ─────────────────────    │
│  [Přepis text]                              │
└─────────────────────────────────────────────┘
```

#### Word confidence styling

| Confidence | Vizuál | Barva | Ne-barevný indikátor |
|-----------|--------|-------|---------------------|
| Learned | Běžný text | systemGreen tint | tučnější nebo checkmark |
| Low | Tečkované podtržení | systemOrange | tečkované podtržení |
| Medium | Tenké podtržení | body @ 60 % | tenké podtržení |

Word popover: `AppTheme.popoverRootView`, alternativní slova jako tlačítka, `secondaryButton` styl.

---

### 6.8 Popover

Kořen přes `AppTheme.popoverRootView()` — `PopoverChromeView`, warm surface.

```
┌──────────────────────────────────────┐
│  surface (warm)  — bez card chrome   │
│                                      │
│  [content]                           │
│                                      │
│  [AppTheme tlačítka]                 │
└──────────────────────────────────────┘
```

- Bez dalšího card chrome uvnitř popoveru (plochý surface).
- `viewDidChangeEffectiveAppearance` → `refreshSurface()` volat vždy.

---

### 6.9 Window chrome

#### Main window — `AppTheme.configureMainWindow`

```
level: .normal
titleVisibility: .visible
titlebarAppearsTransparent: false
isMovableByWindowBackground: false
collectionBehavior: [.fullScreenPrimary]
minSize: 520 × 480 pt
backgroundColor: surface
```

#### Utility/floating window — `AppTheme.configureUtilityWindow`

```
level: .floating
titleVisibility: .hidden
titlebarAppearsTransparent: true
isMovableByWindowBackground: true
collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary]
backgroundColor: surface
```

---

## 7 Dark mode

Všechny barvy jsou dynamic `NSColor` — viz sekce 1. Logika vrstev je identická; dark mode pouze mění hodnoty tokenů.

| Token | Light | Dark |
|-------|-------|------|
| `surface` | `#FCFAF7` (warm off-white) | `#1F1A1A` (warm near-black) |
| `panel` | `#F0E8E0` (cream) | `#2B2121` (warm dark) |
| `separator` | `#D9C9C2` (warm mid) | `#473838` (warm dark mid) |

**Pravidla:**
- Nikdy hardcoded hex v UI; vždy dynamic `NSColor` přes `AppTheme`.
- `applyPanelChrome` volat z `viewDidChangeEffectiveAppearance` — jinak karta zamrzne v jednom modu.
- `AppTheme.resolved(_:for:)` pro `.cgColor` na CALayer — nikdy přímé `.cgColor`.
- Accent `#6B2129` je statický — funguje na obou površích jako primární emphasis.

### Light / Dark porovnání (klíčové povrchy)

```
LIGHT MODE                    DARK MODE
──────────────────────────    ──────────────────────────
Window:    #FCFAF7            Window:    #1F1A1A
Card:      #F0E8E0            Card:      #2B2121
Border:    #D9C9C2            Border:    #473838
Text:      labelColor         Text:      labelColor
Accent:    #6B2129            Accent:    #6B2129  (stejné)
Recording: #D14738            Recording: #D14738  (stejné)
```

---

## 8 Ikony a ikonografie

Locute používá výhradně **SF Symbols** (system symboly). Žádné custom icon sety.

| Kontext | Symbol | Poznámka |
|---------|--------|----------|
| Menu bar idle | `mic.fill` nebo custom | Template mode |
| Menu bar recording | `waveform` | Live Ember tint |
| Menu bar error | `exclamationmark.circle` | Template mode |
| Permission granted | `checkmark.circle.fill` | systemGreen |
| Permission denied | `xmark.circle` | danger |
| Permission pending | `clock` | warning |
| History item | `text.bubble` | Template |
| Settings | `gear` | Template |
| Word learned | `checkmark` (inline) | systemGreen |
| Word low confidence | tečkované podtržení | systemOrange |

**Pravidla:**
- SF Symbols zachovávají správné optical weights automaticky.
- Nikdy custom icon sety pro funkční ikony — pouze pro logo.
- Template symboly respektují light/dark automaticky.

---

## 9 Grid a layout patterns

### Tři layout vzory

#### Window layout

```
window (min 520 × 480)
  └─ NSScrollView (pinScrollViewToWindow)
       └─ NSStackView (orientation: vertical, spacing: stack=20)
            ├─ header (largeTitle + hero gap 32)
            ├─ PanelCardView (section 14 gap)
            ├─ PanelCardView (section 14 gap)
            └─ footer (intimate 8 gap, footnote)

Outer padding: windowPadding = 40 (leading, trailing, top, bottom)
```

#### Card layout

```
PanelCardView
  └─ NSStackView (orientation: vertical, spacing: row=12)
       ├─ headline label
       ├─ content row
       ├─ content row
       └─ action / status

inner padding: cardPadding = 24 (all sides)
corner: 16 pt
border: 1pt separator
```

#### Popover layout

```
PopoverChromeView (surface background)
  └─ NSStackView (orientation: vertical, spacing: row=12)
       ├─ content
       └─ AppTheme buttons

No card chrome; flat surface only
```

### Zakázané layout vzory

- Sidebar jako primární navigace.
- Card-in-card-in-card (max depth: surface → panel).
- Nutnost scrollovat main okno pro dokončení základní akce.
- Diagnostika / logy v první vrstvě Setup.

---

## 10 Komponenty — stavové diagramy

### Recording HUD

```
                   ┌──────────┐
                   │   idle   │ (hidden)
                   └────┬─────┘
                [key down event]
                        ▼
              ┌──────────────────┐
              │   recording      │ ● Live Ember pulse
              │   "Drž [key]…"   │
              └────────┬─────────┘
                  [key up]
                        ▼
              ┌──────────────────┐
              │  transcribing    │ ● Deep Claret static
              │  "Přepisuji…"    │
              └────────┬─────────┘
                 [text ready]
                        ▼
              ┌──────────────────┐
              │   injecting      │ ● Deep Claret static
              │   "Vkládám…"     │
              └──┬───────────────┘
          ┌──────┴──────┐
          ▼              ▼
  ┌──────────────┐  ┌────────────────┐
  │   success    │  │    failure     │
  │ ● system     │  │ ● Claret Alert │
  │   green      │  │ "Nepodařilo…"  │
  └──────┬───────┘  └───────┬────────┘
         └──── 4.5s ────────┘
                    ▼
                  idle
```

### Permission row state machine

```
[unknown]  ──[check]──▶  [not granted]  ──[user grants]──▶  [granted]
                               │                                  │
                           [denied]                           [revoked]
                               ▼                                  ▼
                           [denied]                          [not granted]
```

### Menu bar icon states

```
[idle]  ←──────────────────────────────────────────────────┐
  │                                                         │
  └──[key down]──▶ [recording] ──[key up]──▶ [transcribing]┤
                                                            │
[error] ←──[failure]──  [injecting] ←──[text]── [transcribing]
  │                           │
  └──[dismiss]──▶ [idle]    [success]──▶ [idle]
```

---

## 11 Accessibility spec

### Cíl

WCAG 2.1 AA pro všechny interaktivní prvky a informační povrchy.

### Per-komponent požadavky

| Komponenta | VoiceOver label | Role | Announcements |
|------------|-----------------|------|---------------|
| `AppLogoView` | `"Logo Locute"` | `.image` | — |
| Primary button | title | `.button` | — |
| Secondary button | title | `.button` | — |
| Menu bar status item | aktuální stav (např. `"Locute — Připraveno"`) | `.menuItem` | při změně stavu |
| HUD Recording | `"Nahrávám — pusť klávesu pro přepis"` | `.staticText` | ano (post) |
| HUD Transcribing | `"Přepisuji"` | `.staticText` | ano (post) |
| HUD Success | `"Text vložen"` | `.staticText` | ano (post) |
| HUD Failure | `"Vložení selhalo"` | `.staticText` | ano (post) |
| Permission row | `"[název], [stav]"` | `.group` | při grant/revoke |
| History item | text přepisu | `.staticText` | — |
| Word (low confidence) | `"[slovo], nízká jistota"` | `.button` | — |

### Implementační pravidla

1. `AccessibilitySupport.configure(_:label:)` pro každý interaktivní prvek.
2. `NSAccessibility.post(element:notification:)` pro stavové přechody HUD.
3. Barevné stavové indikátory musí mít **ne-barevný** párový indikátor (ikona nebo podtržení).
4. Overlay (HUD) nesmí být jediný informační kanál — menu bar ikona musí zrcadlit stav.
5. Reduced Motion: HUD pulse respektuje `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`.

### Kontrastní poměry

| Kombinace | Poměr | WCAG |
|-----------|-------|------|
| Cream Paper na Deep Claret | ~8:1 | ✅ AAA |
| `labelColor` na `surface` light | ~14:1 | ✅ AAA |
| `secondaryLabelColor` na `surface` light | ~5.5:1 | ✅ AA |
| Live Ember na `surface` light | ~3.2:1 | ⚠️ AA large text only |
| Deep Claret na `surface` light | ~7.1:1 | ✅ AAA |

> **Poznámka:** Live Ember (`#D14738`) na bílém pozadí neprojde AA pro small text. Používat pouze jako dot indikátor (≥10pt), ne pro body text.

### Audit workflow

Menu bar → Analýza zpřístupnění (VoiceOver)… — viz `ACCESSIBILITY_AUDIT.md`.

---

## Figma soubor

**URL:** [https://www.figma.com/design/q8vqYs24VmW1Inw6EylD88](https://www.figma.com/design/q8vqYs24VmW1Inw6EylD88)

**Stav:** Cover page vytvořena. Foundation + Components stránky čekají na Editor seat (aktuální account má View seat — zablokováno Figma rate limitem).

**Po upgradu seatu:** spustit `claude` v tomto repozitáři a napsat `pokračuj ve stavbě Figma design systému`, agent doplní Foundation a Components stránky s color styles, text styles a všemi komponentami z tohoto dokumentu.
