---
target: Locute/UI
score: 38
p0: 0
p1: 1
slug: locute-ui
timestamp: 2026-06-03T18:00:00Z
---

# Critique: Locute/UI (formální běh)

**Metoda:** Assessment A (design review kódu) + Assessment B (`detect.mjs` → 0 nálezů, AppKit očekávaně mimo scope).  
**Poznámka:** Snapshot `impeccable-loop-score-40` byl **shrnutí práce agenta**, ne výstup plného `/impeccable critique` workflow.

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 4 | ● menu, pill HUD, ikony stavu |
| 2 | Match System / Real World | 4 | Tykání, ⌘ místo Option, krátké copy |
| 3 | User Control and Freedom | 4 | Esc, Historie, Vložit znovu |
| 4 | Consistency and Standards | 4 | Setup ≠ Nastavení; hotkey law |
| 5 | Error Prevention | 4 | Checklist 3 kroků, key test |
| 6 | Recognition Rather Than Recall | 3 | Menu stále 2 řádky stav+hint + 6 akcí |
| 7 | Flexibility and Efficiency | 4 | Pokročilé disclosure, PTT/toggle |
| 8 | Aesthetic and Minimalist Design | 4 | Copy distill hotovo; prefs scroll dlouhý |
| 9 | Error Recovery | 4 | Krátké chyby, Zkusit znovu |
| 10 | Help and Documentation | 4 | „Potřebuješ pomoc?“ disclosure |
| **Total** | | **38/40** | **Silná utilita, menu ještě zhuštit** |

## P1 (zbývá pro 40)

- **[P1] Menu hint řádek** — `hintMenuItem` duplikuje tooltip; zvážit skrýt v idle když klávesa funguje.
- **[P1] Formal loop** — další kola: `/impeccable critique` → `/impeccable distill|clarify|polish` → re-critique.

## Anti-patterns

- **AI slop:** PASS — Quiet Study, claret, žádný SaaS hero.
- **detect.mjs:** `[]` (Swift/AppKit).

## Doporučený Impeccable loop (Locute)

```
/impeccable critique Locute/UI/StatusBarController.swift
/impeccable distill StatusBarController        ← podle P1 z critique
/impeccable critique Locute/UI/StatusBarController.swift   ← re-score
```

Opakovat pro Setup, Preferences, Launch. **`/impeccable live` nepoužívat** (AppKit).
