// ChartSpan.js - value domain: how much history a chart shows ("chart range").
//
// The full ladder of ranges. A provider does not list its ranges: it declares the longest
// history it can serve per chart resolution, and the available ranges are every span on this
// ladder within that limit (see the provider properties (JS/Providers/<Name>/<Name>Properties.js)). How often a chart refreshes follows
// its resolution, not its range.
//
//   ChartSpan.Values.M1       "1M"             ChartSpan.label("1M")       "1 Month"
//   ChartSpan.shortLabel("1M")  "1M"  (the compact form: "1 Month" → "1M", "10 Years" → "10Y")
//   ChartSpan.days("1M")      30               ChartSpan.isValid("1M")     true
//   ChartSpan.ORDER           shortest → longest
//   ChartSpan.pointLimit("1d", "1M")  → most candles a chart of that resolution and range holds
//
// A value domain only: no legacy formats here (old saved values are upgraded by SymbolMigration.js).

.pragma library
.import "TimeUnits.js" as TimeUnits
.import "Resolution.js" as Resolution


var Values = Object.freeze({
    H1:  "1H",
    H3:  "3H",
    H6:  "6H",
    H12: "12H",
    D1:  "1D",
    W1:  "1W",
    M1:  "1M",
    M3:  "3M",
    M6:  "6M",
    Y1:  "1Y",
    Y2:  "2Y",
    Y5:  "5Y",
    Y10: "10Y"
})

// Ordered from shortest to longest.
var ORDER = Object.freeze([Values.H1, Values.H3, Values.H6, Values.H12, Values.D1, Values.W1, Values.M1,
                           Values.M3, Values.M6, Values.Y1, Values.Y2, Values.Y5, Values.Y10])

// `days` is the calendar length.
var INFO = Object.freeze({
    "1H":  Object.freeze({ label: "1 Hour",   days: 1 / 24 }),
    "3H":  Object.freeze({ label: "3 Hours",  days: 3 / 24 }),
    "6H":  Object.freeze({ label: "6 Hours",  days: 6 / 24 }),
    "12H": Object.freeze({ label: "12 Hours", days: 12 / 24 }),
    "1D":  Object.freeze({ label: "1 Day",    days: 1 }),
    "1W":  Object.freeze({ label: "1 Week",   days: 7 }),
    "1M":  Object.freeze({ label: "1 Month",  days: 30 }),
    "3M":  Object.freeze({ label: "3 Months", days: 91 }),
    "6M":  Object.freeze({ label: "6 Months", days: 182 }),
    "1Y":  Object.freeze({ label: "1 Year",   days: 365 }),
    "2Y":  Object.freeze({ label: "2 Years",  days: 730 }),
    "5Y":  Object.freeze({ label: "5 Years",  days: 1826 }),
    "10Y": Object.freeze({ label: "10 Years", days: 3652 })
})

// Check whether the value belongs to this module's value domain.
function isValid(span) { return INFO.hasOwnProperty(span) }

// The compact form for tight places (chart corner): "1 Month" → "1M", "10 Years" → "10Y".
var SHORT = Object.freeze({ "1H": "1H", "3H": "3H", "6H": "6H", "12H": "12H", "1D": "1D", "1W": "1W", "1M": "1M", "3M": "3M", "6M": "6M",
                            "1Y": "1Y", "2Y": "2Y", "5Y": "5Y", "10Y": "10Y" })
// Return the short display label for this value.
function shortLabel(span) { return SHORT.hasOwnProperty(span) ? SHORT[span] : (span ? String(span) : "") }

// Return the display label, preserving unknown values as text.
function label(span) { return isValid(span) ? INFO[span].label : (span ? String(span) : "") }
// Return the number of days represented by a chart span.
function days(span)  { return isValid(span) ? INFO[span].days : 0 }

// Upper bound on candles for a (resolution, span) pair, by calendar time.
// Real series are shorter (weekends/closed hours); this is only a trim limit.
function pointLimit(resolution, span) {
    let candleMs = Resolution.ms(resolution)
    if (candleMs <= 0) return 0
    return Math.ceil(days(span) * TimeUnits.DAY_MS / candleMs) + 2
}
