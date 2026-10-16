// ErrorPolicy.js - logic: what to do with an error. ErrorHandler.qml (the QML service) keeps the state
// (dev mode, recent errors, last notification times) and calls these pure functions.
//
//   recordOf(scope, error, context, now)     → plain ErrorRecord fields; users only ever see `userMessage`
//   shouldNotify(lastNotified, record, ms)   → whether a toast may be shown (rate limit per message)
//   notifyKey(record)                        → the key the rate limit is kept under
//   shouldRetry(error, attempt, maxRetries)  → retry only transient failures, and never beyond maxRetries

.pragma library
.import "../Contracts/PluginError.js" as PluginError

function recordOf(scope, error, context, now) {
    var pluginError = PluginError.from(error)
    var details = pluginError.details
    if (context) details = context + (details ? ": " + details : "")
    return {
        error: pluginError,
        fields: { scope: scope || "markets", code: pluginError.code, userMessage: pluginError.userMessage, details: details,
                  retryable: pluginError.retryable === true, status: pluginError.status || 0, time: now }
    }
}

function notifyKey(record) { return record.scope + "|" + record.code + "|" + record.userMessage }

function shouldNotify(lastNotified, record, cooldownMs) {
    var last = lastNotified[notifyKey(record)]
    return last === undefined || record.time - last >= cooldownMs
}

function shouldRetry(error, attempt, maxRetries) {
    return PluginError.isPluginError(error) && error.retryable === true && attempt < maxRetries
}
