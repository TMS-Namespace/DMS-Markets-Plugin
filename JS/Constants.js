// Constants.js — JS-side constants for the Markets plugin
//
// Only values consumed by JS logic live here (fetching, parsing, timing).
// UI constants (sizes, colors, strings) live in QML/Constants.qml.
//
// Usage in QML:  import "../JS/Constants.js" as JsK
// Usage in JS:   .import "Constants.js" as Constants

.pragma library

// ── Generic time units ───────────────────────────────────────────────────────
var SECOND_MS = 1000
var MINUTE_MS = 60 * SECOND_MS
var HOUR_MS   = 60 * MINUTE_MS
var DAY_MS    = 24 * HOUR_MS
var WEEK_MS   = 7 * DAY_MS
var MONTH_MS  = 30 * DAY_MS

// ── Fetch timing (milliseconds) ───────────────────────────────────────────────
var POLL_INTERVAL_MS         = 30 * SECOND_MS // main polling timer
var RETRY_INTERVAL_MS        = 3 * SECOND_MS  // base retry delay (× attempt number)
var RETRY_SUBSEQUENT_MS      = 2 * SECOND_MS  // delay between consecutive retry-queue items
var FULL_GRAPH_REFRESH_MS    = DAY_MS         // force a full history re-download
var INITIAL_GRAPH_DELAY_MS   = 300            // delay before the first staggered graph fetch
var INITIAL_GRAPH_STAGGER_MS = 500            // gap between consecutive staggered graph fetches
var SYMBOL_WATCH_DELAY_MS    = 500            // debounce window for onSymbolsChanged

// ── Fetch limits ──────────────────────────────────────────────────────────────
var MAX_RETRIES            = 3
var MAX_CONCURRENT_FETCHES = 1          // keep curl bursts off the UI path
var FETCH_QUEUE_PUMP_MS    = 50

// ── Shell fetch command constants ────────────────────────────────────────────
var FETCH_SHELL_COMMAND = ["bash", "-o", "pipefail", "-c"]
var FETCH_USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64)"
var CURL_CONNECT_TIMEOUT_SECONDS = 10
var CURL_MAX_TIME_SECONDS = 20
var PROCESS_NICE_LEVEL = 19
var PROCESS_IONICE_CLASS = 3

// ── Provider credential obfuscation ───────────────────────────────────────────
var CREDENTIAL_OBF_SEED = "https://github.com/TMS-Namespace/DMS-Markets-Plugin"

// ── General numeric constants ────────────────────────────────────────────────
var PERCENT_MULTIPLIER = 100
var INVERT_ROUNDING_FACTOR = 100
var SECONDS_PER_MINUTE = 60
var MINUTES_PER_HOUR = 60
var HOURS_PER_DAY = 24
var SECONDS_PER_DAY = 86400
var HEX_BYTE_WIDTH = 2

// ── Price interval timing ────────────────────────────────────────────────────
var DEFAULT_PRICE_INTERVAL = "1h"
var DEFAULT_PRICE_INTERVAL_MS = HOUR_MS
var PRICE_INTERVAL_MS = {
    "1m":  MINUTE_MS,
    "5m":  5 * MINUTE_MS,
    "15m": 15 * MINUTE_MS,
    "1h":  HOUR_MS,
    "1d":  DAY_MS,
    "1w":  WEEK_MS,
    "1M":  MONTH_MS
}

// ── Chart ranges ─────────────────────────────────────────────────────────────
var DEFAULT_CHART_RANGE = "1M"
var CHART_RANGES = {
    "1W":  { interval: "1d", maxPoints: 7,    refreshMs: HOUR_MS      },
    "1M":  { interval: "1d", maxPoints: 30,   refreshMs: 4 * HOUR_MS  },
    "3M":  { interval: "1d", maxPoints: 65,   refreshMs: DAY_MS       },
    "6M":  { interval: "1d", maxPoints: 130,  refreshMs: DAY_MS       },
    "1Y":  { interval: "1d", maxPoints: 260,  refreshMs: DAY_MS       },
    "2Y":  { interval: "1w", maxPoints: 104,  refreshMs: WEEK_MS      },
    "5Y":  { interval: "1w", maxPoints: 260,  refreshMs: WEEK_MS      },
    "10Y": { interval: "1M", maxPoints: 120,  refreshMs: WEEK_MS      }
}
var LEGACY_CHART_RANGE_MAP = {
    "15m": "1W",
    "1h":  "1W",
    "1d":  "1M",
    "1w":  "3M"
}
var CHART_RANGE_LABELS = {
    "1W": "1 Week",
    "1M": "1 Month",
    "3M": "3 Months",
    "6M": "6 Months",
    "1Y": "1 Year",
    "2Y": "2 Years",
    "5Y": "5 Years",
    "10Y": "10 Years"
}
var INTERVAL_LABELS = {
    "5m":  "5 min",
    "15m": "15 min",
    "1h":  "1 hour",
    "1d":  "1 day",
    "1w":  "1 week",
    "1M":  "1 month"
}

