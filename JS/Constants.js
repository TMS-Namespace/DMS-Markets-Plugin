// Constants.js — JS-side constants for the Markets plugin
//
// Only values consumed by JS logic live here (fetching, parsing, timing).
// UI constants (sizes, colors, strings) live in QML/Constants.qml.
//
// Usage in QML:  import "../JS/Constants.js" as JsK
// Usage in JS:   .import "Constants.js" as JsK

.pragma library

// ── Fetch timing (milliseconds) ───────────────────────────────────────────────
var POLL_INTERVAL_MS         = 30000    // main polling timer
var RETRY_INTERVAL_MS        = 3000     // base retry delay (× attempt number)
var RETRY_SUBSEQUENT_MS      = 2000     // delay between consecutive retry-queue items
var FULL_GRAPH_REFRESH_MS    = 86400000 // 24 h — force a full history re-download
var INITIAL_GRAPH_DELAY_MS   = 300      // delay before the first staggered graph fetch
var INITIAL_GRAPH_STAGGER_MS = 500      // gap between consecutive staggered graph fetches
var SYMBOL_WATCH_DELAY_MS    = 500      // debounce window for onSymbolsChanged

// ── Fetch limits ──────────────────────────────────────────────────────────────
var MAX_RETRIES = 3

// ── API key obfuscation ───────────────────────────────────────────────────────
var API_KEY_OBF_SEED         = "https://github.com/TMS-Namespace/DMS-Markets-Plugin"
var API_KEY_MIN_LENGTH       = 25
var API_KEY_MAX_LENGTH       = 40

// ── API error detection ────────────────────────────────────────────────
var API_KEY_ERROR_SENTINEL   = "get your apikey"   // matched case-insensitively
