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
.import "WiseConstants.js" as K
.import "../../Contracts/PluginError.js" as PluginError
.import "../../Contracts/ChartSpan.js" as ChartSpan
.import "../../Helpers/SeriesRules.js" as SeriesRules

// ── Symbol parsing ───────────────────────────────────────────────────────────
// Accepts "BRLPLN", "BRL-PLN", "brl/pln", … and yields { source, target }.
function parsePair(symbol) {
    var text = (symbol || "").toString().toUpperCase().replace(/[^A-Z]/g, "")
    if (text.length !== 6) return null
    return { source: text.slice(0, 3), target: text.slice(3, 6) }
}

// ── Timestamp → { date, time } (UTC) ─────────────────────────────────────────
function _isoParts(epochMs) {
    var date = new Date(epochMs)
    function pad(number) { return (number < 10 ? "0" : "") + number }
    return {
        date: date.getUTCFullYear() + "-" + pad(date.getUTCMonth() + 1) + "-" + pad(date.getUTCDate()),
        time: pad(date.getUTCHours()) + ":" + pad(date.getUTCMinutes()) + ":" + pad(date.getUTCSeconds())
    }
}

// ── Raw response → [{ time, value }] ascending ───────────────────────────────
// Accepts only real numbers or non-empty numeric strings: Number() alone would turn
// "", [], [5], true and null-ish input into 0/1/5 and silently plot garbage.
function _finiteNumber(raw) {
    if (typeof raw === "number") return isFinite(raw) ? raw : NaN
    if (typeof raw === "string" && raw.trim() !== "") {
        var number = Number(raw)
        return isFinite(number) ? number : NaN
    }
    return NaN
}

function _parseError(detail) {
    return new PluginError.PluginError(PluginError.Code.PARSE, "Wise sent an answer that couldn't be understood.", "Wise: " + detail)
}

function _unsupported(detail) {
    return new PluginError.PluginError(PluginError.Code.UNSUPPORTED, "Wise can't serve this chart setting.", "Wise: " + detail)
}

// The API's own error message, if the body carries one.
function extractApiError(status, body) {
    var parsed
    try { parsed = JSON.parse(body) } catch (e) { return "" }
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed) || parsed.value !== undefined) return ""
    var first = parsed.errors && parsed.errors[0]
    return String(parsed.message || parsed.error || (first && (first.message || first.code)) || "")
}

function _parseRaw(responseText) {
    var parsed
    try { parsed = JSON.parse(responseText) } catch (e) { throw _parseError("not valid JSON (" + e.message + ")") }
    if (!parsed || typeof parsed !== "object") throw _parseError("unexpected answer")
    // /rates/live returns a single object; /rates/history a list.
    if (!Array.isArray(parsed) && parsed.value === undefined) throw _parseError("no rates in the answer")
    var entries = Array.isArray(parsed) ? parsed : [parsed]
    var points = []
    for (var i = 0; i < entries.length; i++) {
        var entry = entries[i]
        if (!entry || typeof entry !== "object") continue
        var value = _finiteNumber(entry.value)
        var time = _finiteNumber(entry.time)
        // Exchange rates and epoch timestamps are positive.
        if (!(value > 0) || !(time > 0)) continue
        points.push({ time: time, value: value })
    }
    points.sort(function(earlier, later) { return earlier.time - later.time })   // numeric, never lexical
    return points
}

// ── [{ time, value }] → DataPoint[] with synthesized candles ─────────────────
// Wise gives one value per timestamp, so a candle's `open` is the previous
// value; the widget's change (close − open) is therefore the step-to-step move.
function _toCandles(points) {
    var candles = []
    var previousValue = null
    for (var i = 0; i < points.length; i++) {
        var value = points[i].value
        var open = (previousValue === null) ? value : previousValue
        var isoParts = _isoParts(points[i].time)
        candles.push(SeriesRules.candle({
            date: isoParts.date, time: isoParts.time,
            open: open, high: Math.max(open, value), low: Math.min(open, value),
            close: value, volume: 0
        }))
        previousValue = value
    }
    return candles
}

// Only the newest `limit` candles are built (limit 0 = all). A candle's open is the previous value, so
// one extra point is read to give the oldest wanted candle its open.
function _parseResponse(responseText, limit) {
    var points = _parseRaw(responseText)
    if (!(limit > 0)) return _toCandles(points)
    return _toCandles(points.slice(-(limit + 1))).slice(-limit)
}

// ── Request parameters ───────────────────────────────────────────────────────
function _apiResolution(resolution) {
    var apiResolution = K.WISE_API_RESOLUTION[resolution]
    if (!apiResolution) throw _unsupported("unsupported resolution '" + resolution + "'")
    return apiResolution
}

// Price: the last two candles at the price resolution (daily or hourly).
function _priceParams(resolution) {
    return { resolution: _apiResolution(resolution), unit: "day", length: 2 }
}

// History: window covering `span`, at the candle size `resolution`.
// Hourly is limited to day units (≤30); daily uses days up to 30, months beyond.
function _historyParams(resolution, span) {
    var apiResolution = _apiResolution(resolution)
    var days = ChartSpan.days(span)
    if (days <= 0) throw _unsupported("unsupported chart range '" + span + "'")
    if (days <= K.WISE_DAY_UNIT_MAX_LENGTH)   // sub-day ranges still need a whole day; the fetcher trims
        return { resolution: apiResolution, unit: "day", length: Math.max(1, Math.ceil(days)) }
    if (apiResolution === "hourly")
        throw _unsupported("hourly data is limited to " + K.WISE_DAY_UNIT_MAX_LENGTH + " days")
    var months = Math.round(days / 30.4375)
    if (months > K.WISE_MONTH_UNIT_MAX_LENGTH)
        throw _unsupported("daily data is limited to " + K.WISE_MONTH_UNIT_MAX_LENGTH + " months")
    return { resolution: apiResolution, unit: "month", length: Math.max(1, months) }
}

function _url(pair, params) {
    return K.WISE_HISTORY_LIVE_URL + "?source=" + pair.source + "&target=" + pair.target
        + "&length=" + params.length
        + "&resolution=" + params.resolution
        + "&unit=" + params.unit
}

function _requirePair(symbol) {
    var pair = parsePair(symbol)
    if (!pair) throw new PluginError.PluginError(PluginError.Code.INVALID_SYMBOL, "Use two 3-letter currency codes, e.g. BRLPLN.",
                                                 "Wise: symbol must be a currency pair like BRLPLN, got '" + String(symbol).slice(0, 40) + "'")
    return pair
}

// ── Public API (what the ProviderHandler calls) ──────────────────────────────────

function priceUrl(symbol, resolution) { return _url(_requirePair(symbol), _priceParams(resolution)) }
function changeUrl(symbol, resolution) { return _url(_requirePair(symbol), _priceParams(resolution)) }
// The value of the period before the newest one.
function parseChange(responseText) {
    var points = _parseRaw(responseText)
    if (points.length < 2) throw _parseError("no previous value in the answer")
    return points[points.length - 2].value
}
function historyUrl(symbol, resolution, span) { return _url(_requirePair(symbol), _historyParams(resolution, span)) }
function parsePrice(responseText, limit) { return _parseResponse(responseText, limit) }
function parseHistory(responseText, limit) { return _parseResponse(responseText, limit) }

function pageUrl(symbolId) {
    var pair = parsePair(symbolId)
    if (!pair) return K.WISE_CONVERTER_BASE_URL
    return K.WISE_CONVERTER_BASE_URL + pair.source.toLowerCase() + "-to-" + pair.target.toLowerCase() + "-rate"
}
