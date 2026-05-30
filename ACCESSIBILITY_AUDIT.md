# Analýza zpřístupnění (VoiceOver)

Dictator umí vygenerovat **podrobnou analýzu zpřístupnění** přímo z menu — bez externích nástrojů a bez odesílání dat ze zařízení.

## Spuštění

1. Spusť Dictator z Xcode nebo z `/Applications/Dictator.app`.
2. V menu baru klikni na ikonu Dictatoru.
3. Zvol **Analýza zpřístupnění (VoiceOver)…**

Aplikace:

- otevře okno **Nastavení** (aby audit viděl hlavní UI),
- projde viditelné okna a položky menu,
- stručně vzorkuje referenční macOS aplikace (pokud máš povolené **Zpřístupnění** pro Dictator),
- uloží Markdown zprávu do `~/Library/Logs/Dictator/accessibility-audit-*.md`,
- otevře složku v Finderu.

## Referenční aplikace

Audit porovnává metriky (podíl prvků s popiskem a nápovědou) s těmito appkami:

| Aplikace | Proč |
|----------|------|
| Nastavení | Vzor nativního AppKit UI s přepínači |
| Poznámky | Textový editor |
| Hlasové poznámky | Audio + stav nahrávání |
| Zkratky | Utility / panelová appka |

**Tip:** Než spustíš audit, otevři jednu referenční appku a dej ji do popředí — vzorek bere **aktuální fokusované okno** dané aplikace.

## Jak číst zprávu

Zpráva obsahuje:

1. **Shrnutí** — počty kritických/varovných nálezů.
2. **Srovnání** — tabulka Dictator vs. referenční appky.
3. **Inventář povrchů** — co všechno appka má (menu bar, overlay, hotkey, panel přepisu) a **ruční kontrolní body** pro VoiceOver.
4. **Automatické nálezy** — konkrétní cesta v UI + návrh opravy.
5. **Doporučený postup úprav** — prioritizovaný roadmap.
6. **Kontrolní seznam před vydáním**.

Malá menu bar appka při rozšíření o Nastavení, overlay a přepis narůstá v **počtu povrchů**, které musí být srozumitelné bez obrazovky. Inventář v zprávě pomáhá vidět celý rozsah, ne jen aktuálně otevřené okno.

## Opakování po úpravách

Po změnách v `AccessibilitySupport.swift` nebo konkrétních view:

1. Znovu spusť analýzu z menu.
2. Porovnej nový `accessibility-audit-*.md` s předchozím (diff v git nebo v editoru).
3. Projdi ruční checklist na konci zprávy s **VoiceOver zapnutým** (⌘ + F5).

## Oprávnění Zpřístupnění

Bez povolení Dictatoru v **Nastavení → Soukromí a zabezpečení → Zpřístupnění**:

- audit Dictator UI stále proběhne,
- srovnání s jinými aplikacemi bude přeskočeno (status `skippedNoAXTrust`).

Pro plnou analýzu povol Zpřístupnění stejně jako pro diktování a vkládání textu.
