// StooqProvider.js — Stooq market data provider
//
// Stooq (https://stooq.com) publishes free CSV quotes for a wide range of
// instruments: forex, indices, commodities, crypto, equities.
//
// Endpoints:
//   Latest candle (no header):   GET /q/l/?s=<symbol>&i=<interval>
//   Historical data (header):    GET /q/d/l/?s=<symbol>&i=<interval>
//   Symbol search / autocomplete: GET /cmp/?q=<query>
//   Symbol page:                  https://stooq.com/q/?s=<symbol>
//
// Common symbols:
//   dx.f    USDX (Dollar Index)       eurusd  EUR/USD
//   gbpusd  GBP/USD                   usdjpy  USD/JPY
//   gc.f    Gold futures              si.f    Silver futures
//   cl.f    Crude Oil futures          btcusd  Bitcoin/USD
//   ^spx    S&P 500                   ^dji    Dow Jones
//   ^ndq    Nasdaq 100                ^ftse   FTSE 100

.import "ProviderInterface.js" as PI

// ─── Helpers ─────────────────────────────────────────────────────────────────

function _safeFloat(s) {
    if (!s || s === "N/D" || s === "null" || s === "NaN") return NaN;
    return parseFloat(s);
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

    // /q/l/?s=SYMBOL&i=INTERVAL → Symbol,Date,Time,Open,High,Low,Close[,Volume]
    buildPriceUrl: function(symbol, interval) {
        var i = this.intervalMap[interval] || "h";
        return "https://stooq.com/q/l/?s="
            + encodeURIComponent(symbol) + "&i=" + i;
    },

    // Returns: DataPoint[]
    parsePriceResponse: function(responseText) {
        var lines = responseText.trim().split("\n");
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

    // ── History ──────────────────────────────────────────────────────────

    // /q/d/l/?s=SYMBOL&i=INTERVAL → Date,Open,High,Low,Close[,Volume]
    buildHistoryUrl: function(symbol, interval) {
        var i = this.intervalMap[interval] || "d";
        return "https://stooq.com/q/d/l/?s="
            + encodeURIComponent(symbol) + "&i=" + i;
    },

    // Returns: DataPoint[]
    parseHistoryResponse: function(responseText) {
        var lines = responseText.trim().split("\n");
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
    },

    // ── Search ───────────────────────────────────────────────────────────

    // /cmp/?q=QUERY → window.cmp_r('ID~Name~Market~Price~Change%~...|...')
    buildSearchUrl: function(query) {
        return "https://stooq.com/cmp/?q=" + encodeURIComponent(query);
    },

    // Returns: SearchResult[]
    parseSearchResponse: function(responseText) {
        var text  = responseText || "";
        var start = text.indexOf("'");
        var end   = text.lastIndexOf("'");
        if (start < 0 || end <= start) return [];

        var inner = text.substring(start + 1, end);
        inner = inner.replace(/<b>/g, "").replace(/<\/b>/g, "");

        var entries = inner.split("|");
        var results = [];
        for (var i = 0; i < entries.length; i++) {
            var parts = entries[i].split("~");
            if (parts.length >= 5) {
                results.push({
                    id:        parts[0].toLowerCase(),
                    name:      parts[1],
                    market:    parts[2],
                    price:     parts[3],
                    changeStr: parts[4]
                });
            }
        }
        return results;
    },

    // ── Validation ───────────────────────────────────────────────────────

    // Uses the price endpoint with daily interval to check whether a symbol
    // returns valid data (not "N/D").
    buildValidationUrl: function(ticker) {
        return "https://stooq.com/q/l/?s="
            + encodeURIComponent(ticker) + "&i=d";
    },

    // Returns: ValidationResult { valid: bool, message: string }
    parseValidationResponse: function(responseText) {
        if (!responseText || !responseText.trim()) {
            return { valid: false, message: "Empty response" };
        }
        var line   = responseText.trim().split("\n")[0];
        var fields = line.split(",");
        if (fields.length >= 7 && fields[6] !== "N/D" && !isNaN(parseFloat(fields[6]))) {
            return { valid: true, message: "" };
        }
        return { valid: false, message: "Symbol not found" };
    },

    // ── Navigation ───────────────────────────────────────────────────────

    // Returns: string — browser URL for the symbol's detail page
    buildSymbolPageUrl: function(symbolId) {
        return "https://stooq.com/q/?s=" + encodeURIComponent(symbolId);
    }
});
