# Formátování diktovaného textu (Locute)

## Problém

Whisper vrací souvislý text **bez interpunkce**. To je normální u speech-to-text — většina nástrojů (Wispr Flow, Superwhisper, Aqua) problém řeší **až v post-processingu**, ne v samotném přepisu.

## Dvě vrstvy v Locute

| Vrstva | Kdy běží | Co dělá |
|--------|----------|---------|
| **Pravidla (vždy, offline)** | Po každém diktátu | Mezery, mluvené příkazy („tečka“, „nový odstavec“), heuristická interpunkce v češtině, velká písmena na začátku vět, struktura e-mailu podle aplikace / frází |
| **Lokální LLM (volitelné)** | Pokud je zapnuté v menu a model je stažený | Doladí delší texty: věty, odstavce, tón podle aplikace (Mail, Slack, …) |

**Vypnutí LLM v menu baru neznamená, že Locute neformátuje.** Znamená to jen, že se nepoužije druhá vrstva. První vrstva běží vždy.

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

Kvalita není jako u člověka ani u velkého LLM — u delších textů doporučujeme zapnout **Doladění přepisu (lokální LLM)**.

## Power user

Stále platí mluvené příkazy: **tečka**, **čárka**, **nový odstavec**, **otazník**, … — mají prioritu před heuristikou.

## Jak to dělají ostatní

- **Wispr / Aqua:** cloudový „auto-edit“ podle kontextu aplikace
- **Superwhisper:** prompty / módy
- **Apple Dictation:** uživatel diktuje interpunkci sám
- **Locute:** pravidla vždy lokálně + volitelný lokální LLM (bez cloudu)

Implementace: `CzechDictationFormatter.swift`, `CzechHeuristicPunctuator.swift`, `PostProcessingEngine.swift`.
