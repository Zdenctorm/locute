# Dictator — vývoj na Macu

## Zdroj pravdy: GitHub `main`

**Aktuální Dictator = větev `main` na https://github.com/Zdenctorm/dictator**

| Co *není* „aktuální“ | Proč |
|---|---|
| DMG z [GitHub Releases](https://github.com/Zdenctorm/dictator/releases) | Release vzniká ručně; `main` je často novější |
| Sparkle update v menu | Appcast sleduje poslední release, ne každý commit na `main` |
| Starý clone na disku | Lokální soubory bez `git pull` zaostávají |
| Build z Xcode (⌘R) | Jiná cesta v DerivedData, ne `/Applications` |

Vždy stáhni/aktualizuj kód z GitHubu, pak postav a nainstaluj.

### Kde je složka na Macu

Uživatel `anycoin` → domovská složka je `/Users/anycoin`.

Repozitář z build logů je typicky:

```bash
cd ~/dictator
# totéž co: cd /Users/anycoin/dictator
```

**Ne** `cd ~/anycoin/dictator` — to znamená `/Users/anycoin/anycoin/dictator` a ta složka neexistuje.

Najdeš clone:

```bash
ls ~/dictator/scripts/install_latest.sh
# nebo: find ~ -maxdepth 3 -name install_latest.sh 2>/dev/null
```

### Čistý start (doporučeno, když nevíš co máš lokálně)

```bash
cd ~
git clone https://github.com/Zdenctorm/dictator.git dictator
cd dictator
./scripts/install_latest.sh
```

### Už máš složku — srovnej s GitHubem a přeinstaluj

```bash
cd ~/path/to/dictator
git fetch origin
git checkout main
git reset --hard origin/main
./scripts/install_latest.sh
```

`reset --hard` zahodí lokální necommitnuté změny. Pokud je nechceš ztratit, místo toho použij `git pull --ff-only origin main`.

Jedním příkazem (jen fast-forward pull aktuální větve, bez resetu):

```bash
./scripts/install_latest.sh --pull
```

Na feature větvi (např. `cursor/hotkey-ux-formatting-7dec`) stáhne tu větev, ne `main`.
Bez `--pull` skript skončí chybou, pokud jsi za `origin/<aktuální-větev>`.
Pro plný překlad po změně Swiftu: `./scripts/install_latest.sh --pull --clean`.

Pokud skript nezná `--clean`, nejdřív jednou ručně: `git pull --ff-only origin $(git branch --show-current)`.
Alternativa: `./scripts/update_and_install.sh --pull --clean` (pull + install v jednom).

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

Až vydáš release skriptem `./scripts/release.sh`, kolegové dostanou DMG a Sparkle update. Do té doby je pro tebe platný jen postup výše z **`origin/main`**.

Viz [RELEASING.md](RELEASING.md).

## První build (co uvidíš v terminálu)

1. **Stahování SPM balíčků** — WhisperKit, Sparkle, **mlx-swift** (lokální LLM post-processing). Na první build počítej **desítky minut** podle připojení.
2. **Kompilace** — dlouhý výpis `CompileMetalFile` u `mlx-swift` je normální.
3. **BUILD SUCCEEDED** — pak `install_latest.sh` dokončí instalaci do `/Applications`.

## Build selže: `missing Metal Toolchain`

Typická chyba na novějším Xcode (např. s macOS 26 SDK):

```text
error: cannot execute tool 'metal' due to missing Metal Toolchain
use: xcodebuild -downloadComponent MetalToolchain
```

**Oprava (jednou na Macu):**

```bash
xcodebuild -downloadComponent MetalToolchain
```

Nebo v **Xcode → Settings → Platforms / Components** doinstaluj **Metal Toolchain**.

Pak znovu:

```bash
cd ~/dictator
git pull origin main
./scripts/install_latest.sh
```

### Build selže: `unterminated string literal` u `Vložit`

Starší `main` měl rozbité uvozovky v `AppDelegate.swift`. Oprava je v commitu `4cd08e5` a novějším.

```bash
cd ~/dictator
git pull origin main
git log -1 --oneline   # mělo by být 4cd08e5 nebo novější
grep 'Vložit' Dictator/App/AppDelegate.swift
```

Řádek 596 musí končit `„Vložit“"` (česká uzavírací `“`), **ne** `„Vložit""`.

Pak znovu `./scripts/install_latest.sh`.

Při `Failed frontend command` bez jasné chyby scrollni výš v terminálu na řádky začínající `error:`.

Bez Metal Toolchainu nejde zkompilovat MLX; Dictator na `main` ho pro volitelný post-processing potřebuje v buildu vždy.

## Diagnostika

- Log: `~/Library/Logs/Dictator/diagnostics.log`
- Sparkle ruční kontrola: menu → Zkontrolovat aktualizace…
