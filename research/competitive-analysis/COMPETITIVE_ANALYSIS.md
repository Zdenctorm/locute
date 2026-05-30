# Konkurenční analýza — macOS diktování (2026)

> Datum: 2026-05-30  
> Cíl: Porovnat Dictator s hlavními nástroji pro push-to-talk / system-wide diktování na Macu a vyvodit UX vzory, které stojí za převzetí.  
> Screenshoty: `./screenshots/` (**96 souborů**, ~16 MB, po složkách podle konkurenta).  
> Index zdrojů: [`SOURCES.md`](./SOURCES.md) · manifest: [`sources/MANIFEST.txt`](./sources/MANIFEST.txt)

---

## 1. Kdo je v poli

| Produkt | Typ | Audio | Cena (orientačně) | Primární publikum |
|---------|-----|-------|-------------------|-------------------|
| **Dictator** | Menu bar, push-to-talk | Lokálně (WhisperKit) | Interní / bez SaaS | Čeština, soukromí, firma |
| **Wispr Flow** | Menu bar + cloud AI edit | Cloud (+ screenshot kontextu) | ~12–15 USD/měs | „Nechci psát“, cross-platform |
| **Superwhisper** | Menu bar + módy | Lokálně (+ volitelný cloud/BYOK) | ~8,5 USD/měs, lifetime | Power users, NDA |
| **Aqua Voice** | Menu bar + streaming | Cloud (Avalon model) | ~8 USD/měs | Rychlost, vývojáři (Cursor) |
| **MacWhisper** | App + dictation režim | Lokálně | ~80 USD lifetime | Přepisy souborů + občasné diktování |
| **Whispur** | Menu bar (open source) | BYOK (Groq, OpenAI, Apple…) | Zdarma + API | Technicky zdatní |
| **WhisperClip / Open-Wispr / Pindrop** | Menu bar, lokální | Lokálně | Zdarma / jednorázově | DIY, privacy puristé |
| **Glimpse** | Tauri app, local-first | Lokálně | Zdarma (beta) | Privacy, Wispr/Superwhisper alternative |
| **VoiceInk** | Menu bar (OSS) | Lokálně + API | Zdarma | Komunita, podobná kategorie |
| **Superduper-whisper** | OSS overlay | Cloud Whisper API | Zdarma + API | Referenční UI (waveform, themes) |
| **Apple Dictation** | Systém | On-device (omezeně) | Zdarma | Krátké vstupy, žádná instalace |

**Závěr trhu (2026):** Přepis už není diferenciace — všichni stojí na Whisper nebo vlastním modelu. Produkt je **workflow**: hotkey, overlay, latence key-up → paste, post-processing, onboarding oprávnění, důvěra (privacy copy).

---

## 2. Stažené materiály (inventář)

### Přehled po složkách

| Složka | Soubory | Hlavní hodnota pro Dictator |
|--------|---------|------------------------------|
| **`whispur/`** | 9 | ⭐ Menu bar, HUD + waveform, setup checklist, demo.gif |
| **`wispr-flow/`** | 44 | Marketing CDN, integrace app, YouTube recenze |
| **`aqua-voice/`** | 25 | Landing Framer, produktové mockupy, logo |
| **`glimpse/`** | 5 | Local-first app: home, dictionary, personalization, library |
| **`superduper-whisper/`** | 5 | Recording bar, settings (12 themes), mini HUD |
| **`open-wispr/`** | 2 | Accessibility onboarding |
| **`whisperclip/`** | 3 | Ikony, dark-app positioning |
| **`superwhisper/`** | 1+URL | OG + docs obrázky (mintcdn — viz `sources/superwhisper-mintcdn-urls.txt`) |
| **`misc/`** | 2 | VoiceInk hero, YouTube |
| **`macwhisper/`** | 0 | *Zatím jen HTML help v `sources/`* |

### Klíčové reference (co otevřít jako první)

