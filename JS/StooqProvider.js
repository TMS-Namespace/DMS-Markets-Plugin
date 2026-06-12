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
.import "Constants.js" as Constants

// ─── Helpers ─────────────────────────────────────────────────────────────────

function _safeFloat(rawValue) {
    if (!rawValue || rawValue === "N/D" || rawValue === "null" || rawValue === "NaN") return NaN;
    return parseFloat(rawValue);
}

function _appendCredential(url) {
    var credential = PI.getCredential(Constants.STOOQ_PROVIDER_ID);
    if (credential) url += "&apikey=" + encodeURIComponent(credential);
    return url;
}

function _buildVerifiedFetchCommand(url, tailLines) {
    var cmd = "";
    cmd += "set -e\n";
    cmd += "if command -v ionice >/dev/null 2>&1; then ionice -c" + Constants.PROCESS_IONICE_CLASS + " -p $$ >/dev/null 2>&1 || true; fi\n";
    cmd += "if command -v renice >/dev/null 2>&1; then renice -n " + Constants.PROCESS_NICE_LEVEL + " -p $$ >/dev/null 2>&1 || true; fi\n";
    cmd += "cookie=\"${XDG_CACHE_HOME:-$HOME/.cache}/" + Constants.STOOQ_COOKIE_FILE + "\"\n";
    cmd += "mkdir -p \"$(dirname \"$cookie\")\"\n";
    cmd += "tmp=\"$(mktemp)\"\n";
    cmd += "hdr=\"$(mktemp)\"\n";
    cmd += "cleanup() { rm -f \"$tmp\" \"$hdr\"; }\n";
    cmd += "trap cleanup EXIT\n";
    cmd += "url='" + url + "'\n";
    cmd += "fetch() {\n";
    cmd += "  curl -fsSL --connect-timeout " + Constants.CURL_CONNECT_TIMEOUT_SECONDS;
    cmd += " --max-time " + Constants.CURL_MAX_TIME_SECONDS;
    cmd += " -D \"$hdr\"";
    cmd += " -b \"$cookie\" -c \"$cookie\"";
    cmd += " -H 'User-Agent: " + Constants.FETCH_USER_AGENT + "'";
    cmd += " \"$url\" -o \"$tmp\"\n";
    cmd += "}\n";
    cmd += "fetch\n";
    cmd += "if grep -q '" + Constants.STOOQ_BROWSER_CHALLENGE_TEXT + "' \"$tmp\"; then\n";
    cmd += "  challenge=$(sed -n 's/.*const c=\"\\([^\"]*\\)\",d=\\([0-9][0-9]*\\).*/\\1 \\2/p' \"$tmp\" | head -n 1)\n";
    cmd += "  if [ -z \"$challenge\" ]; then cat \"$tmp\"; exit 0; fi\n";
    cmd += "  cval=${challenge% *}\n";
    cmd += "  dval=${challenge##* }\n";
    cmd += "  n=$(node -e 'const crypto=require(\"crypto\"); const c=process.argv[1], d=Number(process.argv[2]); const target=\"0\".repeat(d); for (let n=0;;n++) { if (crypto.createHash(\"sha256\").update(c+n).digest(\"hex\").startsWith(target)) { console.log(n); break; } }' \"$cval\" \"$dval\")\n";
    cmd += "  curl -fsSL --connect-timeout " + Constants.CURL_CONNECT_TIMEOUT_SECONDS;
    cmd += " --max-time " + Constants.CURL_MAX_TIME_SECONDS;
    cmd += " -b \"$cookie\" -c \"$cookie\"";
    cmd += " -X POST -H 'Content-Type: application/x-www-form-urlencoded'";
    cmd += " --data-urlencode \"c=$cval\" --data-urlencode \"n=$n\"";
    cmd += " '" + Constants.STOOQ_VERIFY_URL + "' >/dev/null\n";
    cmd += "  fetch\n";
    cmd += "fi\n";
    cmd += "if grep -qi '" + Constants.STOOQ_ERROR_FILENAME_HEADER + "' \"$hdr\"; then echo '" + Constants.STOOQ_CREDENTIAL_ERROR_SENTINEL + "'; exit 0; fi\n";
    if (tailLines > 0)
        cmd += "tail -n " + tailLines + " \"$tmp\"\n";
    else
        cmd += "cat \"$tmp\"\n";
    return cmd;
}

// ─── Provider Registration ───────────────────────────────────────────────────

PI.registerProvider(Constants.STOOQ_PROVIDER_ID, {
    name: Constants.STOOQ_NAME,
    disabled: true,
    disabledMessage: Constants.STOOQ_DISABLED_MESSAGE,
    requiresCredential: true,
    credentialSettingKey: Constants.STOOQ_CREDENTIAL_SETTING_KEY,
    credentialLabel: Constants.STOOQ_CREDENTIAL_LABEL,
    credentialPlaceholder: Constants.STOOQ_CREDENTIAL_PLACEHOLDER,
    credentialMinLength: Constants.STOOQ_CREDENTIAL_MIN_LENGTH,
    credentialMaxLength: Constants.STOOQ_CREDENTIAL_MAX_LENGTH,
    credentialHelpTitle: Constants.STOOQ_CREDENTIAL_HELP_TITLE,
    credentialHelpText: Constants.STOOQ_CREDENTIAL_HELP_TEXT,
    symbolSearchUrl: Constants.STOOQ_SYMBOL_SEARCH_URL,
    symbolHelpText: Constants.STOOQ_SYMBOL_HELP_TEXT,
    symbolPlaceholder: Constants.STOOQ_SYMBOL_PLACEHOLDER,
    providerSettingsText: Constants.STOOQ_SETTINGS_TEXT,
    authErrorMessage: Constants.STOOQ_AUTH_ERROR_MESSAGE,
    credentialErrorSentinel: Constants.STOOQ_CREDENTIAL_ERROR_SENTINEL,
    tailHistory: true,
    buildFetchCommand: _buildVerifiedFetchCommand,

    intervalMap: Constants.STOOQ_INTERVAL_MAP,

    // ── Price ────────────────────────────────────────────────────────────

    // /q/d/l/?s=SYMBOL&i=INTERVAL → Date,Open,High,Low,Close[,Volume]
    buildPriceUrl: function(symbol, interval) {
        // Stooq's former latest-candle endpoint (/q/l/) now returns 404.
        // The downloadable CSV endpoint currently serves daily/weekly/monthly
        // data with an API key, so intraday selections fall back to daily.
        var intervalParam = (interval === "1w" || interval === "1M")
            ? this.intervalMap[interval]
            : "d";
        var url = Constants.STOOQ_DATA_URL + "?s="
            + encodeURIComponent(symbol) + "&i=" + intervalParam;
        return _appendCredential(url);
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
        var url = Constants.STOOQ_DATA_URL + "?s="
            + encodeURIComponent(symbol) + "&i=" + intervalParam;
        return _appendCredential(url);
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
        return Constants.STOOQ_SYMBOL_PAGE_URL + "?s=" + encodeURIComponent(symbolId);
    }
});
