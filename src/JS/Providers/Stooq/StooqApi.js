// StooqApi.js - Stooq market data provider
//
// Stooq (https://stooq.com) publishes free CSV quotes for a wide range of
// instruments: forex, indices, commodities, crypto, equities.
//
// Endpoints:
//   Latest candle/history CSV:   GET /q/d/l/?s=<symbol>&i=<resolution>
//   Symbol page:                  https://stooq.com/q/?s=<symbol>
//
// Common CSV symbols:
//   eurusd  EUR/USD                   gbpusd  GBP/USD
//   usdjpy  USD/JPY                   btcusd  Bitcoin/USD
//   ^spx    S&P 500                   ^dji    Dow Jones
//   ^ndq    Nasdaq 100                ^ftse   FTSE 100

.pragma library
.import "../../Helpers/Constants.js" as Constants
.import "../../Contracts/PluginError.js" as PluginError
.import "StooqConstants.js" as ProviderConstants
.import "../../Helpers/SeriesRules.js" as SeriesRules

// ─── Helpers ─────────────────────────────────────────────────────────────────

// Read a CSV price, leaving missing provider values invalid.
function _safeFloat(rawValue) {
    if (!rawValue || rawValue === "N/D" || rawValue === "null" || rawValue === "NaN") return NaN;
    return parseFloat(rawValue);
}

// Append an encoded credential when one is configured.
function _appendCredential(url, credential) {
    if (credential) url += "&apikey=" + encodeURIComponent(credential);
    return url;
}

// Build the Stooq fetch script with bounded browser verification.
function _buildVerifiedFetchCommand(tailLines) {
    var script = "";
    script += "set -e\n";
    script += "if command -v ionice >/dev/null 2>&1; then ionice -c" + Constants.PROCESS_IONICE_CLASS + " -p $$ >/dev/null 2>&1 || true; fi\n";
    script += "if command -v renice >/dev/null 2>&1; then renice -n " + Constants.PROCESS_NICE_LEVEL + " -p $$ >/dev/null 2>&1 || true; fi\n";
    script += "cookie=\"${XDG_CACHE_HOME:-$HOME/.cache}/" + ProviderConstants.STOOQ_COOKIE_FILE + "\"\n";
    script += "mkdir -p \"$(dirname \"$cookie\")\"\n";
    script += "body_file=\"$(mktemp)\"\n";
    script += "header_file=\"$(mktemp)\"\n";
    script += "cleanup() { rm -f \"$body_file\" \"$header_file\"; }\n";
    script += "trap cleanup EXIT\n";
    script += 'url="$1"\n';
    script += "fetch() {\n";
    script += "  curl -fsSL --connect-timeout " + Constants.CURL_CONNECT_TIMEOUT_SECONDS;
    script += " --max-time " + Constants.CURL_MAX_TIME_SECONDS;
    script += " -D \"$header_file\"";
    script += " -b \"$cookie\" -c \"$cookie\"";
    script += " -H 'User-Agent: " + Constants.FETCH_USER_AGENT + "'";
    script += " \"$url\" -o \"$body_file\"\n";
    script += "}\n";
    script += "fetch\n";
    script += "if grep -q '" + ProviderConstants.STOOQ_BROWSER_CHALLENGE_TEXT + "' \"$body_file\"; then\n";
    script += "  challenge=$(sed -n 's/.*const c=\"\\([^\"]*\\)\",d=\\([0-9][0-9]*\\).*/\\1 \\2/p' \"$body_file\" | head -n 1)\n";
    script += "  if [ -z \"$challenge\" ]; then cat \"$body_file\"; exit 0; fi\n";
    script += "  challenge_value=${challenge% *}\n";
    script += "  challenge_difficulty=${challenge##* }\n";
    // Node's stdout is the nonce protocol, not application logging. Refuse excessive challenges and stop on a deadline.
    script += "  nonce=$(node -e 'const crypto=require(\"crypto\"); const challenge=process.argv[1], difficulty=Number(process.argv[2]); if (!Number.isInteger(difficulty) || difficulty < 0 || difficulty > " + ProviderConstants.STOOQ_POW_MAX_DIFFICULTY + ") process.exit(1); const target=\"0\".repeat(difficulty), deadline=Date.now()+" + ProviderConstants.STOOQ_POW_MAX_MS + "; for (let nonce=0; nonce<" + ProviderConstants.STOOQ_POW_MAX_ATTEMPTS + " && Date.now()<deadline; nonce++) { if (crypto.createHash(\"sha256\").update(challenge+nonce).digest(\"hex\").startsWith(target)) { console.log(nonce); process.exit(0); } } process.exit(1);' \"$challenge_value\" \"$challenge_difficulty\")\n";
    script += "  curl -fsSL --connect-timeout " + Constants.CURL_CONNECT_TIMEOUT_SECONDS;
    script += " --max-time " + Constants.CURL_MAX_TIME_SECONDS;
    script += " -b \"$cookie\" -c \"$cookie\"";
    script += " -X POST -H 'Content-Type: application/x-www-form-urlencoded'";
    script += " --data-urlencode \"c=$challenge_value\" --data-urlencode \"n=$nonce\"";
    script += " '" + ProviderConstants.STOOQ_VERIFY_URL + "' >/dev/null\n";
    script += "  fetch\n";
    script += "fi\n";
    script += "if grep -qi '" + ProviderConstants.STOOQ_ERROR_FILENAME_HEADER + "' \"$header_file\"; then echo '" + ProviderConstants.STOOQ_CREDENTIAL_ERROR_SENTINEL + "'; exit 0; fi\n";
    if (tailLines > 0)
        script += "tail -n " + tailLines + " \"$body_file\"\n";
    else
        script += "cat \"$body_file\"\n";
    return script;
}

