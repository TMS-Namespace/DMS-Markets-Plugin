// SymbolMigration.js - logic: brings symbols saved by older versions up to the current format.
//
// This is the ONLY place that knows how earlier versions stored a symbol. Everything else (the
// providers, SelectionPolicy, the widget, the settings) only ever sees the current format.
//
//   upgrade(raw, defaultProvider, position) → { symbol, changed }  one raw saved entry, format only (a missing uid
//                                          is derived from provider, ticker and position: the same every time)
//   migrate(list, defaultProvider, rulesOf) → { symbols, changed }  a whole list: upgrade each entry,
//                                          then move its three range choices to the closest ones its
//                                          provider serves. `rulesOf(providerId)` returns that
//                                          provider's properties, or null when it is unknown.
// The input is never modified; unchanged entries come back as the very same objects.

.pragma library
.import "Helpers.js" as Helpers
.import "../Contracts/Resolution.js" as Resolution
.import "../Contracts/ChartSpan.js" as ChartSpan
.import "SelectionPolicy.js" as SelectionPolicy

// Field names used by older versions → current names.
var LEGACY_FIELDS = Object.freeze({
    id:              "ticker",            // the ticker text; `uid` is now the unique handle
    priceInterval:   "priceResolution",
    graphResolution: "chartResolution",
    graphInterval:   "chartRange"
})

// Chart ranges saved when a "range" also implied the candle (the value was a candle size).
var LEGACY_RANGES = Object.freeze({
    "15m": Object.freeze({ span: ChartSpan.Values.W1, resolution: Resolution.Values.D1 }),
    "1h":  Object.freeze({ span: ChartSpan.Values.W1, resolution: Resolution.Values.D1 }),
    "1d":  Object.freeze({ span: ChartSpan.Values.M1, resolution: Resolution.Values.D1 }),
    "1w":  Object.freeze({ span: ChartSpan.Values.M3, resolution: Resolution.Values.D1 })
})

// Candle size the earliest versions implicitly used for each span, before chart resolution existed.
var LEGACY_RESOLUTION = Object.freeze({
    "1W":  Resolution.Values.D1, "1M":  Resolution.Values.D1, "3M":  Resolution.Values.D1,
    "6M":  Resolution.Values.D1, "1Y":  Resolution.Values.D1, "2Y":  Resolution.Values.W1,
    "5Y":  Resolution.Values.W1, "10Y": Resolution.Values.MO1
})

var _FLAGS = ["showChangeWhenPinned", "invert", "pinned"]

function upgrade(raw, defaultProvider, position) {
    var copy = Helpers.copyOf(raw)
    var changed = false

    for (var legacy in LEGACY_FIELDS) {
        if (!(legacy in copy)) continue
        var current = LEGACY_FIELDS[legacy]
        if (copy[current] === undefined) copy[current] = copy[legacy]
        delete copy[legacy]
        changed = true
    }

    // A range that was really a candle size, and symbols saved before chart resolution existed.
    var legacyRange = LEGACY_RANGES[copy.chartRange]
    if (legacyRange) {
        copy.chartRange = legacyRange.span
        if (!Resolution.isValid(copy.chartResolution)) copy.chartResolution = legacyRange.resolution
        changed = true
    } else if (!Resolution.isValid(copy.chartResolution) && ChartSpan.isValid(copy.chartRange)) {
        copy.chartResolution = LEGACY_RESOLUTION[copy.chartRange]
        changed = true
    }

    if (!Helpers.isUuid(copy.uid)) {
        // Deterministic, so every migrator of the same saved list agrees on the handles.
        copy.uid = Helpers.uuidFrom((copy.provider || defaultProvider || "") + "|" + (copy.ticker || "") + "|" + position)
        changed = true
    }
    if ((typeof copy.provider !== "string" || copy.provider === "") && defaultProvider) {
        copy.provider = defaultProvider
        changed = true
    }
    if (typeof copy.name !== "string" && typeof copy.ticker === "string") { copy.name = copy.ticker; changed = true }
    for (var i = 0; i < _FLAGS.length; i++) {
        var normalised = Helpers.boolValue(copy[_FLAGS[i]], false)
        if (copy[_FLAGS[i]] !== normalised) { copy[_FLAGS[i]] = normalised; changed = true }
    }
    return { symbol: changed ? copy : raw, changed: changed }
}

function migrate(list, defaultProvider, rulesOf) {
    var changed = false
    var symbols = (list || []).map(function(raw, position) {
        var upgraded = upgrade(raw, defaultProvider, position)
        var symbol = upgraded.symbol
        var symbolChanged = upgraded.changed

        var rules = rulesOf(symbol.provider || defaultProvider)
        if (rules) {
            var selection = SelectionPolicy.clamp(rules, symbol)
            if (symbol.priceResolution !== selection.priceResolution
                    || symbol.changeResolution !== selection.changeResolution
                    || symbol.chartResolution !== selection.chartResolution
                    || symbol.chartRange !== selection.chartRange) {
                if (symbol === raw) symbol = Helpers.copyOf(raw)
                symbol.priceResolution = selection.priceResolution
                symbol.changeResolution = selection.changeResolution   // symbols saved before it existed get the default
                symbol.chartResolution = selection.chartResolution
                symbol.chartRange      = selection.chartRange
                symbolChanged = true
            }
        }
        if (symbolChanged) changed = true
        return symbol
    })
    return { symbols: symbols, changed: changed }
}
