# Zdroje konkurenčního výzkumu

> Aktualizováno: 2026-05-30  
> **96+ souborů** v `screenshots/` (~16 MB). Textové zálohy v `sources/`.

## Jak stáhnout víc

```bash
bash research/competitive-analysis/scripts/download-assets.sh
```

MintCDN (Superwhisper docs) blokuje přímý curl — URL jsou v `sources/superwhisper-mintcdn-urls.txt`; screenshoty z docs je potřeba doplnit ručně z prohlížeče nebo trial app.

---

## Produktové weby

| Produkt | URL | Co z toho čerpat |
|---------|-----|------------------|
| Wispr Flow | https://wisprflow.ai/ | Marketing, pricing, „4× faster“, auto-edit |
| Wispr Help | https://docs.wisprflow.ai/ | Setup guide, Flow Hub, Flow Bar, permissions |
| Superwhisper | https://superwhisper.com/ | Offline, modes, push-to-talk |
| Superwhisper Docs | https://superwhisper.com/docs | Onboarding UI popisy (obrázky na mintcdn) |
| Aqua Voice | https://aquavoice.com/ | Streaming, Avalon, Cursor/dev positioning |
| MacWhisper | https://goodsnooze.gumroad.com/l/macwhisper | File transcription + dictation |
| MacWhisper Help | https://macwhisper.helpscoutdocs.com/ | Dictation enable flow |

---

## Open source repozitáře (screenshoty v README)

| Repo | Složka | Klíčové assety |
|------|--------|----------------|
| [sophiie-ai/whispur](https://github.com/sophiie-ai/whispur) | `screenshots/whispur/` | menu bar, HUD pill, setup checklist, providers, **demo.gif** |
| [LegendarySpy/Glimpse](https://github.com/LegendarySpy/Glimpse) | `screenshots/glimpse/` | home, dictionary, personalization, library, hero |
| [jhargis/superduper-whisper](https://github.com/jhargis/superduper-whisper) | `screenshots/superduper-whisper/` | settings themes, mini bar, recording waveform |
| [cydanix/whisperclip](https://github.com/cydanix/whisperclip) | `screenshots/whisperclip/` | ikony, dark sidebar app |
| [human37/open-wispr](https://github.com/human37/open-wispr) | `screenshots/open-wispr/` | Accessibility dialog, System Settings |
| [Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk) | `screenshots/misc/` | README hero (velký PNG) |

---

## Články a recenze (text v `sources/*.html`)

| Zdroj | URL |
|-------|-----|
| macOS dictation stack 2026 | https://jamesm.blog/ai/mac-dictation-tools-comparison/ |
| Wispr Flow — Cult of Mac | https://www.cultofmac.com/reviews/wispr-flow-mac-speech-to-text-app-review |
| Wispr tutorial | https://www.samanthakasbrick.com/blog/wispr-flow-review-tutorial |
| Aqua review | https://www.aestumanda.com/reviews/2025/08/aqua-voice-delivers-what-apples-dictation-still-lacks/ |
| Wispr setup (HTML záloha) | `sources/doc-*-setup-guide` |
| MacWhisper dictation (HTML záloha) | `sources/doc-*-dictation-feature` |

---

## Video (thumbnaily v `screenshots/`)

| Soubor | Video |
|--------|-------|
| `wispr-flow/yt-review-1.jpg` | https://www.youtube.com/watch?v=GCK17S4XpEU |
| `misc/yt-whisper-flow-tutorial.jpg` | https://www.youtube.com/watch?v=x6XJIbRksgI |
| `wispr-flow/wispr-flow-youtube-thumb.jpg` | promo |

Další videa k ručnímu doplnění: MacWhisper review, Superwhisper demo, Aqua Voice 2 (HN).

---

## Složky screenshotů

| Složka | Počet | Typ obsahu |
|--------|-------|------------|
| `wispr-flow/` | 44 | CDN marketing, app ikony, integrace, OG |
| `aqua-voice/` | 25 | Framer marketing, logo, UI mockup |
| `whispur/` | 9 | **Nejlepší in-app reference** pro Dictator |
| `glimpse/` | 5 | Tauri app — home, dictionary, library |
| `superduper-whisper/` | 5 | Settings + mini recording bar |
| `whisperclip/` | 3 | Ikony |
| `open-wispr/` | 2 | Permissions UX |
| `superwhisper/` | 1 | OG (+ URL docs obrázků v sources) |
| `misc/` | 2 | VoiceInk, YouTube |
| `macwhisper/` | 0 | *Doplnit z trial / Gumroad* |

Kompletní seznam souborů: `sources/MANIFEST.txt`  
Popis po složkách: `sources/INVENTORY_BY_COMPETITOR.md`

---

## Co ještě chybí (doporučené doplnění)

1. **Wispr Flow in-app** — Flow Hub, onboarding karty, Flow Bar (trial + screenshot)
2. **Superwhisper in-app** — modes UI, recording overlay (trial nebo docs save-as)
3. **MacWhisper** — dictation settings, global mode (Gumroad / app)
4. **Apple Dictation** — System Settings screenshot (vlastní)
5. **Dictator** — vlastní screenshoty pro side-by-side složku `screenshots/dictator/`

---

## Licence a použití

Assety jsou stažené z veřejných webů a open-source README pro **interní produktový výzkum**. Před publikací mimo tým zkontroluj copyright daného zdroje (zejména Wispr/Aqua marketing CDN).
