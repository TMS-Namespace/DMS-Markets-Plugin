// ProviderInterface.js — Market Data Provider Abstraction Layer
//
// This file defines the provider registry and public API. All provider-specific
// logic (URL building, response parsing) lives in separate provider files
// (e.g. StooqProvider.js) that register themselves into this singleton.
//
// ─── Provider Contract ───────────────────────────────────────────────────────
//
// Each provider must implement this interface:
//
// {
//     name:                    string,
//
//     // Supported candle intervals — maps internal keys to provider params
//     intervalMap:             { "5m": "...", "1h": "...", "1d": "...", ... },
//
//     // Optional provider metadata
//     requiresCredential:      bool,
//     credentialSettingKey:    string,
//     credentialLabel:         string,
//     credentialPlaceholder:   string,
//     credentialMinLength:     number,
//     credentialMaxLength:     number,
//     symbolSearchUrl:         string,
//     symbolHelpText:          string,
//     symbolPlaceholder:       string,
//     authErrorMessage:        string,
//
//     // Optional provider-specific command builder. Providers that do not need
//     // custom cookies/challenges can omit this and use the default curl command.
//     buildFetchCommand:       function(url: string, tailLines: number) → string,
//
//     // ── Price ──────────────────────────────────────────────────────────
//     // Build URL for latest-candle price data
//     buildPriceUrl:           function(symbol: string, interval: string) → string,
//     //
//     // Parse response → DataPoint[]
//     parsePriceResponse:      function(responseText: string) → DataPoint[],
//
//     // ── History ────────────────────────────────────────────────────────
//     // Build URL for historical candle data (sparkline)
//     buildHistoryUrl:         function(symbol: string, interval: string, maxPoints?: number) → string,
//     //
//     // Parse response → DataPoint[]
//     parseHistoryResponse:    function(responseText: string) → DataPoint[],
//
//     // ── Navigation ─────────────────────────────────────────────────────
//     // Build a browser-friendly URL for the symbol page
//     buildSymbolPageUrl:      function(symbolId: string) → string
// }
//
// ─── Return Type Contracts ───────────────────────────────────────────────────
//
// DataPoint: {
//     date:   string,       // e.g. "2026-02-16"
//     time:   string,       // e.g. "14:30:00" or ""
//     open:   number,
//     high:   number,
//     low:    number,
//     close:  number,
//     volume: number        // 0 if unavailable
// }
//
.pragma library
.import "Constants.js" as Constants

// ─── Registry ────────────────────────────────────────────────────────────────

var _providers = {};
var _defaultProviderId = "";
var _credentials = {};

// ─── Fetch Command Helpers ───────────────────────────────────────────────────

function _buildPlainFetchCommand(url, tailLines) {
    var cmd = "";
    cmd += "set -e\n";
    cmd += "if command -v ionice >/dev/null 2>&1; then ionice -c" + Constants.PROCESS_IONICE_CLASS + " -p $$ >/dev/null 2>&1 || true; fi\n";
    cmd += "if command -v renice >/dev/null 2>&1; then renice -n " + Constants.PROCESS_NICE_LEVEL + " -p $$ >/dev/null 2>&1 || true; fi\n";
    cmd += "tmp=\"$(mktemp)\"\n";
    cmd += "cleanup() { rm -f \"$tmp\"; }\n";
    cmd += "trap cleanup EXIT\n";
    cmd += "url='" + url + "'\n";
    cmd += "curl -fsSL --connect-timeout " + Constants.CURL_CONNECT_TIMEOUT_SECONDS
    cmd += " --max-time " + Constants.CURL_MAX_TIME_SECONDS;
    cmd += " -H 'User-Agent: " + Constants.FETCH_USER_AGENT + "'";
    cmd += " \"$url\" -o \"$tmp\"\n";
    if (tailLines > 0)
        cmd += "tail -n " + tailLines + " \"$tmp\"\n";
    else
        cmd += "cat \"$tmp\"\n";
    return cmd;
}

function _buildRequestCommand(provider, url, tailLines) {
    var commandText = provider.buildFetchCommand
        ? provider.buildFetchCommand(url, tailLines)
        : _buildPlainFetchCommand(url, tailLines);
    return Constants.FETCH_SHELL_COMMAND.concat([commandText]);
}

// ─── Credential Management ───────────────────────────────────────────────────

function setCredential(providerId, credential) {
    _credentials[providerId] = credential || "";
}

function getCredential(providerId) {
    return _credentials[providerId] || "";
}

// Returns true when a response indicates a missing or invalid provider credential.
function isCredentialError(providerId, responseText) {
    var provider = _providers[providerId];
    if (!provider || !responseText) return false;
    var sentinel = provider.credentialErrorSentinel || "";
    return !!(sentinel && responseText.trim().toLowerCase().startsWith(sentinel.toLowerCase()))
}

function registerProvider(id, provider) {
    _providers[id] = provider;
    // First registered provider becomes the default
    if (!_defaultProviderId) _defaultProviderId = id;
}

function getProvider(id) {
    return _providers[id] || null;
}

function getProviderIds() {
    return Object.keys(_providers);
}

function getProviderName(id) {
    var provider = _providers[id];
    return provider ? provider.name : id;
}

