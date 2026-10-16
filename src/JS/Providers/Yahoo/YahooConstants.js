// YahooConstants.js - constants used only by the Yahoo provider
//
// Usage in YahooProperties.js and YahooApi.js:  .import "YahooConstants.js" as ProviderConstants

.pragma library
.import "../../Contracts/Resolution.js" as Resolution
// ── Yahoo provider constants ────────────────────────────────────────────────
var YAHOO_PROVIDER_ID = "yahoo"
var YAHOO_ALIAS = "YHF"      // three capital letters: what charts show instead of the long name
var YAHOO_NAME = "Yahoo Finance"
var YAHOO_BASE_URL = "https://finance.yahoo.com"
var YAHOO_DESCRIPTION = "Stocks, indices, commodities, crypto and major currency pairs from Yahoo Finance. No credential required."
var YAHOO_CHART_BASE_URL = "https://query1.finance.yahoo.com/v8/finance/chart/"
var YAHOO_LOOKUP_URL = "https://finance.yahoo.com/lookup"
var YAHOO_QUOTE_BASE_URL = "https://finance.yahoo.com/quote/"
var YAHOO_SYMBOL_HELP_TEXT = "Provider-specific Yahoo Finance symbol, e.g. EURUSD=X, BZ=F, DX-Y.NYB, ^GSPC"
var YAHOO_SYMBOL_PLACEHOLDER = "EURUSD=X"
var YAHOO_SYMBOL_PATTERN = "^[A-Za-z0-9^][A-Za-z0-9.=^_&-]{0,23}$"
var YAHOO_SYMBOL_MIN_LENGTH = 1
var YAHOO_SYMBOL_MAX_LENGTH = 24
var YAHOO_SYMBOL_FORMAT_MESSAGE = "Use a Yahoo Finance symbol: letters, digits and . = ^ _ & - only, e.g. EURUSD=X, BZ=F, ^GSPC."
var YAHOO_EVENTS_PARAM = "history"
var YAHOO_INCLUDE_PRE_POST = "false"
var YAHOO_RESOLUTION_MAP = Resolution.mapOf([
    [Resolution.Values.M1, "1m"],
    [Resolution.Values.M5, "5m"],
    [Resolution.Values.M15, "15m"],
    [Resolution.Values.H1, "1h"],
    [Resolution.Values.D1, "1d"],
    [Resolution.Values.W1, "1wk"],
    [Resolution.Values.MO1, "1mo"]
])
// Yahoo `range=` value used to fetch the latest candles for the price display.
var YAHOO_PRICE_RANGE_BY_RESOLUTION = Resolution.mapOf([
    [Resolution.Values.M1, "1d"],
    [Resolution.Values.M5, "5d"],
    [Resolution.Values.M15, "5d"],
    [Resolution.Values.H1, "5d"],
    [Resolution.Values.D1, "1mo"],
    [Resolution.Values.W1, "6mo"],
    [Resolution.Values.MO1, "2y"]
])
// Yahoo `range=` value for the change reference: wide enough to hold the previous period's candle.
var YAHOO_CHANGE_RANGE_BY_RESOLUTION = Resolution.mapOf([
    [Resolution.Values.H1, "1d"],
    [Resolution.Values.D1, "1d"],
    [Resolution.Values.W1, "1mo"],
    [Resolution.Values.MO1, "6mo"]
])
// Yahoo `range=` strings with the days they cover, ascending. A chart range uses the
// first one that covers it (shorter ranges are trimmed after fetching). Intraday
// limits (measured against the live API): 1m ≤ 8 days, 5m/15m ≤ 60 days, 1h ≤ 730 days.
var YAHOO_RANGES = [
    { days: 1,    range: "1d"  },
    { days: 7,    range: "5d"  },
    { days: 30,   range: "1mo" },
    { days: 91,   range: "3mo" },
    { days: 182,  range: "6mo" },
    { days: 365,  range: "1y"  },
    { days: 730,  range: "2y"  },
    { days: 1826, range: "5y"  },
    { days: 3652, range: "10y" }
]
