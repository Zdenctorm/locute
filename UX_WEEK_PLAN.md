# UX týden — aktualizovaný plán (bez loga)

## Oprava o modelu

Výchozí model je **`large-v3-v20240930_turbo` (~630 MB)**, ne ~3 GB. Varianta přesnosti `large-v3-v20240930` je také ~626 MB. Dokumentace v `OVERVIEW.md` je sjednocená s `TranscriptionModelPreference`.

## Mimo scope (hotovo jinde)

- Logo a menu bar identita — **neřešit** v tomto sprintu.

## Implementováno v `cursor/ux-week-67b0`

| Oblast | Soubory |
|--------|---------|
| Průvodce first-run | `OnboardingWindowController`, `OnboardingPreference` |
| Quick panel (levý klik) | `StatusBarQuickPanelController` + `StatusBarController` |
| Poslední přepisy v menu | `StatusBarController.updateRecentTranscriptions` |
| Progress stahování v menu baru | `updateModelDownloadProgress` + stav `.modelDownloading` |
| HUD level meter | `AudioLevelMeterView`, `AudioRecorder.recentLiveLevel` |
| Hlasová interpunkce | `PunctuationCommandProcessor` + testy |
| Test přepisu (themed) | `TranscriptionTestSheet` |
| Bez auto launch okna po onboardingu | `OnboardingPreference.suppressAutoLaunchWindow` |

## Volitelně další sprint

- Figma design systém (tokeny z `AppTheme`) — koordinace s designérem
- Notarizace + bundle ID produkce
- Double-tap toggle (VocaMac parity)
- Raycast / Homebrew

## Tým 4 dev — zbývající dny (pokud pokračujete)

Po integraci této větve: QA matrix na macOS, VoiceOver průchod onboardingu, test Gatekeeper copy, ověření punctuation v reálné řeči.