function getProviderMeta(id) {
    var provider = _providers[id];
    if (!provider) return ({})
    return {
        id:                   id,
        name:                 provider.name || id,
        disabled:             !!provider.disabled,
        disabledMessage:      provider.disabledMessage || "",
        requiresCredential:   !!provider.requiresCredential,
        credentialSettingKey: provider.credentialSettingKey || (id + "Credential"),
        credentialLabel:      provider.credentialLabel || (provider.name || id) + " Credential",
        credentialPlaceholder: provider.credentialPlaceholder || "",
        credentialMinLength:  provider.credentialMinLength || 0,
        credentialMaxLength:  provider.credentialMaxLength || 0,
        credentialHelpTitle:  provider.credentialHelpTitle || "",
        credentialHelpText:   provider.credentialHelpText || "",
        symbolSearchUrl:      provider.symbolSearchUrl || "",
        symbolHelpText:       provider.symbolHelpText || "Provider-specific symbol",
        symbolPlaceholder:    provider.symbolPlaceholder || "",
        providerSettingsText: provider.providerSettingsText || "",
        authErrorMessage:     provider.authErrorMessage || "Provider credential missing or invalid"
    }
}

function providerRequiresCredential(providerId) {
    var provider = _providers[providerId];
    return !!(provider && provider.requiresCredential);
}

function providerIsDisabled(providerId) {
    var provider = _providers[providerId];
    return !!(provider && provider.disabled);
}

function isValidCredential(providerId, credential) {
    var provider = _providers[providerId];
    if (provider && provider.disabled) return false;
    if (!provider || !provider.requiresCredential) return true;
    var value = (credential || "").trim();
    var minLength = provider.credentialMinLength || 1;
    var maxLength = provider.credentialMaxLength || 0;
    if (value.length < minLength) return false;
    if (maxLength > 0 && value.length > maxLength) return false;
    return true;
}

function hasRequiredCredential(providerId) {
    return isValidCredential(providerId, getCredential(providerId));
}

// Returns the ID of the default provider (first registered)
function getDefaultProviderId() {
    return _defaultProviderId;
}

// Returns an array of { label: string, value: string } for use in SelectionSetting
function getProviderOptions() {
    var options = [];
    var providerIds = Object.keys(_providers);
    for (var index = 0; index < providerIds.length; index++) {
        options.push({ label: _providers[providerIds[index]].name, value: providerIds[index] });
    }
    return options;
}

function getSupportedIntervals(providerId) {
    var provider = _providers[providerId];
    if (!provider) return [];
    return Object.keys(provider.intervalMap);
}

// ─── Price ───────────────────────────────────────────────────────────────────

function buildPriceUrl(symbol, providerId, interval) {
    var provider = _providers[providerId];
    if (!provider) return "";
    return provider.buildPriceUrl(symbol, interval);
}

function getPriceRequest(symbol, providerId, interval) {
    var provider = _providers[providerId];
    if (!provider) return ({})
    var url = provider.buildPriceUrl(symbol, interval);
    return {
        url: url,
        tailLines: 0,
        command: _buildRequestCommand(provider, url, 0)
    }
}

function parsePriceResponse(providerId, responseText) {
    var provider = _providers[providerId];
    if (!provider) return [];
    return provider.parsePriceResponse(responseText);
}

// ─── History ─────────────────────────────────────────────────────────────────

function buildHistoryUrl(symbol, providerId, interval, maxPoints) {
    var provider = _providers[providerId];
    if (!provider) return "";
    return provider.buildHistoryUrl(symbol, interval, maxPoints);
}

function getHistoryRequest(symbol, providerId, interval, maxPoints) {
    var provider = _providers[providerId];
    if (!provider) return ({})
    var url = provider.buildHistoryUrl(symbol, interval, maxPoints);
    var tailLines = provider.tailHistory ? ((maxPoints || 0) + 2) : 0;
    return {
        url: url,
        tailLines: tailLines,
        command: _buildRequestCommand(provider, url, tailLines)
    }
}

function parseHistoryResponse(providerId, responseText) {
    var provider = _providers[providerId];
    if (!provider) return [];
    return provider.parseHistoryResponse(responseText);
}

// ─── Navigation ──────────────────────────────────────────────────────────────

function buildSymbolPageUrl(providerId, symbolId) {
    var provider = _providers[providerId];
    if (!provider) return "";
    return provider.buildSymbolPageUrl(symbolId);
}

// ─── Interval Helpers ────────────────────────────────────────────────────────

function getIntervalLabel(interval) {
    return Constants.INTERVAL_LABELS[interval] || interval;
}

// ─── Chart Range Helpers ─────────────────────────────────────────────────────
// Chart range controls how much historical data the sparkline shows.
// Each range maps to a candle interval, max data points, and refresh interval.

function getPriceInterval(range) {
    return range || Constants.DEFAULT_PRICE_INTERVAL;
}

function normalizeChartRange(value) {
    if (Constants.CHART_RANGES[value]) return value;
    return Constants.LEGACY_CHART_RANGE_MAP[value] || Constants.DEFAULT_CHART_RANGE;
}

function getHistoryConfig(chartRange) {
    var range = normalizeChartRange(chartRange);
    return Constants.CHART_RANGES[range];
}

function getChartRangeLabel(range) {
    return Constants.CHART_RANGE_LABELS[normalizeChartRange(range)] || range;
}
