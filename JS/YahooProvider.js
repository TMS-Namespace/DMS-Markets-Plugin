// YahooProvider.js — Yahoo Finance chart API market data provider
//
// Yahoo symbols are provider-specific and usually differ from Stooq symbols:
//   EURUSD=X   EUR/USD                  BTC-USD  Bitcoin/USD
//   BZ=F       Brent crude futures      HG=F     Copper futures
//   GC=F       Gold futures             DX-Y.NYB U.S. Dollar Index
//   ^GSPC      S&P 500                  ^GDAXI   DAX

.import "ProviderInterface.js" as PI
.import "Constants.js" as Constants

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

function _chartUrl(symbol, range, interval) {
    return Constants.YAHOO_CHART_BASE_URL
        + encodeURIComponent(symbol)
        + "?range=" + encodeURIComponent(range)
        + "&interval=" + encodeURIComponent(interval)
        + "&includePrePost=" + Constants.YAHOO_INCLUDE_PRE_POST
        + "&events=" + Constants.YAHOO_EVENTS_PARAM;
}

function _parseChartResponse(responseText) {
    var parsed;
    try {
        parsed = JSON.parse(responseText);
    } catch (e) {
        return [];
    }

    var result = parsed && parsed.chart && parsed.chart.result && parsed.chart.result[0];
    if (!result || !result.timestamp || !result.indicators || !result.indicators.quote)
        return [];

    var quote = result.indicators.quote[0] || {};
    var timestamps = result.timestamp || [];
    var opens = quote.open || [];
    var highs = quote.high || [];
    var lows = quote.low || [];
    var closes = quote.close || [];
    var volumes = quote.volume || [];
    var results = [];

    for (var index = 0; index < timestamps.length; index++) {
        var open = _safeNumber(opens[index]);
        var high = _safeNumber(highs[index]);
        var low = _safeNumber(lows[index]);
        var close = _safeNumber(closes[index]);
        if (isNaN(open) || isNaN(high) || isNaN(low) || isNaN(close))
            continue;

        var parts = _dateParts(timestamps[index]);
        results.push({
            date: parts.date,
            time: parts.time,
            open: open,
            high: high,
            low: low,
            close: close,
            volume: parseInt(volumes[index]) || 0
        });
    }

    return results;
}

function _priceRangeForInterval(interval) {
    return Constants.YAHOO_PRICE_RANGE_BY_INTERVAL[interval] || Constants.YAHOO_DEFAULT_PRICE_RANGE;
}

function _historyRangeFor(interval, maxPoints) {
    if (interval === "1w") {
        if (maxPoints <= Constants.YAHOO_WEEKLY_SHORT_POINTS) return Constants.YAHOO_RANGE_TWO_YEARS;
        return Constants.YAHOO_RANGE_FIVE_YEARS;
    }
    if (interval === Constants.YAHOO_INTERVAL_MAP["1M"]) return Constants.YAHOO_RANGE_TEN_YEARS;
    if (maxPoints <= Constants.YAHOO_DAILY_ONE_MONTH_POINTS) return Constants.YAHOO_RANGE_ONE_MONTH;
    if (maxPoints <= Constants.YAHOO_DAILY_SIX_MONTH_POINTS) return Constants.YAHOO_RANGE_SIX_MONTHS;
    if (maxPoints <= Constants.YAHOO_DAILY_ONE_YEAR_POINTS) return Constants.YAHOO_RANGE_ONE_YEAR;
    return Constants.YAHOO_RANGE_TWO_YEARS;
}

// ─── Provider Registration ───────────────────────────────────────────────────

PI.registerProvider(Constants.YAHOO_PROVIDER_ID, {
    name: Constants.YAHOO_NAME,
    requiresCredential: false,
    symbolSearchUrl: Constants.YAHOO_LOOKUP_URL,
    symbolHelpText: Constants.YAHOO_SYMBOL_HELP_TEXT,
    symbolPlaceholder: Constants.YAHOO_SYMBOL_PLACEHOLDER,
    providerSettingsText: Constants.YAHOO_SETTINGS_TEXT,

    intervalMap: Constants.YAHOO_INTERVAL_MAP,

    // ── Price ────────────────────────────────────────────────────────────

    buildPriceUrl: function(symbol, interval) {
        var intervalParam = this.intervalMap[interval] || "1d";
        return _chartUrl(symbol, _priceRangeForInterval(intervalParam), intervalParam);
    },

    parsePriceResponse: function(responseText) {
        return _parseChartResponse(responseText);
    },

    // ── History ──────────────────────────────────────────────────────────

    buildHistoryUrl: function(symbol, interval, maxPoints) {
        var intervalParam = this.intervalMap[interval] || "1d";
        return _chartUrl(symbol, _historyRangeFor(intervalParam, maxPoints || Constants.YAHOO_DEFAULT_HISTORY_POINTS), intervalParam);
    },

    parseHistoryResponse: function(responseText) {
        return _parseChartResponse(responseText);
    },

    // ── Navigation ───────────────────────────────────────────────────────

    buildSymbolPageUrl: function(symbolId) {
        return Constants.YAHOO_QUOTE_BASE_URL + encodeURIComponent(symbolId);
    }
});
