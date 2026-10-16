// YahooApi.js — Yahoo Finance chart API market data provider
//
// Yahoo symbols are provider-specific and usually differ from Stooq symbols:
//   EURUSD=X   EUR/USD                  BTC-USD  Bitcoin/USD
//   BZ=F       Brent crude futures      HG=F     Copper futures
//   GC=F       Gold futures             DX-Y.NYB U.S. Dollar Index
//   ^GSPC      S&P 500                  ^GDAXI   DAX

.pragma library
.import "../../Helpers/Constants.js" as Constants
.import "YahooConstants.js" as K
.import "../../Contracts/PluginError.js" as PluginError
.import "../../Contracts/ChartSpan.js" as ChartSpan
.import "../../Helpers/SeriesRules.js" as SeriesRules
.import "../../Helpers/PriceRules.js" as PriceRules

// ─── Helpers ─────────────────────────────────────────────────────────────────

function _safeNumber(rawValue) {
    if (rawValue === undefined || rawValue === null || rawValue === "null" || rawValue === "NaN")
        return NaN;
    var parsed = parseFloat(rawValue);
    return isNaN(parsed) ? NaN : parsed;
}

function _pad2(value) {
    return value < 10 ? "0" + value : "" + value;
}

function _dateParts(epochSeconds) {
    var date = new Date(epochSeconds * Constants.SECOND_MS);
    return {
        date: date.getUTCFullYear() + "-" + _pad2(date.getUTCMonth() + 1) + "-" + _pad2(date.getUTCDate()),
        time: _pad2(date.getUTCHours()) + ":" + _pad2(date.getUTCMinutes()) + ":" + _pad2(date.getUTCSeconds())
    };
}

function _unsupported(detail) {
    return new PluginError.PluginError(PluginError.Code.UNSUPPORTED, "Yahoo Finance can't serve this chart setting.",
                                       "Yahoo Finance: " + detail);
}

function _chartUrl(symbol, range, resolution) {
    return K.YAHOO_CHART_BASE_URL
        + encodeURIComponent(symbol)
        + "?range=" + encodeURIComponent(range)
        + "&interval=" + encodeURIComponent(resolution)
        + "&includePrePost=" + K.YAHOO_INCLUDE_PRE_POST
        + "&events=" + K.YAHOO_EVENTS_PARAM;
}

function _parseError(detail) {
    return new PluginError.PluginError(PluginError.Code.PARSE, "Yahoo Finance sent an answer that couldn't be understood.",
                                       "Yahoo Finance: " + detail);
}

// The API's own error message, if the body carries one (chart.error.description).
function extractApiError(status, body) {
    var parsed;
    try { parsed = JSON.parse(body); } catch (e) { return ""; }
    var error = parsed && parsed.chart && parsed.chart.error;
    if (!error) return "";
    return String(error.description || error.code || "unknown error");
}

// Throws a PARSE error for anything that is not a Yahoo chart answer; returns [] for a
// valid answer without usable candles (the caller reports that as "no data").
// Only the newest `limit` candles are built (limit 0 = all): the rows are walked from the newest backwards.
function _parseChartResponse(responseText, limit) {
    var parsed;
    try {
        parsed = JSON.parse(responseText);
    } catch (e) {
        throw _parseError("not valid JSON (" + e.message + ")");
    }

    var apiError = extractApiError(200, responseText);
    if (apiError)
        throw new PluginError.PluginError(PluginError.Code.HTTP, "Yahoo Finance: " + apiError, "chart.error: " + apiError);

    var result = parsed && parsed.chart && parsed.chart.result && parsed.chart.result[0];
    if (!result) throw _parseError("no chart result in the answer");
    if (!result.timestamp || !result.indicators || !result.indicators.quote)
        return [];

    var quote = result.indicators.quote[0] || {};
    var timestamps = result.timestamp || [];
    var opens = quote.open || [];
    var highs = quote.high || [];
    var lows = quote.low || [];
    var closes = quote.close || [];
    var volumes = quote.volume || [];
    var results = [];

    for (var index = timestamps.length - 1; index >= 0 && !(limit > 0 && results.length >= limit); index--) {
        var open = _safeNumber(opens[index]);
        var high = _safeNumber(highs[index]);
        var low = _safeNumber(lows[index]);
        var close = _safeNumber(closes[index]);
        if (isNaN(open) || isNaN(high) || isNaN(low) || isNaN(close))
            continue;

        var parts = _dateParts(timestamps[index]);
        results.push(SeriesRules.candle({
            date: parts.date,
            time: parts.time,
            open: open,
            high: high,
            low: low,
            close: close,
            volume: Math.max(0, parseInt(volumes[index]) || 0)
        }));
    }

    return results.reverse();
}

function _priceRangeForResolution(resolution) {
    var range = K.YAHOO_PRICE_RANGE_BY_RESOLUTION[resolution];
    if (!range) throw _unsupported("no price range for resolution '" + resolution + "'");
    return range;
}

function _changeRangeForResolution(resolution) {
    var range = K.YAHOO_CHANGE_RANGE_BY_RESOLUTION[resolution];
    if (!range) throw _unsupported("no change range for resolution '" + resolution + "'");
    return range;
}

// The close the change is measured against: the close of the period before the current one.
// Yahoo ends intraday answers with a flat "live" row, which is not a period of its own.
// An answer with a single period carries that previous close in `meta.chartPreviousClose`.
function _parseChangeReference(responseText) {
    var candles = _parseChartResponse(responseText, 0);
    if (candles.length >= 2 && PriceRules.isSnapshot(candles[candles.length - 1])) candles.pop();
    if (candles.length >= 2) return candles[candles.length - 2].close;
    var parsed = JSON.parse(responseText);
    var meta = parsed.chart.result[0].meta || {};
    var reference = _safeNumber(meta.chartPreviousClose);
    if (isNaN(reference)) reference = _safeNumber(meta.previousClose);
    if (isNaN(reference)) throw _parseError("no previous close in the answer");
    return reference;
}

function _historyRangeForSpan(span) {
    var days = ChartSpan.days(span);
    for (var i = 0; i < K.YAHOO_RANGES.length; i++)
        if (K.YAHOO_RANGES[i].days >= days) return K.YAHOO_RANGES[i].range;
    throw _unsupported("no history range for span '" + span + "'");
}

function _resolutionParam(resolution) {
    var param = K.YAHOO_RESOLUTION_MAP[resolution];
    if (!param) throw _unsupported("unsupported resolution '" + resolution + "'");
    return param;
}

// ── Public API (what the ProviderHandler calls) ──────────────────────────────────

function priceUrl(symbol, resolution) {
    return _chartUrl(symbol, _priceRangeForResolution(resolution), _resolutionParam(resolution));
}
function changeUrl(symbol, resolution) {
    return _chartUrl(symbol, _changeRangeForResolution(resolution), _resolutionParam(resolution));
}
function parseChange(responseText) { return _parseChangeReference(responseText); }
function historyUrl(symbol, resolution, span) {
    return _chartUrl(symbol, _historyRangeForSpan(span), _resolutionParam(resolution));
}
function parsePrice(responseText, limit) { return _parseChartResponse(responseText, limit); }
function parseHistory(responseText, limit) { return _parseChartResponse(responseText, limit); }
function pageUrl(symbolId) { return K.YAHOO_QUOTE_BASE_URL + encodeURIComponent(symbolId); }
