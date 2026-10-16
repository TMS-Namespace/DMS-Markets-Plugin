// WiseConstants.js - constants used only by the Wise provider
//
// Usage in WiseProperties.js and WiseApi.js:  .import "WiseConstants.js" as ProviderConstants

.pragma library
.import "../../Contracts/Resolution.js" as Resolution
// ── Wise provider constants ─────────────────────────────────────────────────
var WISE_PROVIDER_ID = "wise"
var WISE_ALIAS = "WIS"      // three capital letters: what charts show instead of the long name
var WISE_NAME = "Wise"
var WISE_BASE_URL = "https://wise.com"
var WISE_DESCRIPTION = "Various currency-exchange rates for most world currencies, including exotic pairs. Hourly and daily historical data only. No credential required."
var WISE_HISTORY_LIVE_URL = "https://wise.com/rates/history+live"
var WISE_CONVERTER_BASE_URL = "https://wise.com/gb/currency-converter/"
var WISE_SYMBOL_SEARCH_URL = "https://wise.com/gb/currency-converter/"
var WISE_SYMBOL_HELP_TEXT = "6-letter currency pair (source then target), e.g. BRLPLN, EURUSD, CNYJPY."
var WISE_SYMBOL_PLACEHOLDER = "BRLPLN"
var WISE_SYMBOL_PATTERN = "^[A-Za-z]{3}-?[A-Za-z]{3}$"
var WISE_SYMBOL_MIN_LENGTH = 6
var WISE_SYMBOL_MAX_LENGTH = 7
var WISE_SYMBOL_FORMAT_MESSAGE = "Use two 3-letter currency codes, source then target, e.g. BRLPLN or BRL-PLN."
// Wise only serves hourly and daily candles (no weekly/monthly), so providers
// declare only those. `unit=day` accepts length 1-31 (hourly: 1-30); `unit=month`
// accepts 1-60 (daily only); anything wider returns HTTP 400.
var WISE_API_RESOLUTION = Resolution.mapOf([
    [Resolution.Values.H1, "hourly"],
    [Resolution.Values.D1, "daily"]
])
var WISE_DAY_UNIT_MAX_LENGTH = 30
var WISE_HOURLY_MAX_DAYS = 30      // hourly candles: up to 30 days back
var WISE_DAILY_MAX_DAYS = 1826     // daily candles: up to 60 months (~5 years) back
var WISE_MONTH_UNIT_MAX_LENGTH = 60
