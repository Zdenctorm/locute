---
target: Locute/UI/StatusBarController.swift
score: 32
p0: 2
p1: 3
slug: locute-ui-statusbarcontroller-swift
timestamp: 2026-05-30T12:00:00Z
---

# Critique: menu bar + HUD (Locute)

Register: product. North Star largely met; gaps were implementation drift, not AI slop.

## Heuristics (post-polish)

| # | Heuristic | Score | Note |
|---|-----------|-------|------|
| 1 | Visibility of System Status | 4 | HUD + menu agree; reduced motion respected |
| 2 | Match System / Real World | 4 | AppKit-native, Czech copy |
| 3 | User Control | 3 | Popover insert/copy; menu „Vložit znovu“ still roadmap |
| 4 | Consistency | 3 | Popovers now use AppTheme surface |
| 5 | Error Prevention | 3 | Hotkey hints dynamic |
| 6 | Recognition | 4 | Last transcript popover |
| 7 | Flexibility | 3 | Advanced tucked in submenu |
| 8 | Minimalism | 4 | Quiet Study holds |
| 9 | Error Recovery | 3 | Danger dot on brand palette |
| 10 | Help | 3 | Setup vs prefs split OK |

**Total: 32/40** (Solid utility)

## P0 (fixed this pass)

1. **Hotkey Law** — hardcoded Option in history empty state and no-audio errors.
2. **Brand error color** — HUD injection failure used `systemRed`.

## P1 (fixed this pass)

1. Popover roots used system chrome — now `AppTheme.popoverRootView`.
2. Primary copy said „AI“ / „Whisper“ where PRODUCT forbids marketing tone.
3. DESIGN.md still documented popover gap.

## P2 (backlog)

- Menu shortcut „Vložit znovu“ when idle + last transcript exists (Whispur pattern).
- Accent-filled primary CTA once per window (DESIGN open question).
- Learned terms footnote still mentions Whisper (advanced OK, could soften).

## Polish applied

See branch `cursor/impeccable-loop-b8aa`: AppTheme popover chrome, copy, danger dot, DESIGN sync.
