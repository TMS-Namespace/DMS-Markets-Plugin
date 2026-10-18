// YahooApi.js - Yahoo Finance chart API market data provider
//
// Yahoo symbols are provider-specific and usually differ from Stooq symbols:
//   EURUSD=X   EUR/USD                  BTC-USD  Bitcoin/USD
//   BZ=F       Brent crude futures      HG=F     Copper futures
//   GC=F       Gold futures             DX-Y.NYB U.S. Dollar Index
//   ^GSPC      S&P 500                  ^GDAXI   DAX

.pragma library
.import "../../Helpers/Constants.js" as Constants
.import "YahooConstants.js" as ProviderConstants
.import "../../Contracts/PluginError.js" as PluginError
.import "../../Contracts/ChartSpan.js" as ChartSpan
.import "../../Helpers/SeriesRules.js" as SeriesRules
.import "../../Helpers/PriceRules.js" as PriceRules

// ─── Helpers ─────────────────────────────────────────────────────────────────

// Read an available numeric price and leave missing values invalid.
function _safeNumber(rawValue) {
    if (rawValue === undefined || rawValue === null || rawValue === "null" || rawValue === "NaN")
        return NaN;
    let parsed = parseFloat(rawValue);
    return isNaN(parsed) ? NaN : parsed;
}

// Pad one UTC date or time component to two digits.
function _pad2(value) {
    return value < 10 ? "0" + value : "" + value;
}

// Convert an epoch timestamp to UTC date and time fields.
function _dateParts(epochSeconds) {
    let date = new Date(epochSeconds * Constants.SECOND_MS);
    return {
        date: date.getUTCFullYear() + "-" + _pad2(date.getUTCMonth() + 1) + "-" + _pad2(date.getUTCDate()),
        time: _pad2(date.getUTCHours()) + ":" + _pad2(date.getUTCMinutes()) + ":" + _pad2(date.getUTCSeconds())
    };
}

// Build a typed error for a setting this provider cannot serve.
function _unsupported(detail) {
    return new PluginError.PluginError(PluginError.Code.UNSUPPORTED, "Yahoo Finance can't serve this chart setting.",
                                       "Yahoo Finance: " + detail);
}

// Encode the symbol and chart parameters into the provider URL.
function _chartUrl(symbol, range, resolution) {
    return ProviderConstants.YAHOO_CHART_BASE_URL
        + encodeURIComponent(symbol)
        + "?range=" + encodeURIComponent(range)
        + "&interval=" + encodeURIComponent(resolution)
        + "&includePrePost=" + ProviderConstants.YAHOO_INCLUDE_PRE_POST
        + "&events=" + ProviderConstants.YAHOO_EVENTS_PARAM;
}

// Build a typed error for an unreadable provider response.
function _parseError(detail) {
    return new PluginError.PluginError(PluginError.Code.PARSE, "Yahoo Finance sent an answer that couldn't be understood.",
                                       "Yahoo Finance: " + detail);
}

// The API's own error message, if the body carries one (chart.error.description).
function extractApiError(status, body) {
    let parsed;
    try { parsed = JSON.parse(body); } catch (caughtError) { return ""; }
    let error = parsed && parsed.chart && parsed.chart.error;
    if (!error) return "";
    return String(error.description || error.code || "unknown error");
}

