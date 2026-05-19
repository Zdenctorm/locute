# Releasing Dictator

Jak vydat novou verzi tak, aby se nainstalovaným klientům propsala automaticky přes Sparkle.

## Jednorázový setup (už hotovo)

- Sparkle 2.9 jako SPM dependency
- EdDSA klíče vygenerované přes `generate_keys` — privátní v Keychain, veřejný v `Info.plist` (`SUPublicEDKey`)
- `SUFeedURL` v `Info.plist` ukazuje na `https://raw.githubusercontent.com/Zdenctorm/dictator/main/appcast.xml`
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
- Cache: Sparkle si pamatuje 24h. V appce: `defaults delete ai.anycoin.dictator SULastCheckTime`
- Manuální check: menu → „Zkontrolovat aktualizace…"

**Build failne**
- Smaž `build/` a zkus znovu (`rm -rf build/DerivedData build/SourcePackages`)
- `xcodebuild -resolvePackageDependencies` ručně

**Sparkle hlásí "signature mismatch"**
- DMG byl po `sign_update` upravený (nepravděpodobné, ale teoreticky)
- Spusť release znovu

## Distribuce kolegům

První DMG pošli ručně (Slack/Drive). Stáhne se z `https://github.com/Zdenctorm/dictator/releases/latest`.

Od té chvíle dostávají všichni další updaty automaticky.
