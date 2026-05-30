# Locute — přehled

> Soukromé české diktování pro macOS (veřejný brand **Locute**). Drž Option, mluv, pusť — text se objeví tam, kde máš kurzor.

---

## Co Locute je

Nativní macOS aplikace v menu baru, která umožňuje **diktovat text v češtině do libovolné aplikace** push-to-talk gestem.

- Otevřu libovolnou aplikaci (Mail, Terminál, Notes, webový editor, …)
- Kliknu do textového pole
- Podržím **Option (⌥)**, namluvím větu, pustím klávesu
- Text se objeví na pozici kurzoru

Žádné okno, žádný overhead — Locute žije v menu baru a aktivuje se jen klávesou.

---

## Jak to funguje (architektura)

```
[Klávesa Option] → [Mikrofon] → [Whisper model lokálně] → [Vložení textu]
                       ↓               ↓
                   audio bufer    přepis (čeština)
```

1. **Globální klávesová zkratka** (CGEventTap) detekuje stisk Option v jakékoli aplikaci
2. **AVCaptureSession** zachytí mikrofon (16 kHz mono PCM, WAV)
3. **WhisperKit large-v3** běží lokálně na Apple Silicon Neural Engine — provede přepis
4. **Slovník + post-processing** opraví fonetické varianty (např. „měl" → „meEl" atd.)
5. **TextInjector** vloží text do aplikace, ve které byl kurzor — buď přes Accessibility API, nebo přes simulovaný Cmd+V (podle aplikace)

Celý proces od pauznutí klávesy po zobrazení textu trvá **typicky 1–3 sekundy** v závislosti na délce nahrávky.

---

## Bezpečnost a soukromí

**Toto je hlavní prodejní argument pro firemní použití.**

| Co se děje | Kam to teče |
|---|---|
| Zvuk z mikrofonu | RAM aplikace, nikam jinam |
| WAV soubor nahrávky | `/tmp/` na lokálním Macu, smaže se po přepisu |
| Přepsaný text | RAM aplikace + cíl (libovolná aplikace), historie v okně Locute |
| Telemetrie / analytika | **Žádná** — neexistuje |
| Síťová aktivita | **Jediná**: jednorázové stažení Whisper modelu (~630 MB turbo, volitelně ~626 MB přesnost) z Apple's HuggingFace mirroru při prvním spuštění. Po stažení je Locute plně offline. |
| Cloud / API | Žádné. Locute nevolá žádný server, OpenAI ani jiný backend. |

### Entitlements (oprávnění aplikace)

Aplikace má jen dvě:
- `com.apple.security.device.audio-input` — přístup k mikrofonu
- `Accessibility` (přes System Settings → Privacy & Security) — pro globální klávesovou zkratku a vložení textu do aktivního pole

