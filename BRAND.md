# Locute — BRAND.md

> Rozhodnutí: **2026-05-30** · veřejný název **Locute**

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

## Technické jméno

| Vrstva | Hodnota | Poznámka |
|--------|---------|----------|
| Veřejný název | **Locute** | `CFBundleDisplayName`, UI, dokumentace |
| Xcode target / `.app` | `Locute` | `Locute.app` |
| Bundle ID | `com.example.locute` | Sparkle a systémová oprávnění |
| Application Support | `~/Library/Application Support/Locute/` | při prvním spuštění migrace ze staré složky |
| Logy | `~/Library/Logs/Locute/` | totéž |
| GitHub repo | [Zdenctorm/locute](https://github.com/Zdenctorm/locute) | |

V kódu: `AppBrand.displayName` pro UI, `AppBrand.storageDirectoryName` pro cesty.

---

## Co neříkat

- „Whisper app“ / WhisperKit jako produktový název
- Konkurenční vzory: *Flow*, *Super*, *Voca*, *Whisper* v názvu

---

## Další kroky (volitelné)

- [ ] Trademark / App Store: `"Locute" mac dictation`
- [ ] Doména / marketing (`locute.app` apod.)
