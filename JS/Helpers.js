// Helpers.js — Pure utility functions shared across QML components
//
// Usage:  import "../JS/Helpers.js" as Helpers
//         Helpers.formatNumber(1234.5)

.pragma library
.import "Constants.js" as Constants

// ── Number formatting with thousands separator ──────────────────────────────
function formatNumber(number, decimals) {
    if (isNaN(number)) return "—"
    var fixed = number.toFixed(decimals !== undefined ? decimals : 2)
    var parts = fixed.split(".")
    parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",")
    return parts.join(".")
}

// ── Interval string → milliseconds ─────────────────────────────────────────
function intervalToMs(interval) {
    return Constants.PRICE_INTERVAL_MS[interval] || Constants.DEFAULT_PRICE_INTERVAL_MS
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

function isInverted(symbols, symbolId) {
    for (var symbolIndex = 0; symbolIndex < symbols.length; symbolIndex++)
        if (symbols[symbolIndex].id === symbolId) return boolValue(symbols[symbolIndex].invert, false)
    return false
}

// ── Provider credential obfuscation (XOR + hex) ─────────────────────────────
// Not cryptographic — just prevents credentials from sitting as plain text on disk.
// Uses hex instead of base64 to avoid btoa/atob (browser-only Web APIs).
function obfuscate(text) {
    if (!text) return ""
    var key = Constants.CREDENTIAL_OBF_SEED
    var out = ""
    for (var i = 0; i < text.length; i++) {
        var xored = text.charCodeAt(i) ^ key.charCodeAt(i % key.length)
        out += ("0" + xored.toString(16)).slice(-Constants.HEX_BYTE_WIDTH)
    }
    return out
}

function deobfuscate(encoded) {
    if (!encoded) return ""
    // Hex-encoded XOR format: even-length string of hex digits
    if (/^[0-9a-fA-F]+$/.test(encoded) && encoded.length % 2 === 0) {
        try {
            var key = Constants.CREDENTIAL_OBF_SEED
            var out = ""
            for (var i = 0; i < encoded.length; i += Constants.HEX_BYTE_WIDTH)
                out += String.fromCharCode(parseInt(encoded.substring(i, i + Constants.HEX_BYTE_WIDTH), 16) ^ key.charCodeAt((i / Constants.HEX_BYTE_WIDTH) % key.length))
            return out
        } catch (e) {
            console.warn("[Markets/Helpers] deobfuscate failed:", e)
        }
    }
    // Fallback: treat as a legacy plain-text value and return as-is
    return encoded
}
