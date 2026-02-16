// providers.js — Market Data Provider Abstraction Layer
//
// Provider Interface:
// {
//     name:                 string,
//     intervalMap:          { intervalId: providerParam },
//     buildPriceUrl:        function(symbol, interval) → string,
//     buildHistoryUrl:      function(symbol, interval) → string,
//     parsePriceResponse:   function(csvText) → DataPoint[],
//     parseHistoryResponse: function(csvText) → DataPoint[]
// }
//
// DataPoint: { date, time, open, high, low, close, volume }
//
// To add a new provider, call registerProvider("id", { ...interface }) at the
// bottom of this file.  The widget and settings will auto-discover it.

.pragma library

// ─── Registry ────────────────────────────────────────────────────────────────

var _providers = {};

function registerProvider(id, provider) {
    _providers[id] = provider;
}

function getProvider(id) {
    return _providers[id] || null;
}

function getProviderIds() {
    return Object.keys(_providers);
}

function getProviderName(id) {
    var p = _providers[id];
    return p ? p.name : id;
}

function getSupportedIntervals(providerId) {
    var p = _providers[providerId];
    if (!p) return [];
    return Object.keys(p.intervalMap);
}

// ─── URL Builders ────────────────────────────────────────────────────────────

function buildPriceUrl(symbol, providerId, interval) {
    var p = _providers[providerId];
    if (!p) return "";
    return p.buildPriceUrl(symbol, interval);
}

function buildHistoryUrl(symbol, providerId, interval) {
    var p = _providers[providerId];
    if (!p) return "";
    return p.buildHistoryUrl(symbol, interval);
}

// ─── Parsers ─────────────────────────────────────────────────────────────────

function parsePriceResponse(providerId, csvText) {
    var p = _providers[providerId];
    if (!p) return [];
    return p.parsePriceResponse(csvText);
}

function parseHistoryResponse(providerId, csvText) {
    var p = _providers[providerId];
    if (!p) return [];
    return p.parseHistoryResponse(csvText);
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

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

function _safeFloat(s) {
    if (!s || s === "N/D" || s === "null" || s === "NaN") return NaN;
    var v = parseFloat(s);
    return v;
}

// ─── Stooq Provider ─────────────────────────────────────────────────────────
//
// Stooq (https://stooq.com) publishes free CSV quotes for a wide range of
// instruments: forex, indices, commodities, crypto, equities.
//
// Latest‐candle endpoint (no header):
//   GET /q/l/?s=<symbol>&i=<interval>
//   → Symbol,Date,Time,Open,High,Low,Close,Volume
//
// Historical download endpoint (with header row):
//   GET /q/d/l/?s=<symbol>&i=<interval>
//   → Date,Open,High,Low,Close,Volume
//
// Common symbols:
//   dx.f    USDX (Dollar Index)       eurusd  EUR/USD
//   gbpusd  GBP/USD                   usdjpy  USD/JPY
//   gc.f    Gold futures              si.f    Silver futures
//   cl.f    Crude Oil futures         btcusd  Bitcoin/USD
//   ^spx    S&P 500                   ^dji    Dow Jones
//   ^ndq    Nasdaq 100                ^ftse   FTSE 100

registerProvider("stooq", {
    name: "Stooq",

    intervalMap: {
        "5m":  "5",
        "15m": "15",
        "1h":  "h",
        "1d":  "d",
        "1w":  "w",
        "1M":  "m"
    },

    buildPriceUrl: function(symbol, interval) {
        var i = this.intervalMap[interval] || "h";
        return "https://stooq.com/q/l/?s="
            + encodeURIComponent(symbol) + "&i=" + i;
    },

    buildHistoryUrl: function(symbol, interval) {
        var i = this.intervalMap[interval] || "d";
        return "https://stooq.com/q/d/l/?s="
            + encodeURIComponent(symbol) + "&i=" + i;
    },

    // /q/l/ — no header, fields: Symbol,Date,Time,Open,High,Low,Close[,Volume]
    parsePriceResponse: function(csvText) {
        var lines = csvText.trim().split("\n");
        var results = [];
        for (var idx = 0; idx < lines.length; idx++) {
            var line = lines[idx].trim();
            if (!line) continue;
            var f = line.split(",");
            if (f.length < 7) continue;

            var open = _safeFloat(f[3]);
            if (isNaN(open)) continue;           // skip header / invalid rows

            results.push({
                symbol: f[0],
                date:   f[1],
                time:   f[2],
                open:   open,
                high:   _safeFloat(f[4]),
                low:    _safeFloat(f[5]),
                close:  _safeFloat(f[6]),
                volume: f.length > 7 ? (parseInt(f[7]) || 0) : 0
            });
        }
        return results;
    },

    // /q/d/l/ — header row, fields: Date,Open,High,Low,Close[,Volume]
    parseHistoryResponse: function(csvText) {
        var lines = csvText.trim().split("\n");
        var results = [];
        for (var idx = 0; idx < lines.length; idx++) {
            var line = lines[idx].trim();
            if (!line) continue;
            var f = line.split(",");
            if (f.length < 5) continue;

            var open = _safeFloat(f[1]);
            if (isNaN(open)) continue;           // skip header row

            results.push({
                date:   f[0],
                time:   "",
                open:   open,
                high:   _safeFloat(f[2]),
                low:    _safeFloat(f[3]),
                close:  _safeFloat(f[4]),
                volume: f.length > 5 ? (parseInt(f[5]) || 0) : 0
            });
        }
        return results;
    }
});
