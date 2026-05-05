// Helpers.js — Pure utility functions shared across QML components
//
// Usage:  import "../JS/Helpers.js" as Helpers
//         Helpers.formatNumber(1234.5)

.pragma library
.import "Constants.js" as JsK

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
    var map = {
        "1m":  60000,
        "5m":  300000,
        "15m": 900000,
        "1h":  3600000,
        "1d":  86400000,
        "1w":  604800000,
        "1M":  2592000000
    }
    return map[interval] || 3600000
}

// ── Boolean from pluginData (defaults to true when unset) ───────────────────
// pluginData values can be: undefined, "", true, "true", false, "false"
function pluginDataBool(value) {
    return value === undefined || value === "" || value === true || value === "true"
}

// ── Human-readable "time ago" text ──────────────────────────────────────────
function timeAgo(epochMs) {
    if (!epochMs || epochMs <= 0) return ""
    var seconds = Math.floor((Date.now() - epochMs) / 1000)
    if (seconds < 60)   return seconds + " sec. ago"
    var minutes = Math.floor(seconds / 60)
    if (minutes < 60)   return minutes + " min. ago"
    var hours  = Math.floor(minutes / 60)
    if (hours < 24)    return hours + " hr. ago"
    var days = Math.floor(hours / 24)
    return days + " day" + (days !== 1 ? "s" : "") + " ago"
}

// ── Price inversion (1/x) ───────────────────────────────────────────────────
function inv(value) {
    if (value === 0 || isNaN(value)) return 0
    return Math.round(100 / value) / 100   // 1/value rounded to 2 decimals
}

function isInverted(symbols, symbolId) {
    for (var symbolIndex = 0; symbolIndex < symbols.length; symbolIndex++)
        if (symbols[symbolIndex].id === symbolId) return !!symbols[symbolIndex].invert
    return false
}

// ── API key obfuscation (XOR + hex) ─────────────────────────────────────────
// Not cryptographic — just prevents the key from sitting as plain text on disk.
// Uses hex instead of base64 to avoid btoa/atob (browser-only Web APIs).
function obfuscate(text) {
    if (!text) return ""
    var key = JsK.API_KEY_OBF_SEED
    var out = ""
    for (var i = 0; i < text.length; i++) {
        var xored = text.charCodeAt(i) ^ key.charCodeAt(i % key.length)
        out += ("0" + xored.toString(16)).slice(-2)
    }
    return out
}

function deobfuscate(encoded) {
    if (!encoded) return ""
    // Hex-encoded XOR format: even-length string of hex digits
    if (/^[0-9a-fA-F]+$/.test(encoded) && encoded.length % 2 === 0) {
        try {
            var key = JsK.API_KEY_OBF_SEED
            var out = ""
            for (var i = 0; i < encoded.length; i += 2)
                out += String.fromCharCode(parseInt(encoded.substring(i, i + 2), 16) ^ key.charCodeAt((i / 2) % key.length))
            return out
        } catch (e) {
            console.warn("[Markets/Helpers] deobfuscate failed:", e)
        }
    }
    // Fallback: treat as a legacy plain-text value and return as-is
    return encoded
}

// ── API key validation ────────────────────────────────────────────────────────
// Single source of truth for what constitutes a valid (plaintext) API key.
function isValidApiKey(key) {
    var k = (key || "").trim()
    return k.length >= JsK.API_KEY_MIN_LENGTH && k.length <= JsK.API_KEY_MAX_LENGTH
}
