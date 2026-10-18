// WiseApi.js - Wise currency-exchange-rate provider
//
// Wise (https://wise.com) publishes anonymous FX rates, so arbitrary pairs
// such as BRL→PLN work without requiring an API key.
// Symbols are 6-letter currency pairs: "BRLPLN" = Brazilian Real → Polish
// Złoty. No credentials are required.
//
// API shape (verified):
//   live:          GET /rates/live?source=BRL&target=PLN
//                  → { source, target, value, time(ms) }
//   history:       GET /rates/history?source=BRL&target=PLN&length=N&resolution=daily&unit=day
//                  → [ { source, target, value, time(ms) }, ... ] ascending
//   history+live:  same, with the current live rate appended as the last point
//
// Verified limits (live API): `resolution` is only hourly|daily - there is no
// weekly/monthly. `unit`/`length` only set the WINDOW (e.g. daily + 1 month = 31
// daily points), not the candle size. Daily: unit=day 1-31, month ≤60, year ≤5.
// Hourly: unit=day ≤30 only (month/year → HTTP 400). Wider → HTTP 400.
// The provider declares exactly this in `properties`; anything else throws.

.pragma library
.import "WiseConstants.js" as ProviderConstants
.import "../../Contracts/PluginError.js" as PluginError
.import "../../Contracts/ChartSpan.js" as ChartSpan
.import "../../Helpers/SeriesRules.js" as SeriesRules
// ── Symbol parsing ───────────────────────────────────────────────────────────
// Accepts "BRLPLN", "BRL-PLN", "brl/pln", … and yields { source, target }.
function parsePair(symbol) {
    let text = (symbol || "")
        .toString()
        .toUpperCase()
        .replace(/[^A-Z]/g, "");
    if (text.length !== 6) return null;
    return { source: text.slice(0, 3), target: text.slice(3, 6) };
}

// ── Timestamp → { date, time } (UTC) ─────────────────────────────────────────
function _isoParts(epochMs) {
    let date = new Date(epochMs);
    // Pad a UTC date or time component to two digits.
    function pad(number) {
        return (number < 10 ? "0" : "") + number;
    }
    return {
        date: date.getUTCFullYear() + "-" + pad(date.getUTCMonth() + 1) + "-" + pad(date.getUTCDate()),
        time: pad(date.getUTCHours()) + ":" + pad(date.getUTCMinutes()) + ":" + pad(date.getUTCSeconds())
    };
}

// ── Raw response → [{ time, value }] ascending ───────────────────────────────
// Accepts only real numbers or non-empty numeric strings: Number() alone would turn
// "", [], [5], true and null-ish input into 0/1/5 and silently plot garbage.
function _finiteNumber(raw) {
    if (typeof raw === "number") return isFinite(raw) ? raw : NaN;
    if (typeof raw === "string" && raw.trim() !== "") {
        let number = Number(raw);
        return isFinite(number) ? number : NaN;
    }
    return NaN;
}

// Build a typed error for an unreadable provider response.
function _parseError(detail) {
    return new PluginError.PluginError(
        PluginError.Code.PARSE,
        "Wise sent an answer that couldn't be understood.",
        "Wise: " + detail
    );
}

// Build a typed error for a setting this provider cannot serve.
function _unsupported(detail) {
    return new PluginError.PluginError(
        PluginError.Code.UNSUPPORTED,
        "Wise can't serve this chart setting.",
        "Wise: " + detail
    );
}

// The API's own error message, if the body carries one.
function extractApiError(status, body) {
    let parsed;
    try {
        parsed = JSON.parse(body);
    } catch (caughtError) {
        return "";
    }
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed) || parsed.value !== undefined) return "";
    let first = parsed.errors && parsed.errors[0];
    return String(parsed.message || parsed.error || (first && (first.message || first.code)) || "");
}

// Read valid rates and sort them by UTC timestamp.
function _parseRaw(responseText) {
    let parsed;
    try {
        parsed = JSON.parse(responseText);
    } catch (caughtError) {
        throw _parseError("not valid JSON (" + caughtError.message + ")");
    }
    if (!parsed || typeof parsed !== "object") throw _parseError("unexpected answer");
    // /rates/live returns a single object; /rates/history a list.
    if (!Array.isArray(parsed) && parsed.value === undefined) throw _parseError("no rates in the answer");
    let entries = Array.isArray(parsed) ? parsed : [parsed];
    let points = [];
    for (let i = 0; i < entries.length; i++) {
        let entry = entries[i];
        if (!entry || typeof entry !== "object") continue;
        let value = _finiteNumber(entry.value);
        let time = _finiteNumber(entry.time);
        // Exchange rates and epoch timestamps are positive.
        if (!(value > 0) || !(time > 0)) continue;
        points.push({ time: time, value: value });
    }
    points.sort(function (earlier, later) {
        return earlier.time - later.time;
    }); // numeric, never lexical
    return points;
}