// ── Stooq provider constants ────────────────────────────────────────────────
var STOOQ_PROVIDER_ID = "stooq"
var STOOQ_NAME = "Stooq"
var STOOQ_CREDENTIAL_SETTING_KEY = "providerCredential_stooq"
var STOOQ_CREDENTIAL_LABEL = "Stooq API Key"
var STOOQ_CREDENTIAL_PLACEHOLDER = "Paste your Stooq API key here"
var STOOQ_CREDENTIAL_MIN_LENGTH = 25
var STOOQ_CREDENTIAL_MAX_LENGTH = 40
var STOOQ_CREDENTIAL_HELP_TITLE = "Stooq API key availability"
var STOOQ_CREDENTIAL_HELP_TEXT = "Stooq's previous API-key request page currently returns an empty page. Existing valid keys can still be pasted here, but new key generation is not currently available through the old flow."
var STOOQ_DISABLED_MESSAGE = "Stooq is currently disabled because its API has become unstable and repeatedly broke data fetching. It may be re-enabled if the API becomes reliable again.\n\nPlease delete any existing Stooq symbols and re-add them using another provider. Symbol names can differ between providers."
var STOOQ_SYMBOL_SEARCH_URL = "https://stooq.com"
var STOOQ_SYMBOL_HELP_TEXT = "Provider-specific symbol from Stooq"
var STOOQ_SYMBOL_PLACEHOLDER = "eurusd"
var STOOQ_SETTINGS_TEXT = "Required only for symbols that use the Stooq provider."
var STOOQ_AUTH_ERROR_MESSAGE = "Stooq API key missing or invalid"
var STOOQ_CREDENTIAL_ERROR_SENTINEL = "get your apikey"
var STOOQ_DATA_URL = "https://stooq.com/q/d/l/"
var STOOQ_SYMBOL_PAGE_URL = "https://stooq.com/q/"
var STOOQ_VERIFY_URL = "https://stooq.com/__verify"
var STOOQ_COOKIE_FILE = "dms-markets-stooq.cookies"
var STOOQ_BROWSER_CHALLENGE_TEXT = "This site requires JavaScript to verify your browser"
var STOOQ_ERROR_FILENAME_HEADER = "filename=error.txt"
var STOOQ_INTERVAL_MAP = {
    "5m":  "5",
    "15m": "15",
    "1h":  "h",
    "1d":  "d",
    "1w":  "w",
    "1M":  "m"
}

// ── Yahoo provider constants ────────────────────────────────────────────────
var YAHOO_PROVIDER_ID = "yahoo"
var YAHOO_NAME = "Yahoo Finance"
var YAHOO_CHART_BASE_URL = "https://query1.finance.yahoo.com/v8/finance/chart/"
var YAHOO_LOOKUP_URL = "https://finance.yahoo.com/lookup"
var YAHOO_QUOTE_BASE_URL = "https://finance.yahoo.com/quote/"
var YAHOO_SYMBOL_HELP_TEXT = "Provider-specific Yahoo Finance symbol, e.g. EURUSD=X, BZ=F, HG=F, DX-Y.NYB, ^GSPC"
var YAHOO_SYMBOL_PLACEHOLDER = "EURUSD=X"
var YAHOO_SETTINGS_TEXT = "No credential is required. Use Yahoo Finance symbols such as EURUSD=X, BZ=F, HG=F, DX-Y.NYB, or ^GSPC."
var YAHOO_EVENTS_PARAM = "history"
var YAHOO_INCLUDE_PRE_POST = "false"
var YAHOO_INTERVAL_MAP = {
    "1m":  "1m",
    "5m":  "5m",
    "15m": "15m",
    "1h":  "1h",
    "1d":  "1d",
    "1w":  "1wk",
    "1M":  "1mo"
}
var YAHOO_PRICE_RANGE_BY_INTERVAL = {
    "1m":  "1d",
    "5m":  "5d",
    "15m": "5d",
    "1h":  "5d",
    "1w":  "6mo",
    "1mo": "2y"
}
var YAHOO_DEFAULT_PRICE_RANGE = "1mo"
var YAHOO_RANGE_ONE_MONTH = "1mo"
var YAHOO_RANGE_SIX_MONTHS = "6mo"
var YAHOO_RANGE_ONE_YEAR = "1y"
var YAHOO_RANGE_TWO_YEARS = "2y"
var YAHOO_RANGE_FIVE_YEARS = "5y"
var YAHOO_RANGE_TEN_YEARS = "10y"
var YAHOO_DEFAULT_HISTORY_POINTS = 30
var YAHOO_WEEKLY_SHORT_POINTS = 104
var YAHOO_DAILY_ONE_MONTH_POINTS = 30
var YAHOO_DAILY_SIX_MONTH_POINTS = 65
var YAHOO_DAILY_ONE_YEAR_POINTS = 130
