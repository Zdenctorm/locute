# Releasing Locute

Jak vydat novou verzi tak, aby se nainstalovaným klientům propsala automaticky přes Sparkle.

## Jednorázový setup (už hotovo)

- Sparkle 2.9 jako SPM dependency
- EdDSA klíče vygenerované přes `generate_keys` — privátní v Keychain, veřejný v `Info.plist` (`SUPublicEDKey`)
- `SUFeedURL` v `Info.plist` ukazuje na `https://raw.githubusercontent.com/Zdenctorm/locute/main/appcast.xml`
- Repo public (jinak by Sparkle u klientů dostal 401/404)
- Sparkle tools v `build/sparkle-tools/bin/` (`sign_update`, `generate_appcast`)
- `gh` CLI přihlášený

## Release nové verze

```bash
./scripts/release.sh 1.1.0
```

Volitelně s release notes:

```bash
echo "- Oprava XYZ\n- Lepší přepis cizích slov" > /tmp/notes.md
./scripts/release.sh 1.1.0 /tmp/notes.md
```

Co skript dělá:

1. Bumpne `MARKETING_VERSION` a `CURRENT_PROJECT_VERSION` v Xcode projektu
2. Postaví Release build a vytvoří DMG
3. Podepíše DMG Sparkle EdDSA klíčem
4. Vygeneruje/aktualizuje `appcast.xml` (nová verze na vrchu, historie zachovaná)
5. Commit + tag `v<version>` + push na `origin/main`
6. Vytvoří GitHub Release s DMG jako attachment

Po doběhnutí mají všichni nainstalovaní klienti během 24 hodin (nebo hned po kliknutí na „Zkontrolovat aktualizace…") notifikaci o nové verzi.

## Versioning

- Marketing version (`MARKETING_VERSION`) = semver, např. `1.2.0` — to vidí uživatel
- Build number (`CURRENT_PROJECT_VERSION`) = epoch seconds, monotónně rostoucí — to čte Sparkle interně (`sparkle:version`)

Sparkle určuje „je tohle novější verze?" podle `sparkle:version`. Epoch zaručí, že každý release je vždy novější.

## Co dělat při problémech

**Klienti nevidí update**
- Otevři appcast URL v prohlížeči — měl by tam být nový `<item>` nahoře
- Cache: Sparkle si pamatuje 24h. V appce: `defaults delete ai.anycoin.locute SULastCheckTime`
- Manuální check: menu → „Zkontrolovat aktualizace…"

**Build failne**
- Smaž `build/` a zkus znovu (`rm -rf build/DerivedData build/SourcePackages`)
- Chyba `no XCFramework found at .../claude/locute/build/SourcePackages/...` = projekt byl přesunut, ale SPM cache má starou absolutní cestu. `rm -rf build/SourcePackages` stačí (`build_release.sh` to od teď detekuje sám)
- `build_release.sh` nově failne při nevalidním strict codesign verify. Pro lokální-only test lze použít `ALLOW_UNVERIFIED_LOCAL_BUILD=1 ./scripts/build_release.sh`
- `xcodebuild -resolvePackageDependencies` ručně

**Sparkle hlásí "signature mismatch"**
- DMG byl po `sign_update` upravený (nepravděpodobné, ale teoreticky)
- Spusť release znovu

**„Unable to check for updates" / „Hledání aktualizací se nezdařilo"**
- U lokálního buildu (Xcode, `build_release.sh` bez Developer ID) je to **očekávané** — Sparkle vyžaduje podepsaný release
- Appka diktování funguje; auto-update až po `sign_and_notarize.sh` a distribuci DMG z GitHub Releases
- V menu u nepodepsaného buildu položka „Zkontrolovat aktualizace…" už není

**„Updater spadl" hned po startu / appka se nespustí**
- Typicky rozbitý code signing: hlavní binárka a `Sparkle.framework` mají různé Team ID (dyld: `different Team IDs`)
- Nepoužívej `codesign --deep` ani ruční přepodpis jen části bundle — `scripts/sign_and_notarize.sh` podepisuje inside-out jedním Developer ID
- Lokální `build_release.sh` nechává podpis z xcodebuild (linker-signed main + adhoc Sparkle) — to je v pořádku
- Pokud máš v `/tmp/Locute-resign.app` nebo po experimentu s `codesign`, smaž kopii a spusť čerstvý build z `dist/Locute.app` nebo Xcode Debug

## Distribuce kolegům

První DMG pošli ručně (Slack/Drive). Stáhne se z `https://github.com/Zdenctorm/locute/releases/latest`.

Od té chvíle dostávají všichni další updaty automaticky.

## Notarizace a Developer ID (bez Gatekeeper varování)

Pro firemní distribuci mimo Mac App Store je potřeba **Developer ID Application** certifikát a notarizace DMG. Skript je připravený v repozitáři:

```bash
export DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)'
export NOTARY_KEYCHAIN_PROFILE='notary-profile'   # nebo APPLE_ID + APPLE_TEAM_ID + APP_SPECIFIC_PASSWORD

./scripts/sign_and_notarize.sh
```

Kroky skriptu ([scripts/sign_and_notarize.sh](scripts/sign_and_notarize.sh)):

1. Release build + DMG (`build_release.sh`, `create_dmg.sh`)
2. Codesign aplikace a DMG
3. `notarytool submit --wait`
4. `stapler staple` na DMG

Ověření prostředí před release:

```bash
./scripts/verify_distribution_env.sh
```

Bez notarizace musí uživatelé při prvním spuštění použít pravý klik → Otevřít (viz [OVERVIEW.md](OVERVIEW.md)).
