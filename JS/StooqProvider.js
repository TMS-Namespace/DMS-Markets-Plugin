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

function _safeFloat(rawValue) {
    if (!rawValue || rawValue === "N/D" || rawValue === "null" || rawValue === "NaN") return NaN;
    return parseFloat(rawValue);
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
        var intervalParam = this.intervalMap[interval] || "h";
        return "https://stooq.com/q/l/?s="
            + encodeURIComponent(symbol) + "&i=" + intervalParam;
    },

    // Returns: DataPoint[]
    parsePriceResponse: function(responseText) {
        var lines = responseText.trim().split("\n");
        var results = [];
        for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
            var line = lines[lineIndex].trim();
            if (!line) continue;
            var fields = line.split(",");
            if (fields.length < 7) continue;

            var open = _safeFloat(fields[3]);
            if (isNaN(open)) continue;           // skip header / invalid rows

            results.push({
                symbol: fields[0],
                date:   fields[1],
                time:   fields[2],
                open:   open,
                high:   _safeFloat(fields[4]),
                low:    _safeFloat(fields[5]),
                close:  _safeFloat(fields[6]),
                volume: fields.length > 7 ? (parseInt(fields[7]) || 0) : 0
            });
        }
        return results;
    },

    // ── History ──────────────────────────────────────────────────────────

    // /q/d/l/?s=SYMBOL&i=INTERVAL → Date,Open,High,Low,Close[,Volume]
    buildHistoryUrl: function(symbol, interval) {
        var intervalParam = this.intervalMap[interval] || "d";
        return "https://stooq.com/q/d/l/?s="
            + encodeURIComponent(symbol) + "&i=" + intervalParam;
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

        var innerContent = text.substring(start + 1, end);
        innerContent = innerContent.replace(/<b>/g, "").replace(/<\/b>/g, "");

        var entries = innerContent.split("|");
        var results = [];
        for (var entryIndex = 0; entryIndex < entries.length; entryIndex++) {
            var parts = entries[entryIndex].split("~");
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
        var firstLine = responseText.trim().split("\n")[0];
        var fields    = firstLine.split(",");
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
