// SymbolDraft.js — logic: the data of the "add / edit symbol" form, built from a saved symbol or for a new one.
// Only calculates plain data; showing it is the settings page's (QML) job, keeping it is DataStorage's.

.pragma library
.import "Helpers.js" as Helpers

// A draft is { ticker, name, provider, priceResolution, changeResolution, chartResolution, chartRange, showChange, invert }.

// The draft that edits a saved symbol.
function fromSymbol(symbol, defaultProviderId) {
    return {
        ticker: symbol.ticker || "", name: symbol.name || "", provider: symbol.provider || defaultProviderId,
        priceResolution: symbol.priceResolution, changeResolution: symbol.changeResolution, chartResolution: symbol.chartResolution, chartRange: symbol.chartRange,
        showChange: Helpers.boolValue(symbol.showChangeWhenPinned, false), invert: Helpers.boolValue(symbol.invert, false)
    }
}

// The empty draft for a new symbol: the provider's default selection, both flags off.
function empty(providerId, selection) {
    return {
        ticker: "", name: "", provider: providerId,
        priceResolution: selection.priceResolution, changeResolution: selection.changeResolution, chartResolution: selection.chartResolution, chartRange: selection.chartRange,
        showChange: false, invert: false
    }
}