// One CSV row → DataPoint, or null for a row without usable numbers (Stooq writes "N/D").
function _candle(fields, open) {
    var high = _safeFloat(fields[2]);
    var low = _safeFloat(fields[3]);
    var close = _safeFloat(fields[4]);
    if (isNaN(high) || isNaN(low) || isNaN(close)) return null;
    return SeriesRules.candle({
        date: fields[0], time: "", open: open, high: high, low: low, close: close,
        volume: Math.max(0, fields.length > 5 ? (parseInt(fields[5]) || 0) : 0)
    });
}

// Only the newest `limit` candles are built (limit 0 = all): the lines are walked from the newest backwards.
function _parseCsv(responseText, skipNoData, limit) {
    var lines = responseText.trim().split("\n");
    var results = [];
    for (var lineIndex = lines.length - 1; lineIndex >= 0 && !(limit > 0 && results.length >= limit); lineIndex--) {
        var line = lines[lineIndex].trim();
        if (!line) continue;
        if (skipNoData && line === "No data") continue;
        var fields = line.split(",");
        if (fields.length < 5) continue;
        var open = _safeFloat(fields[1]);
        if (isNaN(open)) continue;           // skip header / invalid rows
        var candle = _candle(fields, open);
        if (candle) results.push(candle);
    }
    return results.reverse();
}

// ── Public API (what the ProviderHandler calls) ──────────────────────────────────

// /q/d/l/?s=SYMBOL&i=INTERVAL → Date,Open,High,Low,Close[,Volume]. Stooq's former latest-candle
// endpoint (/q/l/) now returns 404, so the price uses the same downloadable CSV as the chart.
function _url(symbol, resolution, credential) {
    var resolutionParam = ProviderConstants.STOOQ_RESOLUTION_MAP[resolution];
    if (!resolutionParam) throw new PluginError.PluginError(PluginError.Code.UNSUPPORTED, "Stooq can't serve this chart setting.",
                                                            "Stooq: unsupported resolution '" + resolution + "'");
    return _appendCredential(ProviderConstants.STOOQ_DATA_URL + "?s=" + encodeURIComponent(symbol) + "&i=" + resolutionParam, credential);
}
// Build the provider request for the latest price candles.
function priceUrl(symbol, resolution, credential) { return _url(symbol, resolution, credential); }
// Build the provider request for the selected chart window.
function historyUrl(symbol, resolution, span, credential) { return _url(symbol, resolution, credential); }
// Build the provider request for the previous-period reference close.
function changeUrl(symbol, resolution, credential) { return _url(symbol, resolution, credential); }
// The close of the period before the newest one.
function parseChange(responseText) {
    var candles = _parseCsv(responseText, true, 2);
    if (candles.length < 2) throw new PluginError.PluginError(PluginError.Code.PARSE, "Stooq sent an answer that couldn't be understood.",
                                                              "Stooq: no previous close in the answer");
    return candles[0].close;
}
// Parse the newest requested price candles.
function parsePrice(responseText, limit) { return _parseCsv(responseText, true, limit); }
// Parse the newest requested chart candles.
function parseHistory(responseText, limit) { return _parseCsv(responseText, false, limit); }
// Return the provider-specific fetch script for the requested history limit.
function fetchScript(tailLines) { return _buildVerifiedFetchCommand(tailLines); }
// Build the provider browser page for a validated symbol.
function pageUrl(symbolId) { return ProviderConstants.STOOQ_SYMBOL_PAGE_URL + "?s=" + encodeURIComponent(symbolId); }