1. `whispur/recording-overlay.png` — pill HUD, waveform, Esc  
2. `whispur/hero-menubar.png` — minimální menu  
3. `whispur/settings-setup.png` — checklist onboarding  
4. `glimpse/readme-home.png` — local dictation „dashboard“  
5. `superduper-whisper/screenshot-1.png` — dense settings (co **nedělat** v 1. vrstvě)  
6. `wispr-flow/cdn-*.png` — marketing tón Wispr (anti-reference)

**Poznámka:** Wispr Flow a Superwhisper in-app UI jsou v placené appce. Dokumentace Wispr popisuje **Flow Hub**, **Flow Bar**, mikrofon test s audio bary — viz `sources/doc-*-setup-guide` (HTML). Superwhisper docs: `introduction-001.png` atd. na mintcdn (stažení z CLI blokované; doplnit ručně).

Viz kompletní seznam: [`sources/INVENTORY_BY_COMPETITOR.md`](./sources/INVENTORY_BY_COMPETITOR.md).

---

## 3. Jak to dělají — vzory podle vrstvy UX

### 3.1 Aktivace (push-to-talk)

| Nástroj | Výchozí gesto | Konfigurace |
|---------|---------------|-------------|
| Wispr Flow | Podržení klávesy (často Fn / Ctrl+Option) | Průvodce při prvním spuštění |
| Superwhisper | ⌥ + Space (marketing) | Vlastní zkratky |
| Aqua Voice | Hold + Space (demo na webu) | Až 5 alternativních bindingů, vč. Fn chord |
| Whispur | Hold **Fn**, toggle **⌘+Fn** | Edit v menu i Settings |
| Dictator | **Option** (výchozí, konfigurovatelné) | Nastavení + key test card |

**Co se učit:**
- **Dvě gesta:** hold vs toggle/latch — Whispur to má explicitně; Dictator má activation mode, ale v UI to není tak „na první pohled“ jako u Whispur.
- **Key test live** — Dictator už má `keyTestCard` (silná stránka); konkurence to často dává až po frustraci v System Settings.
- **Všechny stringy musí používat aktuální hotkey** — Aqua/Wispr nikde neříkají „Option“ pokud user zvolil něco jiného.

### 3.2 Feedback během nahrávání (HUD / overlay)

**Whispur (referenční vzor):**
- Horizontální **pill** nahoře, tmavé sklo
- Text: „Listening“ + „Release to transcribe“
- **Waveform** uprostřed (okamžitá zpětná vazba že mic funguje)
- **Esc = cancel** viditelně vpravo

**Dictator dnes:**
- HUD nahoře (`RecordingOverlayController`), stavy v češtině, pulzující tečka
- Streaming preview (confirmed + draft) — **silnější než většina konkurence v marketingu**
- Chybí: waveform / úroveň hlasitosti, explicitní cancel klávesa na overlay

**Wispr Flow (z recenzí):**
- Minimální přítomnost — „stays out of the way“
- AI edit až po puštění klávesy (ne nutně live text v HUD)

**Aqua Voice:**
- **Streaming mode** — zvýrazňují real-time úpravu slov během mluvení (hlavní diferenciátor vůči Flow)
- Pro vývojáře: syntax highlighting v preview u Cursor

**Co se učit:**
1. Přidat **vizuální signál živého audia** (waveform nebo level meter) — uživatel okamžitě ví, že mic nejde do ticha.
2. Zvážit **Esc / zrušit** na HUD (jako Whispur) — sníží strach z „už to nahrává“.
3. Dictatorův **streaming preview** je konkurenční výhoda — v marketingu a onboardingu ho víc vytáhnout („vidíš text už při držení klávesy“).

### 3.3 Menu bar — hlavní „home“

**Whispur dropdown:**
- Stav: zelený badge **Ready**
- Jedno primární CTA: **Start Dictation**
- Sekce: Providers, Shortcuts, Last transcript (+ Paste again / Copy)
- Footer: About, Settings, Quit — **bez diagnostiky v hlavní vrstvě**

