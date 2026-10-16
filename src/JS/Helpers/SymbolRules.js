// SymbolRules.js - logic: is a symbol acceptable for a provider?
//
// A provider declares its symbol rules as data (ProviderProperties: symbolPattern, symbolMinLength,
// symbolMaxLength, symbolFormatMessage); this module applies them. Symbols reach a shell command line
// and a URL, so a pattern may never admit whitespace, quotes or shell/URL metacharacters - that is
// checked when a provider is declared (`patternProblem`).
//
//   SymbolRules.validate(properties, "BRLPLN")      → { valid, message }
//   SymbolRules.assertValid(properties, "BRLPLN")   → throws an INVALID_SYMBOL PluginError

.pragma library
.import "../Contracts/PluginError.js" as PluginError
.import "Constants.js" as Constants

var FORBIDDEN_CHARS = Object.freeze([" ", "\t", "\n", "\r", "\0", "'", "\"", "`", "$", ";", "|", "<", ">",
                                     "(", ")", "{", "}", "\\", "#", "?", "%", "/", "*", "!", "~", ","])

// "" when `pattern` is an acceptable symbol pattern, otherwise what is wrong with it.
function patternProblem(pattern) {
    if (typeof pattern !== "string" || pattern.length < 3 || pattern.charAt(0) !== "^" || pattern.charAt(pattern.length - 1) !== "$")
        return "'symbolPattern' must be an anchored regular expression (^...$)"
    var regex
    try { regex = new RegExp(pattern) } catch (e) { return "'symbolPattern' is not a valid regular expression" }
    for (var i = 0; i < FORBIDDEN_CHARS.length; i++) {
        var character = FORBIDDEN_CHARS[i]
        if (regex.test(character) || regex.test("A" + character) || regex.test(character + "A") || regex.test("A" + character + "A"))
            return "'symbolPattern' must not allow the character " + JSON.stringify(character)
    }
    return ""
}

// `rules` is anything with name, symbolPattern, symbolMinLength, symbolMaxLength, symbolFormatMessage
// (a ProviderProperties). Returns plain { valid, message }; `message` is a short, user-facing
// explanation when invalid.
function validate(rules, symbol) {
    if (typeof symbol !== "string" || symbol === "")
        return { valid: false, message: "Enter a symbol. " + rules.symbolFormatMessage }
    if (symbol.length < rules.symbolMinLength || symbol.length > rules.symbolMaxLength)
        return { valid: false, message: "A " + rules.name + " symbol has "
                 + (rules.symbolMinLength === rules.symbolMaxLength ? rules.symbolMinLength
                    : rules.symbolMinLength + " to " + rules.symbolMaxLength)
                 + " characters. " + rules.symbolFormatMessage }
    if (!new RegExp(rules.symbolPattern).test(symbol))
        return { valid: false, message: rules.symbolFormatMessage }
    return { valid: true, message: "" }
}

// The display name a user gives a symbol: 1 to DISPLAY_NAME_MAX_LENGTH characters from a fixed set (spaces included, but not only spaces).
// Returns plain { valid, message } like `validate`.
function validateName(name) {
    if (typeof name !== "string" || name === "")
        return { valid: false, message: "Enter a display name." }
    if (name.length > Constants.DISPLAY_NAME_MAX_LENGTH)
        return { valid: false, message: "The display name can have at most " + Constants.DISPLAY_NAME_MAX_LENGTH + " characters." }
    if (!new RegExp(Constants.DISPLAY_NAME_PATTERN).test(name))
        return { valid: false, message: "The display name can only have letters, digits, spaces and - + * / \\ . ~ % $ ^ _ ? ! # ( ) [ ] =" }
    if (name.trim() === "")
        return { valid: false, message: "Enter a display name." }
    return { valid: true, message: "" }
}

// Throws before any request is built from a symbol that is not acceptable.
function assertValid(rules, symbol) {
    var verdict = validate(rules, symbol)
    if (!verdict.valid)
        throw new PluginError.PluginError(PluginError.Code.INVALID_SYMBOL, verdict.message,
            rules.name + ": invalid symbol " + JSON.stringify(String(symbol).slice(0, 40)) + ". " + verdict.message)
}
