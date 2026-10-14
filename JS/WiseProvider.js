// WiseProvider.js — Wise currency-exchange-rate provider
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
// Only `resolution=hourly|daily` is supported; `unit` ∈ day|month|year with
// length caps (day≤30, month≤60, year≤5). Spans wider than ~5 years 400.

.pragma library
.import "ProviderInterface.js" as PI
.import "Constants.js" as Constants

// ── Symbol parsing ───────────────────────────────────────────────────────────
// Accepts "BRLPLN", "BRL-PLN", "brl/pln", … and yields { source, target }.
function _parsePair(symbol) {
    var text = (symbol || "").toString().toUpperCase().replace(/[^A-Z]/g, "")
    if (text.length !== 6) return null
    return { source: text.slice(0, 3), target: text.slice(3, 6) }
}

// ── Timestamp → { date, time } (UTC) ─────────────────────────────────────────
function _isoParts(epochMs) {
    var d = new Date(epochMs)
    function pad(n) { return (n < 10 ? "0" : "") + n }
    return {
        date: d.getUTCFullYear() + "-" + pad(d.getUTCMonth() + 1) + "-" + pad(d.getUTCDate()),
        time: pad(d.getUTCHours()) + ":" + pad(d.getUTCMinutes()) + ":" + pad(d.getUTCSeconds())
    }
}

// ── Raw response → [{ time, value }] ascending ───────────────────────────────
function _parseRaw(responseText) {
    var parsed
    try { parsed = JSON.parse(responseText) } catch (e) { return [] }
    if (!parsed) return []
    // /rates/live returns a single object; /rates/history a list.
    var arr = Array.isArray(parsed) ? parsed : (parsed.value !== undefined ? [parsed] : [])
    var points = []
    for (var i = 0; i < arr.length; i++) {
        var p = arr[i]
        if (!p || p.value === undefined || p.value === null || isNaN(p.value)) continue
        points.push({ time: p.time, value: p.value })
    }
    points.sort(function(a, b) { return a.time - b.time })
    return points
}

// ── Downsample to one value per bucket of `bucketDays` ───────────────────────
// Keeps the last (most recent) value in each bucket.
function _downsample(points, bucketDays) {
    if (bucketDays <= 1 || points.length === 0) return points
    var bucketMs = bucketDays * Constants.WISE_MS_PER_DAY
    var out = []
    var lastBucket = null
    for (var i = 0; i < points.length; i++) {
        var bucket = Math.floor(points[i].time / bucketMs)
        if (bucket === lastBucket) out[out.length - 1] = points[i]
        else { out.push(points[i]); lastBucket = bucket }
    }
    return out
}

// ── [{ time, value }] → DataPoint[] with synthesized candles ─────────────────
// Wise gives one value per timestamp, so a candle's `open` is the previous
// value; the widget's change (close − open) is therefore the step-to-step move.
function _toCandles(points) {
    var candles = []
    var prev = null
    for (var i = 0; i < points.length; i++) {
        var value = points[i].value
        var open = (prev === null) ? value : prev
        var iso = _isoParts(points[i].time)
        candles.push({
            date: iso.date, time: iso.time,
            open: open, high: Math.max(open, value), low: Math.min(open, value),
            close: value, volume: 0
        })
        prev = value
    }
    return candles
}

function _parseResponse(responseText) {
    return _toCandles(_parseRaw(responseText))
}

// ── Request parameter selection ──────────────────────────────────────────────
// Price: freshest point plus enough history for a meaningful daily/hourly move.
function _priceParams(interval) {
    if (interval === "1d" || interval === "1w" || interval === "1M")
        return { resolution: "daily", unit: "day", length: 7 }
    return { resolution: "hourly", unit: "day", length: 2 }
}

// History: pick the finest API window that covers the requested span, then
// downsample to the chart interval in parseHistoryResponse.
function _historyParams(interval, maxPoints) {
    var points       = maxPoints || Constants.WISE_DEFAULT_HISTORY_POINTS
    var daysPerPoint = interval === "1w" ? 7 : (interval === "1M" ? 30 : 1)
    var spanDays     = Math.min(points * daysPerPoint, Constants.WISE_MAX_HISTORY_DAYS)
    if (spanDays <= Constants.WISE_DAILY_UNIT_MAX_LENGTH)
        return { resolution: "daily", unit: "day", length: Math.max(2, spanDays) }
    return {
        resolution: "daily",
        unit: "month",
        length: Math.min(Constants.WISE_MONTH_UNIT_MAX_LENGTH, Math.ceil(spanDays / 30))
    }
}

function _bucketDaysFor(interval) {
    if (interval === "1w") return 7
    if (interval === "1M") return 30
    return 1
}

function _url(base, pair, params) {
    return base + "?source=" + pair.source + "&target=" + pair.target
        + "&length=" + params.length
        + "&resolution=" + params.resolution
        + "&unit=" + params.unit
}

// ── Provider registration ────────────────────────────────────────────────────
PI.registerProvider(Constants.WISE_PROVIDER_ID, {
    name: Constants.WISE_NAME,
    requiresCredential: false,
    symbolSearchUrl: Constants.WISE_SYMBOL_SEARCH_URL,
    symbolHelpText: Constants.WISE_SYMBOL_HELP_TEXT,
    symbolPlaceholder: Constants.WISE_SYMBOL_PLACEHOLDER,
    providerSettingsText: Constants.WISE_SETTINGS_TEXT,
    intervalMap: Constants.WISE_INTERVAL_MAP,

    buildPriceUrl: function(symbol, interval) {
        var pair = _parsePair(symbol)
        if (!pair) return ""
        return _url(Constants.WISE_HISTORY_LIVE_URL, pair, _priceParams(interval))
    },

    parsePriceResponse: _parseResponse,

    buildHistoryUrl: function(symbol, interval, maxPoints) {
        var pair = _parsePair(symbol)
        if (!pair) return ""
        return _url(Constants.WISE_HISTORY_LIVE_URL, pair, _historyParams(interval, maxPoints))
    },

    // `context.interval` is the chart candle interval ("1d"|"1w"|"1M").
    parseHistoryResponse: function(responseText, context) {
        var points = _parseRaw(responseText)
        var bucketDays = _bucketDaysFor(context && context.interval)
        return _toCandles(_downsample(points, bucketDays))
    },

    buildSymbolPageUrl: function(symbolId) {
        var pair = _parsePair(symbolId)
        if (!pair) return Constants.WISE_CONVERTER_BASE_URL
        return Constants.WISE_CONVERTER_BASE_URL
            + pair.source.toLowerCase() + "-to-" + pair.target.toLowerCase() + "-rate"
    }
})
