// StooqProvider.js — Stooq market data provider
//
// Stooq (https://stooq.com) publishes free CSV quotes for a wide range of
// instruments: forex, indices, commodities, crypto, equities.
//
// Endpoints:
//   Latest candle/history CSV:   GET /q/d/l/?s=<symbol>&i=<interval>
//   Symbol page:                  https://stooq.com/q/?s=<symbol>
//
// Common CSV symbols:
//   eurusd  EUR/USD                   gbpusd  GBP/USD
//   usdjpy  USD/JPY                   btcusd  Bitcoin/USD
//   ^spx    S&P 500                   ^dji    Dow Jones
//   ^ndq    Nasdaq 100                ^ftse   FTSE 100

.import "ProviderInterface.js" as PI

// ─── Helpers ─────────────────────────────────────────────────────────────────

function _safeFloat(rawValue) {
    if (!rawValue || rawValue === "N/D" || rawValue === "null" || rawValue === "NaN") return NaN;
    return parseFloat(rawValue);
}

function _appendApiKey(url) {
    var apiKey = PI.getApiKey("stooq");
    if (apiKey) url += "&apikey=" + encodeURIComponent(apiKey);
    return url;
}

// ─── Provider Registration ───────────────────────────────────────────────────

PI.registerProvider("stooq", {
    name: "Stooq",

    intervalMap: {
        "5m":  "5",
        "15m": "15",
        "1h":  "h",
        "1d":  "d",
        "1w":  "w",
        "1M":  "m"
    },

    // ── Price ────────────────────────────────────────────────────────────

    // /q/d/l/?s=SYMBOL&i=INTERVAL → Date,Open,High,Low,Close[,Volume]
    buildPriceUrl: function(symbol, interval) {
        // Stooq's former latest-candle endpoint (/q/l/) now returns 404.
        // The downloadable CSV endpoint currently serves daily/weekly/monthly
        // data with an API key, so intraday selections fall back to daily.
        var intervalParam = (interval === "1w" || interval === "1M")
            ? this.intervalMap[interval]
            : "d";
        var url = "https://stooq.com/q/d/l/?s="
            + encodeURIComponent(symbol) + "&i=" + intervalParam;
        return _appendApiKey(url);
    },

    // Returns: DataPoint[]
    parsePriceResponse: function(responseText) {
        var lines = responseText.trim().split("\n");
        var results = [];
        for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
            var line = lines[lineIndex].trim();
            if (!line) continue;
            if (line === "No data") continue;

            var fields = line.split(",");
            if (fields.length < 5) continue;

            var open = _safeFloat(fields[1]);
            if (isNaN(open)) continue;           // skip header / invalid rows

            results.push({
                symbol: "",
                date:   fields[0],
                time:   "",
                open:   open,
                high:   _safeFloat(fields[2]),
                low:    _safeFloat(fields[3]),
                close:  _safeFloat(fields[4]),
                volume: fields.length > 5 ? (parseInt(fields[5]) || 0) : 0
            });
        }
        return results;
    },

    // ── History ──────────────────────────────────────────────────────────

    // /q/d/l/?s=SYMBOL&i=INTERVAL → Date,Open,High,Low,Close[,Volume]
    buildHistoryUrl: function(symbol, interval) {
        var intervalParam = this.intervalMap[interval] || "d";
        var url = "https://stooq.com/q/d/l/?s="
            + encodeURIComponent(symbol) + "&i=" + intervalParam;
        return _appendApiKey(url);
    },

    // Returns: DataPoint[]
    parseHistoryResponse: function(responseText) {
        var lines = responseText.trim().split("\n");
        var results = [];
        for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
            var line = lines[lineIndex].trim();
            if (!line) continue;
            var fields = line.split(",");
            if (fields.length < 5) continue;

            var open = _safeFloat(fields[1]);
            if (isNaN(open)) continue;           // skip header row

            results.push({
                date:   fields[0],
                time:   "",
                open:   open,
                high:   _safeFloat(fields[2]),
                low:    _safeFloat(fields[3]),
                close:  _safeFloat(fields[4]),
                volume: fields.length > 5 ? (parseInt(fields[5]) || 0) : 0
            });
        }
        return results;
    },

    // ── Navigation ───────────────────────────────────────────────────────

    // Returns: string — browser URL for the symbol's detail page
    buildSymbolPageUrl: function(symbolId) {
        return "https://stooq.com/q/?s=" + encodeURIComponent(symbolId);
    }
});
