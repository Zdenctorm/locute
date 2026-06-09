import Foundation

/// Česká interpunkční pravidla pro offline úpravu přepisu (vychází z běžné pravopisné praxe / ÚJČ).
///
/// Locute zde **nediktuje styl** — jen doplňuje znaky podle typických vzorů mluveného projevu.
/// LLM vrstva smí dělat totéž, nikoli odpovídat ani měnit slova.
enum CzechPunctuationRules {
    // MARK: - Čárky (podřazení, doplnění, vložený výraz)

    static let commaBeforeSubordinators = [
        "že", "když", "protože", "pokud", "jestliže", "aby", "než",
        "který", "která", "které", "kteří", "kde", "jestli", "zda",
        "proto", "tedy", "totiž", "například", "ovšem", "však", "případně",
    ]

    // MARK: - Hranice vět (souřadné odporování / navazování)

    static let periodBeforeConjunctions = [
        "ale", "avšak", "takže", "potom", "pak", "navíc",
        "nicméně", "přesto", "zároveň", "nakonec", "jinak",
    ]

    // MARK: - Otázky (slova a ustálené fráze)

    static let questionStarters = [
        "jak", "proč", "kde", "kdy", "kolik", "co", "kdo", "čí", "číž",
        "který", "která", "které", "jaký", "jaká", "jaké", "copak", "snad",
        "můžeš", "můžete", "můžeme", "můžu", "mohu",
        "máš", "máte", "má", "máme", "je", "jsou", "bude", "budou",
    ]

    static let questionPhrases = [
        "je to možné", "je možné", "šlo by", "jde o to",
        "má to smysl", "že ne", "nebo ne",
        "jak se ", "jak ti ", "jak vám ", "jak vam ",
    ]

    // MARK: - Znaky zakázané ve výstupu diktování

    static let forbiddenDashes = ["—", "–", "−", "‑"]

    // MARK: - Limity délky věty bez interpunkce

    static let maxWordsWithoutPunctuation = 12
    static let minWordsBeforeClauseBreak = 4
}