**Dictator menu bar:**
- Více položek: test přepisu, diagnostika, Sparkle, post-processing toggle, learned terms…
- Silné pro power users, **slabší pro první dojem** oproti Whispur/Wispr

**Open-Wispr / Pindrop:**
- Ikona stavu: idle / recording / transcribing / downloading model
- Recent recordings v menu
- Copy last dictation — recovery když nebyl focus v textovém poli

**Co se učit:**
1. **Zjednodušit menu** na 1. vrstvě: Stav → Poslední přepis → Nastavení → Ukončit.
2. Přesunout test/diagnostiku/LLM do submenu **Pokročilé**.
3. Přidat **„Vložit znovu“** u posledního přepisu přímo v menu (Whispur pattern).

### 3.4 Onboarding a oprávnění

**Whispur Setup tab:**
- Progress **5/5** + checklist s odkazy na další záložky
- Každý krok: mikrofon, accessibility, provider, shortcuts, první diktát
- Sidebar: Setup | General | Providers | Prompts | Activity | Requests

**Wispr Flow:**
- „Initial setup walks you through everything“ — pak zmizí
- Osobní slovník se učí automaticky (marketing)

**Dictator:**
- `PermissionsWindowController` = permissions **+ celé nastavení v jednom scrollu**
- Key test + Finder path + copy log — užitečné pro dev, těžké pro kolegu z firmy

**Co se učit:**
1. **Rozdělit Setup vs Nastavení** (viz Impeccable critique).
2. Checklist s počítadlem („2 ze 3 hotovo“) místo dlouhého textu u Accessibility.
3. Po splnění permissions **automaticky spustit krátký „první diktát“** wizard (30 s demo).

### 3.5 Post-processing a „AI polish“

| Nástroj | Přístup |
|---------|---------|
| Wispr Flow | Cloud auto-edit, tón podle aplikace, snippet library, Command mode |
| Superwhisper | Módy + prompty + Super Mode (čte obrazovku) |
| Aqua | Avalon model, custom dictionary, custom instructions |
| Whispur | Volitelný LLM cleanup (Groq atd.), BYOK |
| Dictator | Slovník + fonetické opravy + volitelný **lokální LLM** |

**Co se učit:**
- Dictator je **jediný s lokálním LLM post-processingem** v této tabulce — to je silný firemní argument.
- V UI ale **neříkat „AI“ genericky** — raději „lokální oprava přepisu (na tomto Macu)“.
- Wispr/Superwhisper prodávají **výsledek** („rambling → polished prose“), ne technologii — stejný jazyk použít v launch window.

### 3.6 Soukromí a důvěra

| Nástroj | Messaging |
|---------|---------|
| Wispr Flow | SOC2, HIPAA enterprise, Privacy Mode — ale audio jde do cloudu |
| Superwhisper | „Works offline“, lokální modely v marketingu |
| Aqua | „Nothing stored on servers“ (history lokální) — ale inference cloud |
| Dictator | 100 % offline po stažení modelu, žádná telemetrie |

**Co se učit:**
- U firemního uživatele **první obrazovka = co neopouští Mac** (tabulka jako v OVERVIEW.md), ne WhisperKit.
- Konkurence řeší strach **certifikáty**; Dictator řeší strach **architekturou** — zůstat u toho, ale zkrátit na 3 bullet points v onboardingu.

### 3.7 Cenotvorba a „try“

- **Wispr / Aqua:** free tier (slova/týden), pak ~8–15 USD/měs — nízká bariéra vstupu
- **Superwhisper / MacWhisper:** lifetime — power users
- **Dictator:** interní distribuce — konkurence s cenou nehraje, ale **první spuštění ~3 GB model** je větší bariéra než 14denní trial u Wispr

**Co se učit:**
- Progress při stahování modelu + odhad času (Dictator už má download card — doplnit „zbývá ~X min“ pokud možno).
- Jednovětá hodnota před downloadem: „Jednou stáhneš, pak už nikdy nepotřebuješ internet.“

---

## 4. Srovnání s Dictator — SWOT v UX

