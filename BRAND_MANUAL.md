# Locute — Brand Manual

> **Verze:** 2026-05-30
> **Autoritativní zdroj pro:** brand identitu, positioning, hlas a tón, vizuální systém, copy vzory.
> **Nesuperseduje:** `DESIGN.json` (machine-readable tokeny pro tooling), `AppTheme.swift` (runtime barvy), `PRODUCT.md` (product goals a roadmap), `COMPETITIVE_ANALYSIS.md` (research).
> **Superseduje:** `BRAND.md` (brand name, positioning), relevantní sekce `PRODUCT.md` (hlas a tón), `DESIGN.md` (pro non-kódové použití).

---

## 01 Brand Identity

### Název

| | |
|--|--|
| **Správně** | **Locute** |
| **Nikdy** | LOCUTE · locute · LocuTe |

Název se vždy píše s velkým L a malými zbývajícími písmeny. V názvu souboru nebo bundle ID se používá malými: `locute`, `com.example.locute`.

### Výslovnost

| Jazyk | Foneticky | IPA |
|-------|-----------|-----|
| Angličtina | **LO-kjut** | /ˈloʊ.kjuːt/ |
| Čeština | **lo-kjút** | /ˈlo.kjuːt/ |

### Etymologie

*local* + *elocute/speak* — přepis na zařízení, hlas zůstává doma.

Tuto etymologii stačí zmínit jednou (onboarding, web, about okno). Neopakovat v každém kontextu.

### Tagline systém

Tři úrovně. Každá má svůj kontext — nemíchat je na jednom místě.

| Úroveň | EN | CS | Kdy použít |
|--------|----|----|------------|
| **Primární** | Fast, accurate dictation on your Mac. | Rychlý a přesný přepis na Macu. | Hlavní headline — web, App Store, onboarding titulek |
| **Privacy** | Your voice never leaves your device. | Hlas neopustí tvůj Mac. | Pod primárním headline nebo jako standalone benefit |
| **Proof** | See text while you hold the key. | Text vidíš už při držení klávesy. | Feature kontexty — streaming preview, jak to funguje |

### Positioning statement

Locute je nativní macOS utilita pro push-to-talk diktování v češtině. Přepis běží lokálně na Apple Silicon, žádná data neopouštějí Mac. Není to SaaS s offline módem — je to offline nástroj, který nepotřebuje cloudový účet, předplatné ani připojení k internetu po prvním stažení modelu.

---

## 02 Konkurenční pozice

### Diferenciace

| Osa | Locute | Konkurent | Klíčová zpráva |
|-----|--------|-----------|----------------|
| Cloud vs. local | Offline-first | Wispr Flow (cloud default) | „žádné API volání, ani pro editaci" |
| Jazyk | Čeština fixní, optimalizovaná | Superwhisper (100+ jazyků, obecný) | „jeden jazyk, přesně nastrojený" |
| Architektura | WhisperKit na Apple Silicon | Aqua Voice (streaming cloud) | „stejná latence, jiná architektura" |
| Gesto | Push-to-talk hold | Apple Dictation (toggle + pauzy) | „drž klávesu, pusť — hotovo" |
| Cena | Jednorázová nebo žádná | Wispr Flow $12–15/měs., Aqua $8/měs. | „bez předplatného, bez účtu" |

### Sémantický kvadrant

Locute sedí v kvadrantu **Quiet × Local**. To jsou dvě osy k ochraně:

- **Quiet:** žádný vizuální hluk, žádné SaaS hero, editorial estetika
- **Local:** offline-first architektura, ne marketing claim

Každá nová funkce, kopie nebo vizuální rozhodnutí testujte: posouvá nás to z tohoto kvadrantu? Pokud ano, zastavit.

### IT admin pitch

Tři fakta pro skeptického správce systémů:

- Zvuk se zpracovává lokálně v RAM; neopouští Mac ani jako metadata.
- Aplikace nevyžaduje žádný cloudový účet, API klíč ani internetové připojení po stažení modelu (~630 MB, jednorázově).
- Entitlements: pouze `com.apple.security.device.audio-input` a Accessibility API; žádný sandbox.

