// Resolution.js - value domain: the size of one candle.
//
// Used for the live price (price resolution) and for the chart (chart resolution). A
// provider declares which resolutions it can serve (see the provider properties (JS/Providers/<Name>/<Name>Properties.js)); data is
// refreshed as often as its resolution. The string values are the ones persisted in saved
// symbols, so existing data keeps working.
//
//   Resolution.Values.H1                 "1h"
//   Resolution.label("1h")               "1 Hour"          Resolution.shortLabel("1h")  "1 hour"
//   Resolution.ms("1h")                  3600000           Resolution.isValid("1h")     true
//   Resolution.ORDER                     finest → coarsest

.pragma library
.import "TimeUnits.js" as TimeUnits


var Values = Object.freeze({
    M1:  "1m",
    M5:  "5m",
    M15: "15m",
    H1:  "1h",
    D1:  "1d",
    W1:  "1w",
    MO1: "1M"
})

// Ordered from finest to coarsest.
var ORDER = Object.freeze([Values.M1, Values.M5, Values.M15, Values.H1, Values.D1, Values.W1, Values.MO1])

var INFO = Object.freeze({
    "1m":  Object.freeze({ label: "1 Minute",   shortLabel: "1 min",   ms: TimeUnits.MINUTE_MS      }),
    "5m":  Object.freeze({ label: "5 Minutes",  shortLabel: "5 min",   ms: 5 * TimeUnits.MINUTE_MS  }),
    "15m": Object.freeze({ label: "15 Minutes", shortLabel: "15 min",  ms: 15 * TimeUnits.MINUTE_MS }),
    "1h":  Object.freeze({ label: "1 Hour",     shortLabel: "1 hour",  ms: TimeUnits.HOUR_MS        }),
    "1d":  Object.freeze({ label: "1 Day",      shortLabel: "1 day",   ms: TimeUnits.DAY_MS         }),
    "1w":  Object.freeze({ label: "1 Week",     shortLabel: "1 week",  ms: TimeUnits.WEEK_MS        }),
    "1M":  Object.freeze({ label: "1 Month",    shortLabel: "1 month", ms: TimeUnits.MONTH_MS       })
})

// Check whether the value belongs to this module's value domain.
function isValid(value) { return INFO.hasOwnProperty(value) }

// Unknown values are echoed (and an empty one gives ""), so labels never show "undefined".
function label(resolution)      { return isValid(resolution) ? INFO[resolution].label      : (resolution ? String(resolution) : "") }
// Return the short display label for this value.
function shortLabel(resolution) { return isValid(resolution) ? INFO[resolution].shortLabel : (resolution ? String(resolution) : "") }
// Return the resolution duration in milliseconds, or zero when unknown.
function ms(resolution)         { return isValid(resolution) ? INFO[resolution].ms : 0 }

// Builds a frozen { key: value } object from [[key, value], ...] pairs. Object literals
// can't use enum members as keys in ES5, so resolution-keyed tables use this:
//   Resolution.mapOf([[Resolution.Values.H1, "hourly"], [Resolution.Values.D1, "daily"]])
function mapOf(pairs) {
    var resolutionMap = {}
    for (var i = 0; i < pairs.length; i++) resolutionMap[pairs[i][0]] = pairs[i][1]
    return Object.freeze(resolutionMap)
}
