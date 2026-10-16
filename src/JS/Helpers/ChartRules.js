// ChartRules.js - validates a chart resolution (candle size) against a chart
// range (time span) by how many candles fit: too few makes the chart a handful
// of blocky points, too many makes it unreadable in a small sparkline.
//
// Thresholds live in Constants.js (CHART_CANDLES_*):
//   candles < BLOCK_MIN  → "block"  (resolution far too big)
//   candles < WARN_MIN   → "warn"   (resolution too big)
//   candles > BLOCK_MAX  → "block"  (resolution far too small)
//   candles > WARN_MAX   → "warn"   (resolution too small)
//   otherwise            → "ok"

.pragma library
.import "Constants.js" as Constants
.import "../Contracts/Resolution.js" as Resolution
.import "../Contracts/ChartSpan.js" as ChartSpan
.import "../Contracts/TimeUnits.js" as TimeUnits

var Level  = Object.freeze({ OK: "ok", WARN: "warn", BLOCK: "block" })
var Reason = Object.freeze({ NONE: "", TOO_BIG: "tooBig", TOO_SMALL: "tooSmall" })

// Calendar candles that fit in the span (providers return fewer for weekends etc.).
function candleCount(resolution, span) {
    var candleMs = Resolution.ms(resolution)
    if (candleMs <= 0) return 0
    return ChartSpan.days(span) * TimeUnits.DAY_MS / candleMs
}

// One decimal at most: "7", "52.1", "720".
function _round(value) { return Number(value.toFixed(1)) }

// Returns plain { level, reason, candles, message }; `message` is "" when the level is ok.
function evaluate(resolution, span) {
    var candles = candleCount(resolution, span)
    var level = Level.OK
    var reason = Reason.NONE
    if (candles < Constants.CHART_CANDLES_BLOCK_MIN)       { level = Level.BLOCK; reason = Reason.TOO_BIG }
    else if (candles > Constants.CHART_CANDLES_BLOCK_MAX)  { level = Level.BLOCK; reason = Reason.TOO_SMALL }
    else if (candles < Constants.CHART_CANDLES_WARN_MIN)   { level = Level.WARN;  reason = Reason.TOO_BIG }
    else if (candles > Constants.CHART_CANDLES_WARN_MAX)   { level = Level.WARN;  reason = Reason.TOO_SMALL }

    var message = ""
    if (level === Level.WARN && reason === Reason.TOO_BIG)
        message = "Note that this resolution is too big for the current chart range (about " + _round(candles)
                  + " candles), prefer a smaller one."
    else if (level === Level.WARN)
        message = "Note that this resolution is too small for the current chart range (about " + _round(candles)
                  + " candles), prefer a bigger one."
    else if (level === Level.BLOCK && reason === Reason.TOO_BIG)
        message = "This resolution is far too big for the chart range (" + _round(candles) + " candles) and cannot be used."
    else if (level === Level.BLOCK)
        message = "This resolution is far too small for the chart range (" + _round(candles) + " candles) and cannot be used."
    return { level: level, reason: reason, candles: candles, message: message }
}

// Check whether the chart candle count is within the hard limits.
function isAllowed(resolution, span) {
    return evaluate(resolution, span).level !== Level.BLOCK
}