### Zakázaná jména a vzory

Nepoužívat jako produktové jméno ani v copy: *Flow*, *Super*, *Voca*, *Whisper* (jako brand), *Willow*, *Glimpse*, *VocaMac*.

---

## 03 Hlas a tón

### Tři pilíře

**Klidný. Přímý. Důvěryhodný.**

Locute mluví jako nástroj, který prostě funguje — ne jako startup, který se snaží ohromit.

### Jazykový register

| Pravidlo | Správně | Špatně |
|----------|---------|--------|
| Čeština: neformální | „Drž klávesu a mluv." | „Podržte klávesu a mluvte." |
| Angličtina: deklarativní | „Text appears where your cursor is." | „Transform the way you communicate!" |
| Stav jako fakt | „Přepisuji…" | „Pracuji na vašem přepisu…" |
| Privacy jako architektura | „Audio zůstane v RAM tvého Macu." | „Vaše soukromí je naší prioritou." |
| Technické detaily: schovat | „lokální přepis" | „WhisperKit large-v3-v20240930_turbo" |

### Zakázaná slovní zásoba

| Zakázaný výraz | Proč | Alternativa |
|----------------|------|-------------|
| „AI" jako primární label | Hype slovo, vágní | „lokální přepis" / „local transcription" |
| „transform your workflow" | Generic SaaS hero | konkrétní akce: „text se vloží" |
| „powered by AI/cloud" | Buď nepravda, nebo slab argument | vynechat nebo uvést architekturu |
| „seamless", „intelligent" | Marketing slop | konkrétní adjektivum nebo žádné |
| „4× faster", „90% accurate" | Claim bez zdroje | konkrétní měřitelný fakt nebo nic |
| „Whisper" jako produktové jméno | Přivlastnění cizího projektu | „WhisperKit" pro technický kontext, jinak vynechat |
| hardcoded „Option ⌥" | Hotkey Law — uživatel mohl přenastavit | `HotkeyPreference.current.hintLabel` |
| „Vloženo pomocí Locute" | Přidávání podpisu bez souhlasu | nic |

### No AI Slop — checklist

Před publikací jakékoliv copy (UI string, web, dokumentace) projít:

1. Obsahuje copy superlativ bez zdroje? → smazat nebo doložit
2. Je v copy slovo „AI" nebo „intelligent"? → nahradit konkrétním popisem akce
3. Slibuje copy cloudovou funkci, kterou Locute nedělá? → opravit
4. Je hotkey v copy hardcoded jako „Option"? → použít live label
5. Vypadá copy jako generic SaaS landing page? → přeformulovat na utility, ne produkt

### Tři copy tiery

| Tier | Délka | Pravidlo | Příklad |
|------|-------|----------|---------|
| **In-app UI** | Co nejkratší | Vždy živý hotkey label; stav jako jedno slovo nebo věta | „Přepisuji…" |
| **Onboarding** | 2–3 věty na krok | Result-first — co se stane, ne co je potřeba udělat | „Text se vloží tam, kde máš kurzor — v jakékoliv aplikaci." |
| **External/marketing** | Headline + 1 sub + 1 proof | Ne víc než tři bloky na jedné stránce | viz tagline systém výše |

---

## 04 Logo a značka

### Anatomie

- **Glyph:** „ (české otevírací uvozovky), sazba Georgia Bold
- **Barva glyphu:** Cream Paper — `sRGB(0.97, 0.94, 0.91)` / `#F7F0E8`
- **Barva pozadí:** Deep Claret — `sRGB(0.42, 0.13, 0.16)` / `#6B2129`
- **Tvar:** rounded rect, corner radius 22 % délky strany

### Referenční velikosti

| Kontext | Velikost | Corner radius |
|---------|----------|---------------|
| Minimální (menu bar) | 16×16 pt | 3–4 pt |
| Čitelné (thumbnail, web favicon) | 32×32 pt | 7 pt |
| Referenční (settings, launch) | 64×64 pt | 14 pt |
| Marketing / velký kontext | 256×256 pt+ | 22 % strany |

