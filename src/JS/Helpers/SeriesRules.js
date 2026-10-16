// SeriesRules.js - logic: building and checking candles.
//
// Every provider turns its wire format (Yahoo JSON, Wise JSON, Stooq CSV, …) into candles through
// `candle`, and the provider handler checks the whole series (`assertSeries`) before anyone else
// sees it. A candle is plain data:
//
//   date    "YYYY-MM-DD"            UTC calendar date (never converted to local time)
//   time    "HH:MM:SS" or ""        UTC time of day; "" for date-only (daily and coarser) data
//   open, high, low, close          finite numbers; high/low always enclose open and close
//   volume                          non-negative integer, 0 when unavailable
//
// The QML DataPoint contract holds exactly these fields; this module is the logic around them.

.pragma library
.import "../Contracts/PluginError.js" as PluginError

var DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/
var TIME_PATTERN = /^(\d{2}:\d{2}:\d{2})?$/

// Build a typed parsing error for a malformed candle.
function _invalid(detail) {
    return new PluginError.PluginError(PluginError.Code.PARSE, "A data provider sent data in an unexpected format.",
                                       "candle: " + detail)
}

// Require a finite numeric candle field.
function _number(fields, key) {
    var value = fields[key]
    if (typeof value !== "number" || !isFinite(value)) throw _invalid(key + " must be a finite number, got " + JSON.stringify(value))
    return value
}

// Validates `fields` and returns a consistent candle (high and low widened to enclose open and close).
function candle(fields) {
    if (!fields || typeof fields !== "object") throw _invalid("fields must be an object")
    var date = fields.date
    var time = fields.time === undefined || fields.time === null ? "" : fields.time
    if (typeof date !== "string" || !DATE_PATTERN.test(date)) throw _invalid("date must be YYYY-MM-DD, got " + JSON.stringify(date))
    if (typeof time !== "string" || !TIME_PATTERN.test(time)) throw _invalid("time must be HH:MM:SS or empty, got " + JSON.stringify(time))
    var open = _number(fields, "open"), high = _number(fields, "high"), low = _number(fields, "low"), close = _number(fields, "close")
    var volume = fields.volume === undefined || fields.volume === null ? 0 : fields.volume
    if (typeof volume !== "number" || !isFinite(volume) || volume < 0 || Math.floor(volume) !== volume)
        throw _invalid("volume must be a non-negative integer, got " + JSON.stringify(volume))
    return { date: date, time: time, open: open, high: Math.max(high, open, close), low: Math.min(low, open, close),
             close: close, volume: volume }
}

// Sort key: candles are ordered by UTC date and time of day.
function sortKey(point) {
    return point.date + " " + (point.time || "00:00:00")
}

// A new candle with open, high, low and close passed through `convert` (e.g. 1/x). It is rebuilt from the
// four mapped values, so when `convert` reverses the order (as 1/x does) high and low still are the extremes.
function transform(point, convert) {
    var open = convert(point.open), high = convert(point.high), low = convert(point.low), close = convert(point.close)
    return candle({
        date: point.date, time: point.time, volume: point.volume,
        open: open, close: close,
        high: Math.max(open, high, low, close), low: Math.min(open, high, low, close)
    })
}

// Throws unless `points` is an array of valid candles in ascending time order.
function assertSeries(points) {
    if (!Array.isArray(points)) throw _invalid("a series must be an array")
    var previous = ""
    for (var i = 0; i < points.length; i++) {
        var point = points[i]
        var checked = candle(point)
        if (checked.high !== point.high || checked.low !== point.low)
            throw _invalid("entry " + i + " has a high/low that does not enclose open and close")
        var key = sortKey(point)
        if (key < previous) throw _invalid("entry " + i + " (" + key + ") is older than the one before (" + previous + ")")
        previous = key
    }
    return points
}