**App sandbox je vypnutý** — nutné pro globální klávesovou zkratku přes CGEventTap (Apple's sandbox neumožňuje sandboxed apps poslouchat keyboard events mimo svoje okno).

### Co Locute vyloženě nedělá

- Nesleduje uživatele
- Neukládá audio na disk (po přepisu se WAV maže)
- Neposílá nic na server
- Nevolá OpenAI, ChatGPT, Claude, ani jiné cloudové AI
- Nemá analytics framework (Mixpanel, Amplitude, GA, …)
- Nemá crash reporter (žádný Sentry, Bugsnag, atd.)

---

## Technický stack

| Vrstva | Technologie |
|---|---|
| Jazyk | Swift 6 |
| UI framework | Cocoa / AppKit (nativní) |
| Audio capture | AVCaptureSession + AVCaptureAudioDataOutput |
| Klávesnice (globální) | CGEventTap (`flagsChanged` událost) |
| Transkripce | **WhisperKit** — default `large-v3-v20240930_turbo`, volba přesnosti v nastavení |
| Jazyk přepisu | Čeština (`cs`), fixně |
| Min. macOS | 14.0 (Sonoma) |
| Procesor | Apple Silicon (M1/M2/M3/…) |

### Model: WhisperKit (turbo / v20240930)

- Open-source ML framework od Argmax Inc. (postaven nad OpenAI Whisper)
- **Rychlost (výchozí):** `large-v3-v20240930_turbo` (~630 MB) — streamovací partial přepis během držení Option
- **Přesnost:** `large-v3-v20240930` (~626 MB) — volitelně v Nastavení Locute
- Metriky latence (`rtf`, `ttft`, `keyUpToDecodeMs`) se zapisují do `~/Library/Logs/Dictator/diagnostics.log`
- Běží **lokálně** na Apple Neural Engine + GPU
- Stažený jednou z `argmaxinc/whisperkit-coreml` při prvním spuštění
- Po stažení žádné API volání — model je v `~/Library/Caches/`

---

## Co je implementováno

### Core funkce
- ✅ Push-to-talk diktování (Option key)
- ✅ Lokální Whisper přepis v češtině
- ✅ Vložení do aktivního okna (Accessibility nebo Cmd+V podle aplikace)
- ✅ Menu bar ikona se stavovými indikátory (idle / nahrávám / přepisuji / vkládám / chyba)
- ✅ HUD overlay nahoře obrazovky během nahrávání („Držíš Option", „Nahrávám", „Vloženo") včetně live audio level metru
- ✅ Historie přepisů (per-řádek, kopírovat / vložit znovu)
- ✅ Zachytávání cílové aplikace na začátku nahrávání (text vždy jde tam, kde uživatel stiskl klávesu)

### Konfigurace
- ✅ **Hotkey rebind**: výběr mezi „Levý/pravý Option" / „Pravý Option" / „Levý Option" / „Pravý Command" (řeší kolizi s českou AltGr)
- ✅ **Vlastní slovník**: textový editor, kde si uživatel přidá produktové termíny (domény, vlastní jména, zkratky, …) — Whisper je dostane jako prompt-bias + post-process fonetické varianty se nahradí na kanonický tvar
- ✅ Default seed slovníku obsahuje crypto/finance termíny (KYC, AML, SEPA, EUR, blockchain, …)
- ✅ Spouštět při přihlášení do macOS (volitelné)

### Robustnost
- ✅ Cross-app event tap se rebuilduje po Accessibility re-grant (řeší dev-rebuild quirk)
- ✅ Explicitní binding na system default input device (bezpečné proti BlackHole / aggregate devices)
- ✅ Filtrace Whisper halucinací při tichu („Titulky vytvořil JohnYX", „Thanks for watching")
- ✅ Detekce „audio příliš tiché" — když mikrofon nezachytí dost, Locute řekne „mluv hlasitěji" místo aby vrátil prázdný přepis

### UX
- ✅ Brand: tmavě bordó (claret) + cream paper, typografický „ glyph jako ikona
- ✅ Light + dark mode (auto-adapt)
- ✅ Resizable hlavní okno s plynulým layoutem historie

---

## Známá omezení

- **První spuštění stáhne model (~630 MB turbo, výchozí)** — potřeba internet jednorázově
- **Pouze Apple Silicon** (M1+). Intel Macy nejsou podporované (WhisperKit large-v3 vyžaduje ANE)
- **Pouze čeština** — jiné jazyky model umí, ale UI ne (lze přidat)
- **Whisper sám občas chybuje s velikostí písmen** u krátkých technických slov („echo" → „ECHO"). Plánovaný post-process normalizační krok.
- **Sandbox vypnutý** = nepůjde distribuovat přes Mac App Store (ale pro firemní distribuci to není potřeba)

---

## Pro distribuci kolegům

### Co potřebují udělat při instalaci

1. Stáhnout DMG, drag do `/Applications`
2. Při prvním spuštění:
   - Macos zařve „Apple cannot check this app" → kliknout pravým → Otevřít → Confirm
   - Povolit **mikrofon** (system dialog)
   - Otevřít **System Settings → Privacy & Security → Accessibility → +** → přidat Locute (v seznamu může být `Dictator.app` do přejmenování balíčku)
3. Počkat několik minut, než se stáhne Whisper model (~630 MB turbo)
4. Hotovo — drž Option v libovolné aplikaci a diktuj

### Co kolegové dostanou

- Funkční diktování bez OpenAI / cloudu / účtu
- Plně offline po prvním spuštění
- Nezávislé na internetu (po stažení modelu)
- Žádná data nikam neutíkají

### Co Locute NEDĚLÁ pro klid v duši:

- Neposílá audio nikam mimo Mac
- Neukládá audio na disk (jen RAM, dočasný WAV se maže)
- Nesleduje uživatele
- Nevolá žádné API
- Auto-update přes Sparkle (kontrola appcastu 1× denně, žádná telemetrie)

---

## Roadmap (návrhy do diskuse)

- [x] **Post-process velikost písmen**: pravidlová normalizace ALL-CAPS (+ volitelný LLM post-processing)
- [x] **Backup + restore schránky** kolem Cmd+V — neztratit uživatelův obsah
- [x] **Smart leading space** při paste doprostřed věty
- [ ] **Punctuation commands** („tečka", „nový odstavec") — power user feature
- [x] **HUD error feedback** při selhání injection
- [x] **Sparkle auto-update** framework
- [ ] **Apple Developer certifikát + notarizace** pro distribuci bez Gatekeeper warning
- [ ] Volitelně: English a Slovak jazyková podpora

---

## Repo struktura

```
Dictator/
├── Core/                   # Audio, transkripce, klávesnice, vkládání textu
│   ├── AudioRecorder.swift          # AVCaptureSession capture
│   ├── TranscriptionEngine.swift    # WhisperKit wrapper
│   ├── TranscriptionSanitizer.swift # Filtr halucinací + slovník
│   ├── HotkeyManager.swift          # CGEventTap + hotkey preference
│   ├── TextInjector.swift           # AX paste / Cmd+V paste
│   ├── PasteInsertionPlan.swift     # Per-app paste strategie
│   └── DiagnosticsLogger.swift      # Lokální log v ~/Library/Logs/Dictator/
├── UI/                     # Okna, status bar, HUD overlay
└── App/AppDelegate.swift   # Lifecycle, wiring komponent
```