### Clear space

Minimálně polovina šířky loga ze všech čtyř stran.

### Accessibility label

`"Logo Locute"` — neměnit, odpovídá implementaci `AppLogoView`.

### Povolené pozadí

- Deep Claret fill (primární, výchozí)
- `surface` / `panel` barvy ze systému
- bílá (#FFFFFF)

### Zakázané použití

- Deformovat poměr stran
- Změnit typeface glyphu (Georgia Bold — pouze)
- Přebarvit glyph na cokoliv jiného než Cream Paper
- Přidat drop shadow na glyph nebo pozadí
- Umístit na barevné pozadí mimo povolenou paletu
- Přidat mikrofonový symbol nebo waveform do loga (logo je typografické, ne ikonografické)

> **Poznámka:** Starý návrh ikony (tmavý rounded square, bílý mikrofon, modro-fialová) byl zamítnut. Kanonická finální značka je „ na šarlatovém pozadí.

---

## 05 Barevný systém

### Filozofie

Papír a inkoust na stole — teplé neutrály, jedna committed brand barva, žádné gradienty.

### Kompletní paleta

Hodnoty přímo z `AppTheme.swift` (ground truth):

| Token | Descriptive name | Role | sRGB light | Hex light | sRGB dark | Hex dark |
|-------|------------------|------|------------|-----------|-----------|----------|
| `accent` | **Deep Claret** | Brand ink — logo, emphasis, transcribing | 0.42, 0.13, 0.16 | `#6B2129` | — | — |
| `accentSoft` | **Deep Claret 10 %** | Subtle brand tint, backgrounds | stejné, α 0.10 | — | — | — |
| `brandPaper` | **Cream Paper** | Text/glyph na claret površích | 0.97, 0.94, 0.91 | `#F7F0E8` | — | — |
| `surface` | **Warm Desk** | Window background | 0.99, 0.98, 0.97 | `#FCFAF7` | 0.12, 0.10, 0.10 | `#1F1A1A` |
| `panel` | **Pressed Paper** | Card fill | 0.94, 0.91, 0.88 | `#F0E8E0` | 0.17, 0.13, 0.13 | `#2B2121` |
| `separator` | **Warm Rule** | Card borders 1 pt | 0.85, 0.79, 0.76 | `#D9C9C2` | 0.28, 0.22, 0.22 | `#473838` |
| `title` | **Ink Primary** | Primární text | `labelColor` | — | — | — |
| `body` | **Ink Secondary** | Sekundární text | `secondaryLabelColor` | — | — | — |
| `recording` | **Live Ember** | Nahrávání — klávesa držena | 0.82, 0.28, 0.22 | `#D14738` | — | — |
| `danger` | **Claret Alert** | Chybové stavy v brand rodině | 0.62, 0.18, 0.20 | `#9E2E33` | — | — |
| `success` | **System Grove** | Permission udělena, OK stav | `systemGreen` | — | — | — |
| `warning` | **System Amber** | Busy stav | `systemOrange` | — | — | — |

### Čtyři barevné zákony

1. **Nikdy** nevnést fialovou, indigo nebo modrou jako druhý brand hue.
2. **Nikdy** nepoužít `systemRed` na HUD dot — místo toho `danger` nebo `recording`.
3. **Vždy** tintovat neutrály teplou stranou (surface/panel/separator), ne cool gray.
4. **Accent** je rezervován pro logo, čísla kroků a stavy přepisu — ne pro každé tlačítko.

### Light/dark mode

Stejná logika vrstev v obou módech. V dark mode jsou barvy tmavší warm ink, ne pure `#000000`. Dynamické barvy resolve přes `AppTheme.resolved(_:for:)` — nikdy přímé `.cgColor` bez kontextu appearance.

### Kontrast (WCAG)

Cream Paper (`#F7F0E8`) na Deep Claret (`#6B2129`) prochází AA pro velký text. Pro body text (13 pt) kontrast ověřit — nepoužívat Cream Paper na Claret pro odstavce textu.

---

## 06 Typografie

### Stack

Všude macOS system sans (`NSFont.systemFont`) — žádný custom font, žádný web font.

**Výjimka:** Logo glyph „ sází se výhradně v **Georgia Bold** (fallback Times New Roman). Tato výjimka platí pouze pro logo, nikde jinde.

### Typografická stupnice

Hodnoty z `AppTheme.Font`:

| Role | Token | Velikost | Tloušťka | Použití |
|------|-------|----------|----------|---------|
| Window title | `largeTitle` | 26 pt | semibold | Jeden per okno max |
| Section title | `title` | 20 pt | semibold | Hlavní sekce |
| Card headline | `headline` | 14 pt | semibold | Nadpis karty |
| Body text | `body` | 13 pt | regular | Obecný UI text |
| Helper / legend | `footnote` | 12 pt | regular | Max 2–3 věty |
| HUD / status | `status` | 14 pt | medium | Jedna řádka HUD |

### Pět typografických pravidel

1. Jeden `largeTitle` per okno — více je hierarchický chaos.
2. Nikdy ALL CAPS pro celé věty.
3. České uvozovky v copy: **„ "** (ne " " ani « »); logo používá otevírací „ jako glyph.
4. HUD status: maximálně 1 řádka, truncate — nikdy wrapping.
5. Permission a help copy: `lines: 0`, word-wrap zapnutý.

---

## 07 Layout a spacing

### Spacing tokeny

Hodnoty z `AppTheme.Spacing`:

| Token | Hodnota | Použití |
|-------|---------|---------|
| `windowPadding` | 40 pt | Vnější margin okna |
| `stack` | 20 pt | Mezi hlavními sekcemi |
| `hero` | 32 pt | Pod brand headerem (dýchat) |
| `intimate` | 8 pt | Footer / helper text grouping |
| `row` | 12 pt | Uvnitř karty, mezi položkami |
| `tight` | 6 pt | Ikona + label pair |
| `cardPadding` | 24 pt | Vnitřní padding karty |
| `section` | 14 pt | Mezi kartami v scrollu |
| `contentInset` | 4 pt | Drobný inset uvnitř prvků |

### Tři layout vzory

**Window layout:** Jeden vertikální flow, header → obsah → status/akce. Žádný sidebar jako primární navigace.

**Card layout:** `PanelCardView` — corner 16 pt, border 1 pt Warm Rule, padding 24 pt, inter-item 12 pt (`row`). `applyPanelChrome` volat vždy z `viewDidChangeEffectiveAppearance`.

**Popover layout:** Plochý surface bez card chrome — `AppTheme.popoverRootView` (warm surface), `AppTheme` tlačítka.

### Elevation systém

| Úroveň | Povrch | Kde |
|--------|--------|-----|
| 0 | `surface` — Warm Desk | Window background |
| 1 | `panel` + `separator` border | Karty, transcription panel |
| 2 | `NSVisualEffectView .hudWindow` | Floating recording overlay — jedině zde |

**Pravidla:**
- Nikdy card-in-card-in-card (max 2 úrovně: surface → panel).
- Nikdy drop shadow na settings kartách.
- Systémový shadow pouze na HUD panel (`hasShadow = true`).
- Minimální velikost main window: 520×480 pt.

---

## 08 UI Komponenty

### AppLogoView

- **Rozměry:** 64×64 pt (reference); 22 % corner radius
- **Fill:** Deep Claret; **Glyph:** Cream Paper „, Georgia Bold
- **VoiceOver:** `"Logo Locute"`, role `.image`
- **Minimum:** 32×32 pt pro jakýkoliv zobrazovaný kontext

### RecordingOverlayController (HUD)

- **Pozice:** top-center, non-activating panel, `.hudWindow`
- **Rozměry:** ~420×72 pt min
- **Dot:** 10 pt, corner 5 pt

| Stav | Barva | Animace |
|------|-------|---------|
| Recording | Live Ember (`#D14738`) | Pulse 0.45 s |
| Transcribing | Deep Claret (`#6B2129`) | statická |
| Injecting | Deep Claret (`#6B2129`) | statická |
| Success | `systemGreen` | statická, auto-hide ~4.5 s |
| Failure | Claret Alert (`#9E2E33`) | statická, auto-hide ~4.5 s |

- Nepoužívat `systemRed` pro failure — zůstat v brand family.
- Volitelný druhý řádek: streaming preview v `footnote` — confirmed text + draft text.
- VoiceOver announcements pro každý stavový přechod (přes `NSAccessibility.post`).

### StatusBarController (menu bar)

- Ikona: template (idle), mic/waveform/error pro aktivní stavy
- Stavy ikony musí být rozlišitelné labelem, ne jen barvou

**Cílová menu struktura (Whispur pattern):**
```
Ready / Nahrávám / Přepisuji      ← status badge
─────────────────────────────
Poslední přepis: "…"              ← kliknutelné pro copy
Vložit znovu                      ← Paste again
─────────────────────────────
Nastavení…
─────────────────────────────
Diagnostika ▶                     ← submenu, NE v primární vrstvě
Ukončit Locute
```

### PanelCardView (cards)

- Corner 16 pt, padding 24 pt (`cardPadding`), spacing 12 pt (`row`)
- Separator border 1 pt Warm Rule
- `applyPanelChrome` při každé změně appearance

### Tlačítka

- **Primary** (`primaryButton`): bezelStyle `.rounded`, size `.large`, keyEquivalent `\r`
- **Secondary** (`secondaryButton`): bezelStyle `.rounded`, controlSize `.regular`
- V popoverech: `AppTheme` tlačítka na `popoverRootView`; bez card chrome

### Permission rows

- 32 pt semibold Deep Claret číslo + stack
- **Ne** nested card per row; permission = řádka, ne karta

### TranscriptionPanelView (history)

- Panel chrome, internal scroll, separátory 1 pt Warm Rule
- Word confidence: zelená = learned, oranžová tečkovaná = nízká jistota, šedá = střední
- Barevné označení musí mít i ne-barevný indikátor (ikona nebo podtržení) — přístupnost

---

## 09 Pět designových zákonů

Tyto názvy jsou stabilní reference — používají se v code review, critique příkazech a onboarding checklistech.

### Quiet Study

**Teplé ploché povrchy, jedna ink barva, minimální chrome.**

Zakazuje: gradient fills, cool gray neutrály, více než 2 elevation úrovně, fialové/modré brand barvy, AI-glow efekty.

✓ Správně: nová karta používá `surface`/`panel` tokeny, border přes `separator`.
✗ Špatně: nová karta s custom `NSColor(red:0.2 green:0.2 blue:0.8)` pozadím.

### Menu Home

**Primární UX žije v menu baru a HUD, ne v dashboard okně.**

Zakazuje: nutnost otevírat hlavní okno pro dokončení přepisu; diagnostické možnosti v primární menu vrstvě.

✓ Správně: přepis proběhne kompletně přes HUD; hlavní okno je volitelná historie.
✗ Špatně: „zkontroluj přepis v hlavním okně" jako součást core loop.

### Hotkey Law

**Všechna copy referující na aktivační gesto používá živý label z `HotkeyPreference.current.hintLabel`.**

Zakazuje: jakýkoliv string obsahující literální „Option" nebo „⌥" mimo rendering aktuálně nastavené hodnoty.

✓ Správně: `"Drž \(HotkeyPreference.current.hintLabel) a mluv."`
✗ Špatně: `"Drž Option a mluv."`

### Trust Surface

**Offline/privacy messaging jako faktický souhrn architektury (≤ 3 odrážky, blízko prvního spuštění), ne marketingový jazyk.**

Zakazuje: „vaše soukromí je naší prioritou", dedicované Privacy Promise okno se štítem, více než jedna obrazovka věnovaná privacy claims.

✓ Správně: tři věty v onboarding checklistu — co data nedělají.
✗ Špatně: full-screen „Privacy Promise" s animovaným zámkem.

### No AI Slop

**Žádné fialové/indigo gradienty, žádné generické SaaS hero vzory, žádné „AI" jako marketingový label.**

Zakazuje: „powered by AI", gradient text, „intelligent", feature-gated splash screens, nested marketing cards v UI.

✓ Správně: „lokální přepis" / „local transcription"
✗ Špatně: „AI-powered dictation for the modern workflow"

---

## 10 Přístupnost

### Cíl

WCAG 2.1 AA tam, kde AppKit a VoiceOver umožňují měřitelné chování.

### Požadované chování na každém povrchu

| Povrch | Požadavek |
|--------|-----------|
| Všechny interaktivní prvky | VoiceOver label přes `AccessibilitySupport.configure` |
| HUD stavové přechody | `NSAccessibility.post` announcement — overlay nesmí být jediný informační kanál |
| Menu bar ikona | Stavové změny musí být rozlišitelné labelem, ne jen barvou |
| Word confidence | Ikona + barva (nikdy jen barva); oranžová = tečkované podtržení + barva |
| Reduced Motion | HUD pulse respektuje `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` (roadmap) |

### VoiceOver label konvence

| Komponenta | Label |
|------------|-------|
| `AppLogoView` | `"Logo Locute"` |
| HUD recording | `"Nahrávám — pusť klávesu pro přepis"` |
| HUD transcribing | `"Přepisuji"` |
| HUD success | `"Text vložen"` |
| HUD failure | `"Vložení selhalo"` |

### Audit

Spustit přes: menu bar → Analýza zpřístupnění (VoiceOver)… → viz `ACCESSIBILITY_AUDIT.md` pro kompletní workflow.

---

## 11 Copy vzory a string konvence

### HUD strings

Přesné schválené stringy. Vždy jedna řádka, hotkey z live labelu.

| Stav | CS | EN |
|------|----|----|
| Recording | Drž [hotkey] — mluv | Hold [hotkey] — speak |
| Transcribing | Přepisuji… | Transcribing… |
| Injecting | Vkládám… | Inserting… |
| Success | Vloženo | Done |
| Failure | Nepodařilo se vložit | Could not insert |

### Menu bar strings

| Položka | CS | EN |
|---------|----|----|
| Status ready | Připraveno | Ready |
| Last transcript header | Poslední přepis | Last Transcription |
| Paste again | Vložit znovu | Paste Again |
| Settings | Nastavení… | Settings… |
| Diagnostics submenu | Diagnostika | Diagnostics |
| Quit | Ukončit Locute | Quit Locute |

### Onboarding pattern

```
[číslo]  [akce — imperativ]
         [expected result — 1 věta]
```

Příklad:
```
1  Povol přístup k mikrofonu
   Locute potřebuje slyšet tvůj hlas pro přepis.

2  Povol přístupnost
   Locute vkládá text přes Accessibility API tam, kde máš kurzor.

3  Podrž [hotkey] a promluv
   Text se vloží tam, kde máš kurzor — v jakékoliv aplikaci.
```

### Error pattern

**Co se stalo + co udělat.** Nikdy blame uživateli, nikdy název modelu.

✓ Správně: „Vložení selhalo. Přidej Locute do Nastavení → Soukromí → Přístupnost."
✗ Špatně: „Error: CGEventPost failed (model: large-v3-v20240930_turbo)"

### Trust Surface šablona

Přesně tři odrážky, nic víc. Umístit blízko prvního spuštění nebo modelu info.

```
• Zvuk zůstane v RAM tvého Macu.
• Přepis probíhá lokálně — žádné API.
• Telemetrie neexistuje.
```

EN verze:
```
• Audio stays in your Mac's RAM.
• Transcription runs locally — no API calls.
• No telemetry.
```

### Zakázané stringy

- `"Whisper"` jako standalone noun v user-facing copy
- `"AI"` jako primární label
- Hardcoded `"Option"` nebo `"⌥"` místo live hotkey labelu
- `"Error"` bez kontextu (co se stalo, co dělat)
- Procentuální accuracy claims bez zdroje
- Podpis „Vloženo pomocí Locute" bez souhlasu uživatele

---

## 12 Technická identita

### AppBrand.swift

Ground truth pro kódovou vrstvu (`Locute/Core/AppBrand.swift`):

| Konstanta | Hodnota | Použití |
|-----------|---------|---------|
| `AppBrand.displayName` | `"Locute"` | UI, okna, systémové dialogy |
| `AppBrand.storageDirectoryName` | `"Locute"` | Cesty na disku |
| `AppBrand.legacyStorageDirectoryName` | `"Dictator"` | Migrace při prvním spuštění |
| `AppBrand.bundleFileName` | `Locute.app` | z `Bundle.main` |
| `AppBrand.canonicalInstallPath` | `/Applications/Locute.app` | |

### Technické identifikátory

| Vrstva | Hodnota |
|--------|---------|
| Bundle ID | `com.example.locute` |
| Application Support | `~/Library/Application Support/Locute/` |
| Logs | `~/Library/Logs/Locute/` |
| GitHub repo | `Zdenctorm/locute` |

### Chain pravdy

```
AppTheme.swift          ← ground truth pro runtime barvy a spacing
    ↓
DESIGN.json             ← machine-readable tokeny pro tooling
    ↓
BRAND_MANUAL.md         ← autoritativní prose — semantic meaning a pravidla
    ↓
DESIGN.md               ← implementation guide pro nové views
```

Při konfliktu: **kód je pravda pro hodnoty tokenů**; **tento manuál je pravda pro sémantický význam a pravidla použití**.

### Update sequence

| Co se mění | Update pořadí |
|------------|--------------|
| Barva nebo spacing | AppTheme.swift → DESIGN.json → BRAND_MANUAL.md §05/07 |
| Nová komponenta | AppTheme.swift → BRAND_MANUAL.md §08 → DESIGN.md §05 |
| Positioning nebo tagline | BRAND_MANUAL.md §01/02 → BRAND.md (nebo jeho retire) |
| Nová copy konvence | BRAND_MANUAL.md §11 |

---

## 13 Anti-vzory

Konsolidovaný vetůjící seznam. Každá položka je dostatečně konkrétní pro review comment.

### Brand / název

- `"Whisper app"` nebo `"WhisperKit"` jako produktový název v UI
- Jakýkoliv název konkurenčního vzoru: Flow, Super, Voca, VocaMac, Glimpse
- Locute psáno jinak než `Locute` (bez výjimek)

### Vizuální

- Fialové/indigo gradienty — ať už jako brand nebo AI marker
- Glassmorphism na celé okno (`.hudWindow` je limit, dál nejít)
- Rainbow nebo multi-hue stavové indikátory
- Drop shadow na settings kartách
- Cool gray neutrály místo warm papír tónů
- Dock ikona bez explicitního souhlasu uživatele

### Copy

- `"AI-powered"`, `"transform your workflow"`, `"supercharge"`, `"intelligent"`
- Accuracy claim bez měřitelného zdroje
- Hardcoded `"Option"` nebo `"⌥"` kdykoliv user mohl přenastavit hotkey
- `"Error"` samotné bez popisu stavu a dalšího kroku
- Privacy slib jako marketingový claim (`"vaše soukromí je naší prioritou"`)
- Podpis vloženého textu

### Architektura / UX

- Cloud inference jako výchozí mód
- 7-tab sidebar jako primární navigace (Superwhisper anti-vzor)
- Onboarding zobrazující logy, bundle path nebo test přepisu dřív než permissions
- Nutnost hlavního okna pro dokončení core loop (přepis)
- Nested card-in-card-in-card struktura
- Screenshot capture kontextu cílové aplikace (Wispr Flow pattern — Locute to dělat nebude)
- Analytics framework nebo crash reporter odesílající data

### Co Locute explicitně nedělá

- Screenshot capture aktivní aplikace před/po přepisu
- Cloud inference (ani jako opt-in v MVP)
- Uživatelský účet nebo předplatné
- Telemetrie nebo anonymní usage data
- Přepis hodinových nahrávek ze souborů (to je MacWhisper use case)
