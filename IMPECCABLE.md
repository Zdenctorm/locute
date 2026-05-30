# Impeccable — Locute

Kompletní kontext pro příkazy `/impeccable *` v tomto repozitáři. Agent při každém spuštění načte `PRODUCT.md` a `DESIGN.md` ze kořene projektu.

---

## Stav setupu

| Soubor / složka | Účel |
|-----------------|------|
| [PRODUCT.md](./PRODUCT.md) | Kdo, proč, principy, anti-reference |
| [DESIGN.md](./DESIGN.md) | Vizuál (Stitch formát), North Star „The Quiet Study“ |
| [DESIGN.json](./DESIGN.json) | Strojově čitelné tokeny (barvy, spacing) |
| [BRAND.md](./BRAND.md) | Veřejný název **Locute**, positioning, tagline |
| [.cursor/skills/impeccable/](./.cursor/skills/impeccable/) | Skill + reference pro všechny sub-příkazy |
| [.impeccable/critique/ignore.md](./.impeccable/critique/ignore.md) | Výjimky z critique (commitnuté) |
| [.impeccable/critique/`*.md`](./.impeccable/critique/) | Snapshoty z `/impeccable critique` (gitignored) |
| [research/competitive-analysis/](./research/competitive-analysis/) | UX benchmarky konkurence |

**Register:** `product` (nativní macOS utilita, ne marketing web).

**Live mode (`/impeccable live`):** pro tento projekt **nepoužitelný** — UI je AppKit/Swift, ne HTML. Iterace dělej v Xcode nebo popiš změny v critique → polish.

---

## Instalace skillu (jednou na stroji)

```bash
cd /path/to/dictator
npx impeccable skills install --yes
```

Ověření:

```bash
node .cursor/skills/impeccable/scripts/context.mjs | head -5
```

Mělo by vypsat `# Locute — PRODUCT.md`, ne `NO_PRODUCT_MD`.

Bootstrap lokální složky (volitelné, obnoví `.impeccable`):

```bash
./scripts/setup-impeccable.sh
```

---

## Doporučené cíle (target) pro příkazy

| Surface | Soubor(y) | Příkaz |
|---------|-----------|--------|
| Menu bar | `Dictator/UI/StatusBarController.swift` | `/impeccable critique Dictator/UI/StatusBarController.swift` |
| Onboarding / oprávnění | `Dictator/UI/SetupWindowController.swift` | `/impeccable onboard Dictator/UI/SetupWindowController.swift` |
| Nastavení (prefs) | `Dictator/UI/PreferencesWindowController.swift` | `/impeccable clarify Dictator/UI/PreferencesWindowController.swift` |
| Recording HUD | `Dictator/UI/RecordingOverlayController.swift` | `/impeccable polish Dictator/UI/RecordingOverlayController.swift` |
| Design tokens | `Dictator/UI/AppTheme.swift` | `/impeccable document` (refresh DESIGN.md) |
| Celé UI | `Dictator/UI/` | `/impeccable critique Dictator/UI` |

Detektor antipatternů (`detect.mjs`) je určen pro HTML/CSS — u Swift UI spoléhej na **critique** + čtení `AppTheme.swift`.

---

## Nejčastější příkazy

```text
/impeccable                          → menu + doporučení dalšího kroku
/impeccable critique <soubor>        → UX review + uložení do .impeccable/critique/
/impeccable polish <soubor>          → opravy podle poslední critique
/impeccable distill StatusBarController   → zjednodušit menu
/impeccable onboard SetupWindowController
/impeccable clarify Dictator/UI
/impeccable audit Dictator/UI        → a11y (VoiceOver copy v AccessibilitySupport)
/impeccable document                → aktualizovat DESIGN.md z kódu
```

Zkratky (volitelné):

```bash
node .cursor/skills/impeccable/scripts/pin.mjs pin critique
# → /critique volá /impeccable critique
```

---

## Principy, které Impeccable hlídá

Z [PRODUCT.md](./PRODUCT.md) a [DESIGN.md](./DESIGN.md):

1. **Menu bar is home** — ne dashboard-first.
2. **Quiet Study** — claret + cream, žádné fialové AI gradienty.
3. **Hotkey is law** — copy používá `HotkeyPreference`, ne hardcoded Option.
4. **Progressive disclosure** — Setup ≠ Nastavení ≠ Diagnostika.
5. **Trust surface** — offline jako fakt, ne marketingový superlativ.

---

## Po critique

Snapshoty: `.impeccable/critique/<timestamp>__<slug>.md`

```bash
node .cursor/skills/impeccable/scripts/critique-storage.mjs latest dictator-ui-statusbarcontroller-swift
```

Uprav [`.impeccable/critique/ignore.md`](./.impeccable/critique/ignore.md), pokud je nález záměrný (např. systémový popover).

---

## Aktualizace kontextu

| Změna | Akce |
|-------|------|
| Nová barva / spacing v `AppTheme` | `/impeccable document` + ručně DESIGN.md |
| Nový brand copy | BRAND.md + `AppBrand.swift` |
| Nový UX benchmark | `research/competitive-analysis/` |
| Změna positioning | PRODUCT.md |

---

## Odkazy

- Skill: [.cursor/skills/impeccable/SKILL.md](./.cursor/skills/impeccable/SKILL.md)
- Init flow: [.cursor/skills/impeccable/reference/init.md](./.cursor/skills/impeccable/reference/init.md)
- Product register: [.cursor/skills/impeccable/reference/product.md](./.cursor/skills/impeccable/reference/product.md)
