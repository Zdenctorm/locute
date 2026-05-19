# Roadmap — implementační balíčky

Tato složka obsahuje **plné specifikace** pro nejbližší produktové fáze. Tracking úkolů: **GitHub Issues** v repozitáři `dictator` (žádný externí nástroj).

| Dokument | Obsah |
|----------|--------|
| [P0-spec.md](./P0-spec.md) | 5 položek — důvěra, vkládání, distribuce |
| [P1-spec.md](./P1-spec.md) | 13 položek — power user, jazyky, modely |
| [../research/voice-dictation-market-research.md](../research/voice-dictation-market-research.md) | Tržní research a backlog R1–R8 |

**Hlavní index roadmapy:** [ROADMAP.md](../../ROADMAP.md)

## Jak zakládat issues

1. Každá položka `P0.x` / `P1.x` má v spec souboru sekci **GitHub issue** (title + body).
2. Label návrh: `P0` / `P1`, `area:paste`, `area:transcription`, `area:release`, …
3. Milestone návrh: `v1.1-p0` (všechny P0), `v1.2-p1` (P1 po dokončení P0).

## Definition of Done (společné)

- [ ] Acceptance criteria ze spec splněna
- [ ] Manuální test na macOS 14+ Apple Silicon (uvedené scénáře)
- [ ] Unit testy tam, kde spec požaduje (pure logika)
- [ ] `DiagnosticsLogger` záznamy pro nové failure větve
- [ ] Aktualizace [ROADMAP.md](../../ROADMAP.md) checkboxu položky