// ── [{ time, value }] → DataPoint[] with synthesized candles ─────────────────
// Wise gives one value per timestamp, so a candle's `open` is the previous
// value; the widget's change (close − open) is therefore the step-to-step move.
function _toCandles(points) {
    let candles = [];
    let previousValue = null;
    for (let i = 0; i < points.length; i++) {
        let value = points[i].value;
        let open = previousValue === null ? value : previousValue;
        let isoParts = _isoParts(points[i].time);
        candles.push(
            SeriesRules.candle({
                date: isoParts.date,
                time: isoParts.time,
                open: open,
                high: Math.max(open, value),
                low: Math.min(open, value),
                close: value,
                volume: 0
            })
        );
        previousValue = value;
    }
    return candles;
}

// Only the newest `limit` candles are built (limit 0 = all). A candle's open is the previous value, so
// one extra point is read to give the oldest wanted candle its open.
function _parseResponse(responseText, limit) {
    let points = _parseRaw(responseText);
    if (!(limit > 0)) return _toCandles(points);
    return _toCandles(points.slice(-(limit + 1))).slice(-limit);
}

// ── Request parameters ───────────────────────────────────────────────────────
function _apiResolution(resolution) {
    let apiResolution = ProviderConstants.WISE_API_RESOLUTION[resolution];
    if (!apiResolution) throw _unsupported("unsupported resolution '" + resolution + "'");
    return apiResolution;
}

// Price: the last two candles at the price resolution (daily or hourly).
function _priceParams(resolution) {
    return { resolution: _apiResolution(resolution), unit: "day", length: 2 };
}

// History: window covering `span`, at the candle size `resolution`.
// Hourly is limited to day units (≤30); daily uses days up to 30, months beyond.
function _historyParams(resolution, span) {
    let apiResolution = _apiResolution(resolution);
    let days = ChartSpan.days(span);
    if (days <= 0) throw _unsupported("unsupported chart range '" + span + "'");
    if (days <= ProviderConstants.WISE_DAY_UNIT_MAX_LENGTH)
        // sub-day ranges still need a whole day; the fetcher trims
        return { resolution: apiResolution, unit: "day", length: Math.max(1, Math.ceil(days)) };
    if (apiResolution === "hourly")
        throw _unsupported("hourly data is limited to " + ProviderConstants.WISE_DAY_UNIT_MAX_LENGTH + " days");
    let months = Math.round(days / 30.4375);
    if (months > ProviderConstants.WISE_MONTH_UNIT_MAX_LENGTH)
        throw _unsupported("daily data is limited to " + ProviderConstants.WISE_MONTH_UNIT_MAX_LENGTH + " months");
    return { resolution: apiResolution, unit: "month", length: Math.max(1, months) };
}

// Build the request URL from validated provider parameters.
function _url(pair, params) {
    return (
        ProviderConstants.WISE_HISTORY_LIVE_URL +
        "?source=" +
        pair.source +
        "&target=" +
        pair.target +
        "&length=" +
        params.length +
        "&resolution=" +
        params.resolution +
        "&unit=" +
        params.unit
    );
}

// Require a currency pair before building a request.
function _requirePair(symbol) {
    let pair = parsePair(symbol);
    if (!pair)
        throw new PluginError.PluginError(
            PluginError.Code.INVALID_SYMBOL,
            "Use two 3-letter currency codes, e.g. BRLPLN.",
            "Wise: symbol must be a currency pair like BRLPLN, got '" + String(symbol).slice(0, 40) + "'"
        );
    return pair;
}

// ── Public API (what the ProviderHandler calls) ──────────────────────────────────

// Build the provider request for the latest price candles.
function priceUrl(symbol, resolution) {
    return _url(_requirePair(symbol), _priceParams(resolution));
}
// Build the provider request for the previous-period reference close.
function changeUrl(symbol, resolution) {
    return _url(_requirePair(symbol), _priceParams(resolution));
}
// The value of the period before the newest one.
function parseChange(responseText) {
    let points = _parseRaw(responseText);
    if (points.length < 2) throw _parseError("no previous value in the answer");
    return points[points.length - 2].value;
}
// Build the provider request for the selected chart window.
function historyUrl(symbol, resolution, span) {
    return _url(_requirePair(symbol), _historyParams(resolution, span));
}
// Parse the newest requested price candles.
function parsePrice(responseText, limit) {
    return _parseResponse(responseText, limit);
}
// Parse the newest requested chart candles.
function parseHistory(responseText, limit) {
    return _parseResponse(responseText, limit);
}

// Build the provider browser page for a validated symbol.
function pageUrl(symbolId) {
    let pair = parsePair(symbolId);
    if (!pair) return ProviderConstants.WISE_CONVERTER_BASE_URL;
    return (
        ProviderConstants.WISE_CONVERTER_BASE_URL +
        pair.source.toLowerCase() +
        "-to-" +
        pair.target.toLowerCase() +
        "-rate"
    );
}