### Silné stránky (vs konkurence)
- **Offline-first** bez kompromisu (Superwhisper je nejbližší, ale má cloud módy a složitost).
- **Čeština fixně** + slovník — Wispr má 100 jazyků, ale ne specializaci na české prostředí/firemní slovník.
- **Streaming partial přepis** během držení klávesy — Aqua to prodává agresivně; Dictator to má implementované.
- **Vlastní brand** (claret + „) — ne vypadá jako generický AI SaaS (Impeccable PASS).
- **Word-level correction + learning** — hlubší než většina menu-bar konkurentů.

### Slabiny (vs konkurence)
- **Příliš mnoho UI na jednom místě** (nastavení = permissions + 6 karet) — Whispur/Wispr oddělují.
- **Menu bar přeplněné** — Whispur ukazuje ideální minimální dropdown.
- **HUD bez waveform/cancel** — Whispur standard.
- **Marketingové screenshoty chybí** — konkurence prodává emocí a jedním obrázkem loopu; Dictator má jen funkční okna.
- **Gatekeeper / notarizace** — Wispr/Superwhisper jako komerční produkty — Dictator je v distribuci pozadu (viz OVERVIEW roadmap).

---

## 5. Doporučené převzetí (prioritizováno)

### P0 — rychlé UX wins
1. **Menu bar redesign** podle Whispur: Ready badge, poslední přepis, Paste again, Settings, Quit.
2. **HUD:** waveform nebo audio level + „Esc zrušit“.
3. **Jednotné hotkey stringy** všude (placeholder, overlay, launch text).

### P1 — onboarding
4. **Setup checklist** (permissions + key test + první diktát) odděleně od Preferences.
5. **Privacy panel** — 3 odrážky na první obrazovce před downloadem modelu.

### P2 — diferenciace
6. **Zvýraznit streaming preview** v launch/HUD copy (konkurence s Aqua).
7. **„Lokální oprava přepisu“** místo „LLM“ v menu pro firemní klid.

### P3 — inspirace z Wispr (bez cloudu)
8. **Snippet library** / voice shortcuts pro opakované fráze (lokální šablony, ne cloud).
9. **Command mode** ekvivalent — lokální úprava označeného textu (už částečně review mode).

---

## 6. Co záměrně nedělat

- **Screenshot kontextu okna** (Wispr) — proti Dictator DNA.
- **Cloud jako default** — ztráta hlavního příběhu.
- **Sidebar s 7 záložkami** jako Whispur Providers/Requests — Dictator není pro vývojáře konfigurující 5 API.
- **Fialové gradienty / generic AI landing** — brand je už správně jiný.

---

## 7. Další kroky (výzkum)

- [x] Rozšířit stažené assety (marketing CDN, GitHub README, docs HTML) — viz `SOURCES.md`
- [ ] Pořídit **reálné in-app screenshoty** Wispr Flow / Superwhisper / MacWhisper (trial) → `screenshots/in-app/`
- [ ] Uložit Superwhisper docs obrázky z prohlížeče (mintcdn URL v `sources/superwhisper-mintcdn-urls.txt`)
- [ ] Složka `screenshots/dictator/` — vlastní UI pro side-by-side
- [ ] Uživatelské testy: 3 kolegové, úkoly „napiš mail / Slack / poznámku“

---

## Zdroje

- [Wispr Flow](https://wisprflow.ai/)
- [Superwhisper](https://superwhisper.com/)
- [Aqua Voice](https://aquavoice.com/)
- [Mac dictation comparison (jamesm.blog, 2026)](https://jamesm.blog/ai/mac-dictation-tools-comparison/)
- [Cult of Mac – Wispr Flow review](https://www.cultofmac.com/reviews/wispr-flow-mac-speech-to-text-app-review)
- [Whispur (GitHub screenshots)](https://github.com/sophiie-ai/whispur/tree/main/docs/screenshots)
- [Open-Wispr install guide](https://github.com/human37/open-wispr/blob/main/docs/install-guide.md)
