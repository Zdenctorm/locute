# Dictator — produktová roadmapa

> **Účel:** Jednotný přehled směřování produktu.  
> **Poslední revize:** květen 2026  
> **Plné specifikace P0/P1:** [docs/roadmap/](./docs/roadmap/)  
> **Tržní research:** [docs/research/voice-dictation-market-research.md](./docs/research/voice-dictation-market-research.md)

---

## Vize

**Dictator** je soukromé české diktování pro macOS: drž klávesu, mluv, pusť — text se objeví tam, kde máš kurzor. Bez cloudu, bez účtu, bez telemetrie.

Cílový uživatel: knowledge worker na Macu — kdokoli, kdo píše hodně textu a nechce posílat hlas ani přepisy na cizí servery.

---

## Produktové principy

| Princip | Praxe |
|--------|--------|
| **Offline-first** | WhisperKit lokálně; síť jen model + Sparkle |
| **Soukromí** | Žádná analytika; audio jen dočasně |
| **Push-to-talk** | Vědomá aktivace klávesou |
| **Funguje všude** | Vložení do aktivní aplikace |
| **Čeština first** | `cs` default; další jazyky volitelně |

---

## Stav dnes (shrnutí)

Kompletní checklist implementovaných funkcí: sekce **„Stav dnes“** v předchozí verzi dokumentu zůstává platný — viz [OVERVIEW.md](./OVERVIEW.md#co-je-implementováno).

Hlavní oblasti: PTT diktování · Whisper large-v3 CZ · per-app paste · LearningEngine · historie · HUD · Sparkle · hotkey rebind.

---

## Jak číst priority

| Úroveň | Dokument | Tracking |
|--------|----------|----------|
| **P0** | [docs/roadmap/P0-spec.md](./docs/roadmap/P0-spec.md) | GitHub Issues, milestone `v1.1-p0` |
| **P1** | [docs/roadmap/P1-spec.md](./docs/roadmap/P1-spec.md) | GitHub Issues, milestone `v1.2-p1` |
| **P2+** | níže v tomto souboru | issues podle potřeby |
| **Research backlog R1–R8** | [research doc](./docs/research/voice-dictation-market-research.md) | po P1 retrospektiva |

---

## P0 — Kvalita každodenního diktování (v1.1)

**Cíl:** Důvěra při každodenním používání + bezproblémová instalace u kolegů.

| ID | Funkce | Stav | Spec |
|----|--------|------|------|
| P0.1 | Obnova schránky po Cmd+V | [ ] | [P0-spec § P0.1](./docs/roadmap/P0-spec.md#p01--obnova-schránky-při-cmdv-vkládání) |
| P0.2 | Smart leading space | [ ] | [§ P0.2](./docs/roadmap/P0-spec.md#p02--smart-leading-space) |
| P0.3 | Normalizace ALL-CAPS | [ ] | [§ P0.3](./docs/roadmap/P0-spec.md#p03--normalizace-velikosti-písmen-all-caps) |
| P0.4 | HUD při chybě vložení | [ ] | [§ P0.4](./docs/roadmap/P0-spec.md#p04--hud-a-feedback-při-selhání-vložení) |
| P0.5 | Developer ID + notarizace | [~] | [§ P0.5](./docs/roadmap/P0-spec.md#p05--apple-developer-id--notarizace-produkčního-buildu) |

**Proč teď (research):** Přepisovaná schránka je top issue u [Handy](https://github.com/cjpais/Handy/issues/921) a Kalam; paste failures dokumentuje [Wispr](https://docs.wisprflow.ai/articles/7971211038-fix-text-not-pasting-after-dictation). Gatekeeper blokuje adopci u týmů.

---

## P1 — Profesionální diktování (v1.2)

**Cíl:** Pokrytí očekávání z Dragon / SuperWhisper / Wispr — bez porušení offline slibu.

| ID | Funkce | Stav | Spec |
|----|--------|------|------|
| P1.1 | České hlasové příkazy (interpunkce) | [ ] | [P1-spec § P1.1](./docs/roadmap/P1-spec.md#p11--interpunkční-a-formátovací-hlasové-příkazy-čeština) |
| P1.2 | Normalizace čísel / dat | [ ] | [§ P1.2](./docs/roadmap/P1-spec.md#p12--normalizace-čísel-a-dat) |
| P1.3 | Undo posledního vložení | [ ] | [§ P1.3](./docs/roadmap/P1-spec.md#p13--undo-posledního-vložení) |
| P1.4 | Review před vložením | [ ] | [§ P1.4](./docs/roadmap/P1-spec.md#p14--režim-zkontroluj-před-vložením) |
| P1.5 | Volba Whisper modelu | [ ] | [§ P1.5](./docs/roadmap/P1-spec.md#p15--volba-whisper-modelu) |
| P1.6 | Streaming preview (beta) | [ ] | [§ P1.6](./docs/roadmap/P1-spec.md#p16--průběžný-přepis-streaming) |
| P1.7 | Warm-up / cold start | [ ] | [§ P1.7](./docs/roadmap/P1-spec.md#p17--agresivnější-warm-up-po-startu) |
| P1.8 | Export / import slovníku | [ ] | [§ P1.8](./docs/roadmap/P1-spec.md#p18--export--import-slovníku) |
| P1.9 | Slovník podle aplikace | [ ] | [§ P1.9](./docs/roadmap/P1-spec.md#p19--profil-slovníku-podle-aplikace) |
| P1.10 | Editor celého slovníku | [ ] | [§ P1.10](./docs/roadmap/P1-spec.md#p110--ruční-editor-celého-slovníku) |
| P1.11 | Angličtina | [ ] | [§ P1.11](./docs/roadmap/P1-spec.md#p111--angličtina) |
| P1.12 | Slovenština | [ ] | [§ P1.12](./docs/roadmap/P1-spec.md#p112--slovenština) |
| P1.13 | Auto detekce jazyka | [ ] | [§ P1.13](./docs/roadmap/P1-spec.md#p113--automatická-detekce-jazyka) |

**Doporučený první slice v1.2:** P1.1 + P1.4 + P1.8 + P1.11 (viz [P1 release checklist](./docs/roadmap/P1-spec.md#p1--release-checklist-v12)).

**Proč (research):** Dragon uživatelé očekávají hlasové příkazy; Wispr nabízí review/scratchpad; SuperWhisper a enterprise segment chtějí slovník a lokální režim — viz [research](./docs/research/voice-dictation-market-research.md).

---

## Research backlog (budoucí rozhodování)

Položky odvozené z trhu, **nejsou** součástí P0/P1 — prioritizovat po v1.2.

| ID | Název | Stručně |
|----|-------|---------|
| R1 | Odstranění výplňových slov | „ehm“, „jako“ — post-process, volitelné |
| R2 | Hotkey „Vlož poslední přepis“ | Záloha jako Wispr Scratchpad |
| R3 | Kontext z aktivního pole (opt-in) | Lokální AX → Whisper prompt |
| R4 | Hint pro problematické appky | Citrix, VDI — místo tichého failu |
| R5 | Snippety / šablony | Krátká makra po diktátu |
| R6 | Režim tiché řeči | Gain / práh pro tichý mikrofon |
| R7 | Retence historie | Auto-mazání po N dnech |
| R8 | CS+EN mix v jedné větě | Auto-detect bez přepínání |

Detail a zdroje: [voice-dictation-market-research.md](./docs/research/voice-dictation-market-research.md).

---

## P2 — Tým, firma, compliance

| ID | Funkce |
|----|--------|
| P2.1 | Sdílený týmový slovník (soubor / MDM) |
| P2.2 | MDM / silent install (PKG) |
| P2.3 | Zásady uchovávání historie |
| P2.4 | Lokální audit log (metadata only) |
| P2.5 | Privacy report pro security review |
| P2.6 | Offline mirror Whisper modelu |

---

## P3 — Platforma a experimenty

Kontinuální diktování · druhá hotkey · Shortcuts · mini-editor · statistiky lokálně · Intel Mac · iOS · Windows · Mac App Store edice.

Detailní tabulka zůstává v git historii; nové nápady nejdřív do research backlogu.

---

## Anti-cíle

Cloud STT · dlouhodobé ukládání audio · telemetrie · účty · nepřetržité odposlouchávání · přepis callů bez souhlasu.

---

## Metriky úspěchu (bez telemetrie)

- Retry do 8 s a ruční opravy v historii ↓  
- Hlášení „nevložilo se“ ↓ po P0  
- Podíl notarizovaných instalací ↑  
- Medián čas release → text v poli < 3 s (krátké věty)  
- Kvalitativní retence 7 / 30 dní

---

## Dokumentace

| Soubor | Obsah |
|--------|--------|
| [CLAUDE.md](./CLAUDE.md) | MVP kontext |
| [PLAN.md](./PLAN.md) | Technický implementační plán |
| [OVERVIEW.md](./OVERVIEW.md) | Architektura a bezpečnost |
| **ROADMAP.md** | Tento index |
| [docs/roadmap/](./docs/roadmap/) | P0/P1 specifikace |
| [docs/research/](./docs/research/) | Tržní research |
| [RELEASING.md](./RELEASING.md) | Vydávání |

---

## Historie

| Datum | Změna |
|-------|--------|
| 2026-05 | První roadmapa |
| 2026-05 | P0/P1 plné spec + market research; tracking přes GitHub Issues |
