# Locute — BRAND.md

> Rozhodnutí: **2026-05-30** · veřejný název **Locute** (nahrazuje pracovní název Dictator)

---

## Název a význam

| | |
|--|--|
| **Brand** | **Locute** |
| **Výslovnost** | LO-kjut (EN), lokjút (CS) |
| **Význam** | *local* + *speak* — rychlý, přesný přepis na Macu, offline po stažení modelu |
| **Logo** | glyf „ na claret (`AppTheme`) — beze změny |

---

## Positioning (EN / CS)

| | EN | CS |
|--|----|----|
| **Headline** | Fast, accurate dictation on your Mac. | Rychlý a přesný přepis na Macu. |
| **Sub** | Your voice never leaves your device. | Hlas neopustí tvůj Mac. |
| **Proof** | See text while you hold the key. | Text vidíš už při držení klávesy. |

**Voice:** klidný, přímý, důvěryhodný — viz [PRODUCT.md](./PRODUCT.md).

**Design North Star:** „The Quiet Study“ — viz [DESIGN.md](./DESIGN.md).

---

## Technické jméno vs. brand (záměrně oddělené)

| Vrstva | Hodnota | Poznámka |
|--------|---------|----------|
| Veřejný název | **Locute** | `CFBundleDisplayName`, UI, dokumentace |
| Xcode target / `.app` | `Dictator` | Přejmenování na `Locute.app` = samostatný release task |
| Bundle ID | beze změny | Stabilita oprávnění a Sparkle |
| Application Support | `~/Library/Application Support/Dictator/` | Migrace dat až při přejmenování složky |
| Logy | `~/Library/Logs/Dictator/` | totéž |
| GitHub repo | `dictator` | URL beze změny |

V kódu: `AppBrand.displayName` pro UI, `AppBrand.storageDirectoryName` pro cesty.

---

## Co neříkat

- Dictator (toxický / zavádějící)
- „Whisper app“ / WhisperKit jako produktový název
- Konkurenční vzory: *Flow*, *Super*, *Voca*, *Whisper* v názvu

---

## Další kroky (volitelné)

- [ ] Trademark / App Store: `"Locute" mac dictation`
- [ ] Přejmenovat Xcode produkt → `Locute.app` + migrační skript pro Application Support
- [ ] Doména / marketing (`locute.app` apod.)
