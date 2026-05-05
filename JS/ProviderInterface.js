// ProviderInterface.js — Market Data Provider Abstraction Layer
//
// This file defines the provider registry and public API. All provider-specific
// logic (URL building, response parsing) lives in separate provider files
// (e.g. StooqProvider.js) that register themselves into this singleton.
//
// ─── Provider Contract ───────────────────────────────────────────────────────
//
// Each provider must implement this interface:
//
// {
//     name:                    string,
//
//     // Supported candle intervals — maps internal keys to provider params
//     intervalMap:             { "5m": "...", "1h": "...", "1d": "...", ... },
//
//     // ── Price ──────────────────────────────────────────────────────────
//     // Build URL for latest-candle price data
//     buildPriceUrl:           function(symbol: string, interval: string) → string,
//     //
//     // Parse response → DataPoint[]
//     parsePriceResponse:      function(responseText: string) → DataPoint[],
//
//     // ── History ────────────────────────────────────────────────────────
//     // Build URL for historical candle data (sparkline)
//     buildHistoryUrl:         function(symbol: string, interval: string) → string,
//     //
//     // Parse response → DataPoint[]
//     parseHistoryResponse:    function(responseText: string) → DataPoint[],
//
//     // ── Search ─────────────────────────────────────────────────────────
//     // Build URL for symbol search / autocomplete
//     buildSearchUrl:          function(query: string) → string,
//     //
//     // Parse response → SearchResult[]
//     parseSearchResponse:     function(responseText: string) → SearchResult[],
//
//     // ── Validation ─────────────────────────────────────────────────────
//     // Build URL to verify a symbol exists
//     buildValidationUrl:      function(ticker: string) → string,
//     //
//     // Parse response → ValidationResult
//     parseValidationResponse: function(responseText: string) → ValidationResult,
//
//     // ── Navigation ─────────────────────────────────────────────────────
//     // Build a browser-friendly URL for the symbol page
//     buildSymbolPageUrl:      function(symbolId: string) → string
// }
//
// ─── Return Type Contracts ───────────────────────────────────────────────────
//
// DataPoint: {
//     date:   string,       // e.g. "2026-02-16"
//     time:   string,       // e.g. "14:30:00" or ""
//     open:   number,
//     high:   number,
//     low:    number,
//     close:  number,
//     volume: number        // 0 if unavailable
// }
//
// SearchResult: {
//     id:        string,    // e.g. "eurusd"
//     name:      string,    // e.g. "Euro / U.S. Dollar"
//     market:    string,    // e.g. "Currency"
//     price:     string,    // e.g. "1.18552" (display string)
//     changeStr: string     // e.g. "-0.16%" (display string)
// }
//
// ValidationResult: {
//     valid:   bool,        // true if the symbol exists and has data
//     message: string       // human-readable reason on failure
// }

.pragma library

// ─── Registry ────────────────────────────────────────────────────────────────

var _providers = {};
var _defaultProviderId = "";
var _apiKeys = {};

// ─── API Key Management ───────────────────────────────────────────────────────

function setApiKey(providerId, apiKey) {
    _apiKeys[providerId] = apiKey || "";
}

function getApiKey(providerId) {
    return _apiKeys[providerId] || "";
}

// Returns true when a response indicates a missing or invalid API key
function isApiKeyError(responseText) {
    return !!(responseText && responseText.trim().toLowerCase().startsWith(JsK.API_KEY_ERROR_SENTINEL))
}

function registerProvider(id, provider) {
    _providers[id] = provider;
    // First registered provider becomes the default
    if (!_defaultProviderId) _defaultProviderId = id;
}

function getProvider(id) {
    return _providers[id] || null;
}

function getProviderIds() {
    return Object.keys(_providers);
}

function getProviderName(id) {
    var provider = _providers[id];
    return provider ? provider.name : id;
}

// Returns the ID of the default provider (first registered)
function getDefaultProviderId() {
    return _defaultProviderId;
}

// Returns an array of { label: string, value: string } for use in SelectionSetting
function getProviderOptions() {
    var options = [];
    var providerIds = Object.keys(_providers);
    for (var index = 0; index < providerIds.length; index++) {
        options.push({ label: _providers[providerIds[index]].name, value: providerIds[index] });
    }
    return options;
}

