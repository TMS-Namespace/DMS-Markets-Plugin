// PriceRules.js - logic: what the widget shows for a symbol's live price.
//
// Built from the newest candle (already inverted when the symbol asks for 1/x); the change is measured from the
// candle's open to its close. Returns plain data for the PriceInfo contract.
//
// Some providers end an intraday answer with a "live" row stamped with the current time whose open, high, low and
// close are all the current price (Yahoo does). Taken alone its change would always be 0, so such a snapshot is
// merged into the candle before it: the price is that candle's period seen at the current price.

.pragma library
.import "Constants.js" as Constants

// A candle without any range: a snapshot of the current price rather than a period.
function isSnapshot(candle) {
    return candle.open === candle.high && candle.high === candle.low && candle.low === candle.close
}

// `previous` (optional) is the candle before `latest`. `reference` (optional) is the close the price is compared with
// (the close of the previous period at the symbol's change resolution): when it is known the change is the price minus it,
// otherwise the change is the one over the newest candle.
function priceFrom(latest, previous, reference) {
    var open = latest.open, high = latest.high, low = latest.low
    if (previous && isSnapshot(latest)) {
        open = previous.open
        high = Math.max(previous.high, latest.high)
        low = Math.min(previous.low, latest.low)
    }
    var base = typeof reference === "number" && isFinite(reference) && reference !== 0 ? reference : open
    var change = latest.close - base
    return {
        open: open, high: high, low: low, close: latest.close,
        date: latest.date, time: latest.time,
        change: change,
        changePercent: base !== 0 ? (change / base) * Constants.PERCENT_MULTIPLIER : 0
    }
}
