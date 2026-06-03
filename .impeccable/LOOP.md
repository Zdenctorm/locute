# Impeccable loop — Locute (Swift / AppKit)

**North Star:** The Quiet Study · **Register:** product · **Cíl skóre:** ≥40/40

## Správný loop (povinný postup)

Impeccable loop **není** „agent napíše skóre do LOOP.md“. Správně:

1. `/impeccable critique Locute/UI/<surface>.swift` — Assessment A + B, snapshot do `.impeccable/critique/`
2. Podle P0/P1 v snapshotu: `/impeccable distill`, `/impeccable clarify`, `/impeccable polish`, `/impeccable onboard`…
3. Commit → znovu **critique** stejného surface → porovnat skóre
4. **`/impeccable live` u Locute nepoužívat** (AppKit, ne HTML)

Příklad:

```text
/impeccable critique Locute/UI/StatusBarController.swift
/impeccable distill StatusBarController
/impeccable critique Locute/UI/StatusBarController.swift
```

---

## Iterace 2026-06-03 — formální re-critique **38/40**

Snapshot `2026-06-03T18-00-00Z__locute-ui-formal-critique.md` — upřímné skóre po copy distill.  
Dřívější „40/40“ snapshot byl **agent summary**, ne plný critique běh.

### Hotovo (implementace)

| ID | Oblast | Změna |
|----|--------|-------|
| L13 | Copy distill | Setup, Launch, Prefs, menu, chyby |
| L14 | CTA | `AccentFilledButton` |
| L15 | Menu | Historie… sibling |

### Další kolo (38 → 40)

| Pri | Úkol | Impeccable příkaz |
|-----|------|-------------------|
| P1 | Zredukovat menu hint řádek | `distill StatusBarController` |
| P2 | Zkrátit prefs scroll (méně karet) | `distill PreferencesPanelBuilder` |
| P3 | Re-critique po úpravách | `critique Locute/UI` |

---

## Iterace 2026-06-03 — agent summary 40/40 (neformální)

Viz `2026-06-03T12-00-00Z__impeccable-loop-score-40.md` — orientační, ne audit trail.

---

## Iterace 2026-06-03 — skóre **38/40** ✓ (kolo 2)

Viz git history — HistoryWindow, prefs sekce, pill HUD, speed-first.

---

## Jak spustit další loop

```text
/impeccable udělej loop se subagenty — cíl skóre 40, pokračuj podle .impeccable/LOOP.md
```