// Throws a PARSE error for anything that is not a Yahoo chart answer; returns [] for a
// valid answer without usable candles (the caller reports that as "no data").
// Only the newest `limit` candles are built (limit 0 = all): the rows are walked from the newest backwards.
function _parseChartResponse(responseText, limit) {
    let parsed;
    try {
        parsed = JSON.parse(responseText);
    } catch (caughtError) {
        throw _parseError("not valid JSON (" + caughtError.message + ")");
    }

    let apiError = extractApiError(200, responseText);
    if (apiError)
        throw new PluginError.PluginError(PluginError.Code.HTTP, "Yahoo Finance: " + apiError, "chart.error: " + apiError);

    let result = parsed && parsed.chart && parsed.chart.result && parsed.chart.result[0];
    if (!result) throw _parseError("no chart result in the answer");
    if (!result.timestamp || !result.indicators || !result.indicators.quote)
        return [];

    let quote = result.indicators.quote[0] || {};
    let timestamps = result.timestamp || [];
    let opens = quote.open || [];
    let highs = quote.high || [];
    let lows = quote.low || [];
    let closes = quote.close || [];
    let volumes = quote.volume || [];
    let results = [];

    for (let index = timestamps.length - 1; index >= 0 && !(limit > 0 && results.length >= limit); index--) {
        let open = _safeNumber(opens[index]);
        let high = _safeNumber(highs[index]);
        let low = _safeNumber(lows[index]);
        let close = _safeNumber(closes[index]);
        if (isNaN(open) || isNaN(high) || isNaN(low) || isNaN(close))
            continue;

        let parts = _dateParts(timestamps[index]);
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

// Select the request window needed for the latest price candles.
function _priceRangeForResolution(resolution) {
    let range = ProviderConstants.YAHOO_PRICE_RANGE_BY_RESOLUTION[resolution];
    if (!range) throw _unsupported("no price range for resolution '" + resolution + "'");
    return range;
}

// Select a window that includes the previous change period.
function _changeRangeForResolution(resolution) {
    let range = ProviderConstants.YAHOO_CHANGE_RANGE_BY_RESOLUTION[resolution];
    if (!range) throw _unsupported("no change range for resolution '" + resolution + "'");
    return range;
}

// The close the change is measured against: the close of the period before the current one.
// Yahoo ends intraday answers with a flat "live" row, which is not a period of its own.
// An answer with a single period carries that previous close in `meta.chartPreviousClose`.
function _parseChangeReference(responseText) {
    let candles = _parseChartResponse(responseText, 0);
    if (candles.length >= 2 && PriceRules.isSnapshot(candles[candles.length - 1])) candles.pop();
    if (candles.length >= 2) return candles[candles.length - 2].close;
    let parsed = JSON.parse(responseText);
    let meta = parsed.chart.result[0].meta || {};
    let reference = _safeNumber(meta.chartPreviousClose);
    if (isNaN(reference)) reference = _safeNumber(meta.previousClose);
    if (isNaN(reference)) throw _parseError("no previous close in the answer");
    return reference;
}

// Select the smallest API window covering the requested chart range.
function _historyRangeForSpan(span) {
    let days = ChartSpan.days(span);
    for (let i = 0; i < ProviderConstants.YAHOO_RANGES.length; i++)
        if (ProviderConstants.YAHOO_RANGES[i].days >= days) return ProviderConstants.YAHOO_RANGES[i].range;
    throw _unsupported("no history range for span '" + span + "'");
}

// Translate an internal resolution into the provider API parameter.
function _resolutionParam(resolution) {
    let param = ProviderConstants.YAHOO_RESOLUTION_MAP[resolution];
    if (!param) throw _unsupported("unsupported resolution '" + resolution + "'");
    return param;
}

// ── Public API (what the ProviderHandler calls) ──────────────────────────────────

// Build the provider request for the latest price candles.
function priceUrl(symbol, resolution) {
    return _chartUrl(symbol, _priceRangeForResolution(resolution), _resolutionParam(resolution));
}
// Build the provider request for the previous-period reference close.
function changeUrl(symbol, resolution) {
    return _chartUrl(symbol, _changeRangeForResolution(resolution), _resolutionParam(resolution));
}
// Read the close used as the price change reference.
function parseChange(responseText) { return _parseChangeReference(responseText); }
// Build the provider request for the selected chart window.
function historyUrl(symbol, resolution, span) {
    return _chartUrl(symbol, _historyRangeForSpan(span), _resolutionParam(resolution));
}
// Parse the newest requested price candles.
function parsePrice(responseText, limit) { return _parseChartResponse(responseText, limit); }
// Parse the newest requested chart candles.
function parseHistory(responseText, limit) { return _parseChartResponse(responseText, limit); }
// Build the provider browser page for a validated symbol.
function pageUrl(symbolId) { return ProviderConstants.YAHOO_QUOTE_BASE_URL + encodeURIComponent(symbolId); }
