# Formátování diktovaného textu (Locute)

## Problém

Whisper vrací souvislý text **bez interpunkce**. To je normální u speech-to-text — většina nástrojů (Wispr Flow, Superwhisper, Aqua) problém řeší **až v post-processingu**, ne v samotném přepisu.

## Dvě vrstvy v Locute

| Vrstva | Kdy běží | Co dělá |
|--------|----------|---------|
| **Pravidla (vždy, offline)** | Po každém diktátu | Mezery, mluvené příkazy („tečka“, „nový odstavec“), heuristická interpunkce v češtině, velká písmena na začátku vět, struktura e-mailu podle aplikace / frází |
| **Lepší formátování (volitelné)** | Zapnuto v menu **a** doplněk je načtený na Macu | Doladí delší texty: věty, odstavce, tón podle aplikace (Mail, Slack, …) |

**Vypnutí v menu neznamená, že Locute neformátuje.** Znamená to jen, že se nepoužije druhá vrstva. První vrstva běží vždy.

### Co vidí uživatel při startu

1. **Stahování / načítání modelu přepisu** (Whisper) — progress v okně startu, v menu „Připravuji model“.
2. Až je přepis **Připraveno**, může diktovat hned.
3. Pokud je zapnuté **Lepší formátování**, v menu (a v okně startu) zůstane **„Připravuji formátování (X %)“** — to je *jiný* jednorázový doplněk, ne model diktování. Do té doby platí jen pravidla; po načtení se doplněk použije automaticky.

Technické názvy modelů (Qwen, Llama) jsou jen v diagnostice / kódu, ne v běžném UI.

## E-mail

V Mailu (a podobných klientech), nebo když přepis obsahuje typické fráze:

- **Pozdrav** (`dobrý den`, `vážený pane`, …) → čárka a prázdný řádek za pozdravem
- **Závěr** (`s pozdravem`, `s úctou`, `děkuji`, …) → nový odstavec a velké počáteční písmeno

Per-app instrukce pro LLM jsou v `AppContextPostProcessingStore` (výchozí preset pro `com.apple.mail`).

## Interpunkce bez mluvených příkazů

Heuristika (offline) mimo jiné:

- čárka před `že`, `když`, `protože`, `který`/`která`, …
- tečka před dlouhými větami s `ale`, `proto`, `takže`, `potom`, …
- `?` u otázek začínajících na `jak`, `proč`, `kde`, …
- tečka na konci utterance, pokud chybí

Pravidla jsou v `CzechPunctuationRules.swift` (čárky před podřazením, konce vět, otazníky). **Pomlčky (—, –) se nikdy nevkládají** — nahrazují se čárkou nebo tečkou.

Lokální model smí jen doplnit znaki. Když odpoví jako chat („Samozřejmě…“, „Rád pomohu…“) nebo přidá cizí věty, výstup se **zahodí** a zůstanou pravidla.

## Power user

Stále platí mluvené příkazy: **tečka**, **čárka**, **nový odstavec**, **otazník**, … — mají prioritu před heuristikou.

## Jak to dělají ostatní

- **Wispr / Aqua:** cloudový „auto-edit“ podle kontextu aplikace
- **Superwhisper:** prompty / módy
- **Apple Dictation:** uživatel diktuje interpunkci sám
- **Locute:** pravidla vždy lokálně + volitelný lokální LLM (bez cloudu)

Implementace: `CzechPunctuationRules.swift`, `CzechHeuristicPunctuator.swift`, `CzechDictationFormatter.swift`, `PostProcessingOutputSanitizer.swift`, `PostProcessingEngine.swift`.
