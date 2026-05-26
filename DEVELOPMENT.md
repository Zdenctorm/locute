# Dictator — vývoj na Macu

## Jedna kopie aplikace (doporučeno)

Na Macu snadno vznikne víc kopií `Dictator.app` (Xcode DerivedData, `dist/`, starý DMG v `/Applications`, kopie na ploše). macOS pak v **Zpřístupnění** ukazuje jinou aplikaci, než kterou právě spouštíš — diktování a oprávnění působí „rozbitě“.

**Pravidlo:** vždy jedna kanonická instalace v `/Applications/Dictator.app`, aktualizovaná z repa.

```bash
cd ~/path/to/dictator   # tvůj clone
git pull origin main
./scripts/install_latest.sh
```

Volitelně v jednom kroku:

```bash
./scripts/install_latest.sh --pull
```

### Co skript dělá

1. Postaví Release do `dist/Dictator.app` (`build_release.sh`)
2. Ukončí běžící Dictator
3. Nahradí `/Applications/Dictator.app`
4. Spustí novou kopii
5. Vypíše další nalezené kopie — ty smaž nebo ignoruj

Jiná cílová složka:

```bash
DICTATOR_INSTALL_PATH="$HOME/Applications/Dictator.app" ./scripts/install_latest.sh
```

Jen zobrazit duplicity:

```bash
./scripts/install_latest.sh --list
```

### Po instalaci

1. **Nastavení → Soukromí a zabezpečení → Zpřístupnění** — smaž staré položky „Dictator“, přidej **aktuální** `/Applications/Dictator.app` (v appce Nastavení → Oprávnění uvidíš přesnou cestu).
2. V menu baru **Dictator → O Dictatoru** — ověř verzi.
3. **Nespouštěj** zároveň build z Xcode (⌘R) a kopii z `/Applications` — Xcode spouští jinou cestu v DerivedData.

### Úklid starých kopií

```bash
./scripts/install_latest.sh --list
# ručně smaž např.:
#   dist/Dictator.app (jen artefakt buildu — znovu se vytvoří)
#   ~/Library/Developer/Xcode/DerivedData/.../Dictator.app
#   staré DMG rozbalené na Desktopu
```

## Vývoj v Xcode

Otevři `Dictator.xcodeproj`. Pro běžné testování funkcí preferuj `install_latest.sh` místo Run z Xcode.

## Stabilní verze pro kolegy (DMG + Sparkle)

- Release: `./scripts/release.sh <verze>` — viz [RELEASING.md](RELEASING.md)
- Stažený DMG: [GitHub Releases](https://github.com/Zdenctorm/dictator/releases/latest)

**Poznámka:** `main` může být napřed před posledním GitHub releasem. Pro nejnovější kód z repa vždy `install_latest.sh`, ne starý DMG.

## Diagnostika

- Log: `~/Library/Logs/Dictator/diagnostics.log`
- Sparkle ruční kontrola: menu → Zkontrolovat aktualizace…