function getSupportedIntervals(providerId) {
    var provider = _providers[providerId];
    if (!provider) return [];
    return Object.keys(provider.intervalMap);
}

// ─── Price ───────────────────────────────────────────────────────────────────

function buildPriceUrl(symbol, providerId, interval) {
    var provider = _providers[providerId];
    if (!provider) return "";
    return provider.buildPriceUrl(symbol, interval);
}

function parsePriceResponse(providerId, responseText) {
    var provider = _providers[providerId];
    if (!provider) return [];
    return provider.parsePriceResponse(responseText);
}

// ─── History ─────────────────────────────────────────────────────────────────

function buildHistoryUrl(symbol, providerId, interval) {
    var provider = _providers[providerId];
    if (!provider) return "";
    return provider.buildHistoryUrl(symbol, interval);
}

function parseHistoryResponse(providerId, responseText) {
    var provider = _providers[providerId];
    if (!provider) return [];
    return provider.parseHistoryResponse(responseText);
}

// ─── Search ──────────────────────────────────────────────────────────────────

function buildSearchUrl(providerId, query) {
    var provider = _providers[providerId];
    if (!provider) return "";
    return provider.buildSearchUrl(query);
}

function parseSearchResponse(providerId, responseText) {
    var provider = _providers[providerId];
    if (!provider) return [];
    return provider.parseSearchResponse(responseText);
}

// ─── Validation ──────────────────────────────────────────────────────────────

function buildValidationUrl(providerId, ticker) {
    var provider = _providers[providerId];
    if (!provider) return "";
    return provider.buildValidationUrl(ticker);
}

function parseValidationResponse(providerId, responseText) {
    var provider = _providers[providerId];
    if (!provider) return { valid: false, message: "Unknown provider: " + providerId };
    return provider.parseValidationResponse(responseText);
}

// ─── Navigation ──────────────────────────────────────────────────────────────

function buildSymbolPageUrl(providerId, symbolId) {
    var provider = _providers[providerId];
    if (!provider) return "";
    return provider.buildSymbolPageUrl(symbolId);
}

// ─── Interval Helpers ────────────────────────────────────────────────────────

function getIntervalLabel(interval) {
    var labels = {
        "5m":  "5 min",
        "15m": "15 min",
        "1h":  "1 hour",
        "1d":  "1 day",
        "1w":  "1 week",
        "1M":  "1 month"
    };
    return labels[interval] || interval;
}

// ─── Chart Range Helpers ─────────────────────────────────────────────────────
// Chart range controls how much historical data the sparkline shows.
// Each range maps to a candle interval, max data points, and refresh interval.

var _chartRanges = {
    "1W":  { interval: "1d", maxPoints: 7,    refreshMs: 3600000   },
    "1M":  { interval: "1d", maxPoints: 30,   refreshMs: 14400000  },
    "3M":  { interval: "1d", maxPoints: 65,   refreshMs: 86400000  },
    "6M":  { interval: "1d", maxPoints: 130,  refreshMs: 86400000  },
    "1Y":  { interval: "1d", maxPoints: 260,  refreshMs: 86400000  },
    "2Y":  { interval: "1w", maxPoints: 104,  refreshMs: 604800000 },
    "5Y":  { interval: "1w", maxPoints: 260,  refreshMs: 604800000 },
    "10Y": { interval: "1M", maxPoints: 120,  refreshMs: 604800000 }
};

function getPriceInterval(range) {
    return range || "1d";
}

var _legacyRangeMap = {
    "15m": "1W",
    "1h":  "1W",
    "1d":  "1M",
    "1w":  "3M"
};

function normalizeChartRange(value) {
    if (_chartRanges[value]) return value;
    return _legacyRangeMap[value] || "1M";
}

function getHistoryConfig(chartRange) {
    var range = normalizeChartRange(chartRange);
    return _chartRanges[range];
}

function getChartRangeLabel(range) {
    var labels = {
        "1W": "1 Week",
        "1M": "1 Month",
        "3M": "3 Months",
        "6M": "6 Months",
        "1Y": "1 Year",
        "2Y": "2 Years",
        "5Y": "5 Years",
        "10Y": "10 Years"
    };
    return labels[normalizeChartRange(range)] || range;
}
