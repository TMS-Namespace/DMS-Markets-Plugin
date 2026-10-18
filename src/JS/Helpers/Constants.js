// Constants.js - JS-side constants for the Markets plugin
//
// Only values shared by all providers live here (fetching, parsing, timing);
// provider-specific constants live next to each provider in JS/Providers/<Name>/.
// UI constants (sizes, colors, strings) live in QML/Helpers/Constants.qml.
//
// Usage in QML:  import "../JS/Helpers/Constants.js" as JsConstants
// Usage in JS:   .import "Constants.js" as Constants

.pragma library
.import "../Contracts/TimeUnits.js" as TimeUnits
.import "../Contracts/Resolution.js" as Resolution
.import "../Contracts/ChartSpan.js" as ChartSpan

// ── Generic time units ───────────────────────────────────────────────────────
var SECOND_MS = TimeUnits.SECOND_MS
var MINUTE_MS = TimeUnits.MINUTE_MS
var HOUR_MS = TimeUnits.HOUR_MS
var DAY_MS = TimeUnits.DAY_MS
var WEEK_MS = TimeUnits.WEEK_MS
var MONTH_MS = TimeUnits.MONTH_MS

// ── Fetch timing (milliseconds) ───────────────────────────────────────────────
var POLL_INTERVAL_MS         = 30 * SECOND_MS // main polling timer
var RETRY_INTERVAL_MS        = 3 * SECOND_MS  // base retry delay (× attempt number)
var RETRY_SUBSEQUENT_MS      = 2 * SECOND_MS  // delay between consecutive retry-queue items
var INITIAL_GRAPH_DELAY_MS   = 300            // delay before the first staggered graph fetch
var INITIAL_GRAPH_STAGGER_MS = 500            // gap between consecutive staggered graph fetches
var SYMBOL_WATCH_DELAY_MS    = 500            // debounce window for onSymbolsChanged

// ── Error handling ───────────────────────────────────────────────────────────
var ERROR_NOTIFY_COOLDOWN_MS = 10 * SECOND_MS  // min gap between toasts for the same kind of error
var RECENT_ERRORS_MAX        = 25              // errors kept for diagnostics
var ERROR_BODY_SNIPPET_CHARS = 200             // response text kept in an error's details
var ERROR_USER_MESSAGE_MAX_CHARS = 140         // user-facing messages are short
var STDERR_MAX_CHARS         = 2000            // process stderr kept per fetch
var RETRY_QUEUE_MAX          = 50              // hard cap on queued retries

// ── Storage keys (plugin data) ───────────────────────────────────────────────
// The display name of a symbol (what the bar and popup show): short, and only these characters
// (letters, digits, spaces and & - + * / \ . ~ % $ ^ _ ? ! # ( ) [ ] =).
var DISPLAY_NAME_MAX_LENGTH    = 10
var DISPLAY_NAME_PATTERN       = "^[A-Za-z0-9 &\\-+*/\\\\.~%$^_?!#()\\[\\]=]+$"
var STORAGE_SAVE_ATTEMPTS     = 3               // tries of one write to the plugin data
// Saved market data (MarketCache): one file per symbol, named by the symbol's uid, in the user's cache directory.
var CACHE_DIR_NAME             = "dms-markets-plugin"
var CACHE_FORMAT_VERSION       = 1
var CACHE_ATTEMPTS             = 3               // tries of one file read or write before giving up on that file
var CACHE_RETRY_MS             = 500             // wait between those tries
var CACHE_FLUSH_DELAY_MS       = 1000            // updates of a symbol within this time are written as one file
var CACHE_PROCESS_QUEUE_MAX   = 100             // bounded shell work; excess work follows the normal failure path
var CACHE_MAX_FALLBACKS        = 2               // other file names tried when a symbol's file cannot be written
var STORAGE_SYMBOLS_KEY        = "symbols"
var STORAGE_SYMBOLS_BACKUP_KEY = "symbolsBackup"
// Where the "add / edit symbol" form keeps its draft (one stored value per field), so it survives closing the settings.
var DRAFT_KEYS = Object.freeze({
    ticker: "_addTicker", name: "_addName", provider: "_addProvider",
    priceResolution: "_addPriceResolution", changeResolution: "_addChangeResolution", chartResolution: "_addChartResolution", chartRange: "_addChartRange",
    showChange: "_addShowChange", invert: "_addInvert"
})
var STORAGE_SHOW_PRICE_CHANGE_KEY        = "showPriceChange"
var STORAGE_LEGACY_SHOW_PRICE_RANGE_KEY  = "showPriceRange"   // old name of showPriceChange

// ── Fetch limits ──────────────────────────────────────────────────────────────
var FETCH_QUEUE_MAX        = 100        // reject excess work before allocating a pending call
var MAX_RETRIES            = 3
var MAX_CONCURRENT_FETCHES = 1          // keep curl bursts off the UI path
var FETCH_QUEUE_PUMP_MS    = 50
var RATE_LIMIT_COOLDOWN_MS = 30 * SECOND_MS // HTTP 429 pauses all requests to that provider; repeated attempts wait longer

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
var HEX_BYTE_WIDTH = 2

// ── Chart candle-count validation ────────────────────────────────────────────
// How many candles of the chosen chart resolution fit in the chart range
// (see Helpers/ChartRules.js). Outside the warn bounds the settings show a
// non-blocking note; outside the block bounds the combination is not allowed.
var CHART_CANDLES_BLOCK_MIN = 3     // fewer than this: resolution far too big → blocked
var CHART_CANDLES_WARN_MIN  = 10    // fewer than this: resolution too big → warning
var CHART_CANDLES_WARN_MAX  = 100   // more than this: resolution too small → warning
var CHART_CANDLES_BLOCK_MAX = 200   // more than this: resolution far too small → blocked

// ── Price / chart intervals and spans ───────────────────────────────────────
// Defined centrally in Contracts/Resolution.js and ChartSpan.js.
var DEFAULT_PRICE_RESOLUTION = Resolution.Values.H1
// New symbols: chart candle and range (snapped to what the provider offers).
var DEFAULT_CHANGE_RESOLUTION = Resolution.Values.D1   // the change is measured against the previous day's close
var DEFAULT_CHART_RESOLUTION = Resolution.Values.D1
var DEFAULT_CHART_SPAN = ChartSpan.Values.M1
