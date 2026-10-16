// ProviderRules.js - logic: checks that depend on a provider's declared properties and are not
// about symbols or selections (those live in SymbolRules.js and SelectionPolicy.js).

.pragma library
.import "../Contracts/PluginError.js" as PluginError
.import "../Contracts/Resolution.js" as Resolution
.import "SymbolRules.js" as SymbolRules

// Is `credential` acceptable for a provider (`properties`: requiresCredential, disabled,
// credentialMinLength, credentialMaxLength)? A disabled provider never is.
function isValidCredential(properties, credential) {
    if (!properties) return true
    if (properties.disabled) return false
    if (!properties.requiresCredential) return true
    var value = (credential || "").trim()
    var minLength = properties.credentialMinLength || 1
    var maxLength = properties.credentialMaxLength || 0
    if (value.length < minLength) return false
    if (maxLength > 0 && value.length > maxLength) return false
    return true
}

// ── Declaration check ────────────────────────────────────────────────────────
// A provider's declared properties (plain data) and API module must be coherent before the plugin
// uses them; one broken provider is reported (ProviderLoadError) and the others keep working.

var API_FUNCTIONS = ["priceUrl", "historyUrl", "changeUrl", "parsePrice", "parseHistory", "parseChange", "pageUrl"]
var OPTIONAL_API_FUNCTIONS = ["extractApiError", "fetchScript"]

function _fail(id, detail) {
    throw new PluginError.PluginError(PluginError.Code.PROVIDER_CONFIG, "A data provider is misconfigured and was not loaded.",
                                      "Provider '" + id + "': " + detail)
}

// Throws a PROVIDER_CONFIG error naming the first problem found.
function assertDeclaration(id, declared, api) {
    if (!declared || typeof declared !== "object") _fail(id, "the declaration must be an object")
    if (declared.providerId !== id) _fail(id, "declares providerId '" + declared.providerId + "'")
    ;["name", "baseUrl", "symbolFormatMessage"].forEach(function(key) {
        if (typeof declared[key] !== "string" || declared[key] === "") _fail(id, "'" + key + "' must be a non-empty string")
    })
    if (!/^[A-Z]{3}$/.test(declared.alias)) _fail(id, "'alias' must be exactly three capital letters, e.g. YHF")
    var problem = SymbolRules.patternProblem(declared.symbolPattern)
    if (problem) _fail(id, problem)
    if (!(declared.symbolMinLength >= 1) || !(declared.symbolMaxLength >= declared.symbolMinLength))
        _fail(id, "symbol lengths must satisfy 1 <= min <= max")
    if (!Resolution.isValid(declared.minPullResolution)) _fail(id, "'minPullResolution' is not a Resolution")
    if (!Array.isArray(declared.priceResolutions) || declared.priceResolutions.length === 0) _fail(id, "'priceResolutions' must be a non-empty list")
    declared.priceResolutions.forEach(function(resolution) { if (!Resolution.isValid(resolution)) _fail(id, "unknown price resolution '" + resolution + "'") })
    if (!Array.isArray(declared.changeResolutions) || declared.changeResolutions.length === 0) _fail(id, "'changeResolutions' must be a non-empty list")
    declared.changeResolutions.forEach(function(r) { if (!Resolution.isValid(r)) _fail(id, "unknown change resolution '" + r + "'") })
    if (!Array.isArray(declared.chartLimits) || declared.chartLimits.length === 0) _fail(id, "'chartLimits' must be a non-empty list")
    var seen = {}
    declared.chartLimits.forEach(function(limit) {
        if (!limit || !Resolution.isValid(limit.resolution)) _fail(id, "unknown chart resolution in 'chartLimits'")
        if (seen[limit.resolution]) _fail(id, "chart resolution '" + limit.resolution + "' is declared twice")
        seen[limit.resolution] = true
        var days = limit.maxHistoryDays === undefined ? 0 : limit.maxHistoryDays
        if (typeof days !== "number" || !(days >= 0)) _fail(id, "'maxHistoryDays' of '" + limit.resolution + "' must be a number >= 0")
    })
    if (declared.requiresCredential && (typeof declared.credentialSettingKey !== "string" || declared.credentialSettingKey === ""))
        _fail(id, "a provider that needs a credential must declare 'credentialSettingKey'")
    if (!api || typeof api !== "object") _fail(id, "the API module is missing")
    API_FUNCTIONS.forEach(function(name) { if (typeof api[name] !== "function") _fail(id, "the API must provide `" + name + "`") })
    OPTIONAL_API_FUNCTIONS.forEach(function(name) {
        if (api[name] !== undefined && typeof api[name] !== "function") _fail(id, "`" + name + "` must be a function when present")
    })
}
