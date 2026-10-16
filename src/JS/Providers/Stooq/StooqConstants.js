// StooqConstants.js - constants used only by the Stooq provider
//
// Usage in StooqProperties.js and StooqApi.js:  .import "StooqConstants.js" as K

.pragma library
.import "../../Contracts/Resolution.js" as Resolution
// ── Stooq provider constants ────────────────────────────────────────────────
var STOOQ_PROVIDER_ID = "stooq"
var STOOQ_ALIAS = "STK"      // three capital letters: what charts show instead of the long name
var STOOQ_NAME = "Stooq"
var STOOQ_BASE_URL = "https://stooq.com"
var STOOQ_DESCRIPTION = "Polish market-data site publishing free CSV quotes for forex, indices, commodities, crypto and equities. Currently disabled because its API is unstable."
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
var STOOQ_SYMBOL_PATTERN = "^[A-Za-z0-9^][A-Za-z0-9._^-]{0,19}$"
var STOOQ_SYMBOL_MIN_LENGTH = 1
var STOOQ_SYMBOL_MAX_LENGTH = 20
var STOOQ_SYMBOL_FORMAT_MESSAGE = "Use a Stooq symbol: letters, digits and . _ ^ - only, e.g. eurusd, ^spx, cl.f."
var STOOQ_AUTH_ERROR_MESSAGE = "Stooq API key missing or invalid"
var STOOQ_CREDENTIAL_ERROR_SENTINEL = "get your apikey"
var STOOQ_DATA_URL = "https://stooq.com/q/d/l/"
var STOOQ_SYMBOL_PAGE_URL = "https://stooq.com/q/"
var STOOQ_VERIFY_URL = "https://stooq.com/__verify"
var STOOQ_COOKIE_FILE = "dms-markets-stooq.cookies"
var STOOQ_BROWSER_CHALLENGE_TEXT = "This site requires JavaScript to verify your browser"
var STOOQ_ERROR_FILENAME_HEADER = "filename=error.txt"
var STOOQ_RESOLUTION_MAP = Resolution.mapOf([
    [Resolution.Values.M5, "5"],
    [Resolution.Values.M15, "15"],
    [Resolution.Values.H1, "h"],
    [Resolution.Values.D1, "d"],
    [Resolution.Values.W1, "w"],
    [Resolution.Values.MO1, "m"]
])
