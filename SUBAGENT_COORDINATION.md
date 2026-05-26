# Koordinace subagentů — push na GitHub

**Větev:** `cursor/ux-week-67b0`  
**PR:** https://github.com/Zdenctorm/dictator/pull/29  
**Base:** `main` (k `2026-05-26` bez merge konfliktů)

## Pravidla pro paralelní subagenty

1. **Jedna větev** — všichni commitují na `cursor/ux-week-67b0`, ne na `main`.
2. **Vlastnictví souborů** — před startem si rozdělit; jeden agent = integrátor `AppDelegate.swift` + `project.pbxproj`.
3. **pbxproj** — mění jen integrátor po tom, co ostatní dodají nové `.swift` soubory.
4. **Push** — až po integraci: `git pull origin cursor/ux-week-67b0`, řešit konflikty, `git push origin cursor/ux-week-67b0`.
5. **Kontrola kolizí** — žádné `<<<<<<<`, žádné duplicitní API (`onInsert` odstraněno v `a6c9861`).

## Mapa commitů (subagent → obsah)

| Commit | Agent oblast | Soubory |
|--------|----------------|---------|
| `5f379f0` | Punctuation + docs | `PunctuationCommandProcessor*`, `OVERVIEW.md` |
| `2426727` | HUD meter | `AudioRecorder`, `AudioLevelMeterView`, `RecordingOverlayController` |
| `e5c1489` | Onboarding | `OnboardingPreference`, `OnboardingWindowController` |
| `3ff2a38` | Menu discoverability | `StatusBarQuickPanelController`, `StatusBarController` |
| `7356b21` | Integrace | `AppDelegate`, `pbxproj`, `TranscriptionTestSheet` |
| `a6c9861` | UX fix Vložit | Historie/popover/quick panel copy-only |

## Integrační checklist (hotovo)

- [x] Všechny nové Swift soubory v `Dictator.xcodeproj/project.pbxproj`
- [x] `git merge origin/main` — Already up to date
- [x] Žádné conflict markery v repu
- [x] Odstraněné mrtvé API: `onInsert`, `onRetryInsert`, `Vložit` tlačítka
- [x] `AppDelegate` propojuje: onboarding, quick panel, audio meter, punctuation
- [x] `origin/cursor/ux-week-67b0` synchronní s lokální větví

## Před merge PR na Macu

```bash
git checkout cursor/ux-week-67b0
git pull origin cursor/ux-week-67b0
xcodebuild -scheme Dictator -destination 'platform=macOS' build
xcodebuild -scheme DictatorTests -destination 'platform=macOS' test
```

## Známé limity CI

Linux agent nemá Xcode — build/test pouze na macOS u vývojáře.
