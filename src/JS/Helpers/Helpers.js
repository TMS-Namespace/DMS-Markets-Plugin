// Helpers.js - Pure utility functions shared across QML components
//
// Usage:  import "../JS/Helpers/Helpers.js" as Helpers
//         Helpers.formatNumber(1234.5)

.pragma library
.import "Constants.js" as Constants
.import "../Contracts/Resolution.js" as Resolution
// ── Number formatting with thousands separator ──────────────────────────────
function formatNumber(number, decimals) {
    if (isNaN(number)) return "-"
    var fixed = number.toFixed(decimals !== undefined ? decimals : 2)
    var parts = fixed.split(".")
    parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",")
    return parts.join(".")
}

// ── Resolution string → milliseconds (pull frequency of that resolution) ────
function resolutionToMs(resolution) {
    return Resolution.ms(resolution) || Resolution.ms(Constants.DEFAULT_PRICE_RESOLUTION)
}

// ── Copies of maps (QML only notices a `var` property that is assigned a NEW object) ──────────────
function copyOf(map) {
    var copy = {}
    for (var key in map) copy[key] = map[key]
    return copy
}

// A copy of `map` with `key` set / removed; `map` itself is never changed.
function withEntry(map, key, value) {
    var copy = copyOf(map)
    copy[key] = value
    return copy
}

function withoutEntry(map, key) {
    var copy = copyOf(map)
    delete copy[key]
    return copy
}

// ── Unique, internal symbol handle (RFC 4122 version 4 layout) ──────────────
// QML's JS engine has no crypto API, so this is Math.random based: unique enough
// for an internal key, not suitable for secrets. Never shown in the UI.
function generateUuid() {
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function(placeholder) {
        var randomDigit = Math.floor(Math.random() * 16)
        return (placeholder === "x" ? randomDigit : (randomDigit % 4) + 8).toString(16)
    })
}

// A UUID-shaped handle computed from `text` (four FNV-1a hashes with different seeds), the same every time. Used for
// symbols saved by an older version: every part of the plugin that migrates such a list arrives at the same ids,
// so migrating twice (the widget and the settings page both do) can never produce two different handles.
function uuidFrom(text) {
    var words = []
    for (var seed = 0; seed < 4; seed++) {
        var hash = (2166136261 ^ (seed * 16777619)) >>> 0
        for (var i = 0; i < text.length; i++) hash = Math.imul(hash ^ text.charCodeAt(i), 16777619) >>> 0
        words.push(("00000000" + hash.toString(16)).slice(-8))
    }
    var hex = words.join("")
    return hex.slice(0, 8) + "-" + hex.slice(8, 12) + "-4" + hex.slice(13, 16) + "-" + "89ab"[parseInt(hex.charAt(16), 16) % 4] + hex.slice(17, 20) + "-" + hex.slice(20, 32)
}

function isUuid(value) {
    return typeof value === "string"
           && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(value)
}

// ── Boolean coercion for pluginData and persisted symbol flags ──────────────
// Stored values can be: undefined, "", true, "true", false, "false".
function boolValue(value, defaultValue) {
    if (value === undefined || value === null || value === "")
        return defaultValue !== undefined ? defaultValue : false
    return value === true || value === "true" || value === 1 || value === "1"
}

function pluginDataBool(value) {
    return boolValue(value, true)
}

// ── Human-readable "time ago" text ──────────────────────────────────────────
function timeAgo(epochMs) {
    if (!epochMs || epochMs <= 0) return ""
    var seconds = Math.floor((Date.now() - epochMs) / Constants.SECOND_MS)
    if (seconds < Constants.SECONDS_PER_MINUTE)   return seconds + " sec. ago"
    var minutes = Math.floor(seconds / Constants.SECONDS_PER_MINUTE)
    if (minutes < Constants.MINUTES_PER_HOUR)   return minutes + " min. ago"
    var hours  = Math.floor(minutes / Constants.MINUTES_PER_HOUR)
    if (hours < Constants.HOURS_PER_DAY)    return hours + " hr. ago"
    var days = Math.floor(hours / Constants.HOURS_PER_DAY)
    return days + " day" + (days !== 1 ? "s" : "") + " ago"
}

// ── Price inversion (1/x) ───────────────────────────────────────────────────
function inv(value) {
    if (value === 0 || isNaN(value)) return 0
    return Math.round(Constants.INVERT_ROUNDING_FACTOR / value) / Constants.INVERT_ROUNDING_FACTOR
}

function isInverted(symbols, uid) {
    for (var symbolIndex = 0; symbolIndex < symbols.length; symbolIndex++)
        if (symbols[symbolIndex].uid === uid) return boolValue(symbols[symbolIndex].invert, false)
    return false
}

// Identity of the data a configuration requests, shared by live calls and saved market data.
function symbolFetchSignature(symbol, defaultProvider) {
    return [symbol.provider || defaultProvider, symbol.ticker, symbol.priceResolution, symbol.changeResolution,
            symbol.chartResolution, symbol.chartRange, boolValue(symbol.invert, false)].join("|")
}

// ── Provider credential obfuscation (XOR + hex) ─────────────────────────────
// Not cryptographic - just prevents credentials from sitting as plain text on disk.
// Uses hex instead of base64 to avoid btoa/atob (browser-only Web APIs).
function obfuscate(text) {
    if (!text) return ""
    var key = Constants.CREDENTIAL_OBF_SEED
    var hex = ""
    for (var i = 0; i < text.length; i++) {
        var xored = text.charCodeAt(i) ^ key.charCodeAt(i % key.length)
        hex += ("0" + xored.toString(16)).slice(-Constants.HEX_BYTE_WIDTH)
    }
    return hex
}

function deobfuscate(encoded) {
    if (!encoded) return ""
    // Hex-encoded XOR format: even-length string of hex digits
    if (/^[0-9a-fA-F]+$/.test(encoded) && encoded.length % 2 === 0) {
        var key = Constants.CREDENTIAL_OBF_SEED
        var plain = ""
        for (var i = 0; i < encoded.length; i += Constants.HEX_BYTE_WIDTH)
            plain += String.fromCharCode(parseInt(encoded.substring(i, i + Constants.HEX_BYTE_WIDTH), 16) ^ key.charCodeAt((i / Constants.HEX_BYTE_WIDTH) % key.length))
        return plain
    }
    // Fallback: treat as a legacy plain-text value and return as-is
    return encoded
}
