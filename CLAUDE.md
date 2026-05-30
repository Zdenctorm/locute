# CLAUDE.md

## Co je tento projekt

Nativní macOS appka pro hlasové diktování. **Veřejný brand: Locute** (viz `BRAND.md`). Repo / Xcode target: `Locute`.

**Design / UX:** `PRODUCT.md`, `DESIGN.md`, příkazy `/impeccable` — viz `IMPECCABLE.md`.

Uživatel přidrží klávesu, mluví, pustí → text se objeví tam, kde má kurzor.

---

## Cíl

Jednoduchá, offline, soukromá diktovací appka. Žádná data neopouštějí zařízení.

---

## Stack

- **Jazyk:** Swift (nativní macOS)
- **Transcription backend:** WhisperKit (Apple Silicon, offline)
- **Jazyk přepisu:** čeština (`cs`)
- **Distribuce:** menu bar appka, žádné okno

---

## Klíčové funkce (MVP)

1. **Menu bar icon** — appka žije v menu baru, nemá hlavní okno
2. **Push-to-talk** — přidrž klávesu (výchozí: Right Option) → nahrává mikrofon → pusť → přepíše → napíše text do aktivního okna
3. **Vizuální feedback** — ikona/overlay indikuje nahrávání
4. **Offline only** — WhisperKit lokálně, nic se neposílá ven
5. **Čeština** — model fixně nastaven na `cs`

---

## Technické poznámky

- Globální klávesová zkratka přes `CGEventTap` (funguje i když appka není v popředí)
- Psaní do aktivního okna přes `CGEvent` (klávestové eventy) nebo Accessibility API
- WhisperKit má oficiální Swift Package — přidat jako SPM závislost
- Entitlements: `com.apple.security.device.audio-input`, Accessibility

---


---

## Struktura projektu

Xcode projekt. Hlavní soubory budou doplněny po vytvoření projektu.
