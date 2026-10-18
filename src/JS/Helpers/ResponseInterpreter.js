// ResponseInterpreter.js - logic: turns what a fetch process printed into an outcome.
//
// The default fetch script prints one envelope line before the body:
//   MARKETS-RESPONSE <curl exit code> <HTTP status>
// Custom provider scripts (Stooq) may omit it; then only the process exit code is known.
//
//   ResponseInterpreter.fromProcess(providerId, name, { exitCode, stdout, stderr }, hooks)
//       → plain { providerId, ok, status, body, error }
//   `error` is null on success, otherwise a PluginError (friendly userMessage, the web API's own
//   message when it sent one, `retryable` for transient failures).
//
// The result shape is the QML ProviderResponse contract; this module only builds plain data for it.

.pragma library
.import "../Contracts/PluginError.js" as PluginError
.import "Constants.js" as Constants

var ENVELOPE_PREFIX = "MARKETS-RESPONSE"

var ENVELOPE_PATTERN = new RegExp("^" + ENVELOPE_PREFIX + " (\\d+) (\\d*)\\r?$")

// Build the plain fields of a successful provider response.
function success(providerId, status, body) {
    return { providerId: providerId, ok: true, status: status || 200,
             body: body === undefined || body === null ? "" : String(body), error: null }
}

// Build a failed response and normalize its error to PluginError.
function failure(providerId, error, status, body) {
    return { providerId: providerId, ok: false, status: status || (error && error.status) || 0,
             body: body === undefined || body === null ? "" : String(body), error: PluginError.from(error) }
}

// Throws the response's error unless it succeeded.
function assertOk(response) {
    if (!response || typeof response.ok !== "boolean")
        throw PluginError.internal("a provider response is required, got " + typeof response)
    if (!response.ok) throw response.error
    return response
}

// ── Envelope ─────────────────────────────────────────────────────────────────

// Splits stdout into { hasEnvelope, curlExit, status, body }.
function parseEnvelope(stdout) {
    let text = stdout === undefined || stdout === null ? "" : String(stdout)
    let newline = text.indexOf("\n")
    let firstLine = newline === -1 ? text : text.slice(0, newline)
    let match = ENVELOPE_PATTERN.exec(firstLine)
    if (!match) return { hasEnvelope: false, curlExit: 0, status: 0, body: text }
    return {
        hasEnvelope: true,
        curlExit:    parseInt(match[1], 10),
        status:      match[2] === "" ? 0 : parseInt(match[2], 10),
        body:        newline === -1 ? "" : text.slice(newline + 1)
    }
}

// ── Messages ─────────────────────────────────────────────────────────────────

// Collapse whitespace and bound the length of diagnostic text.
function _short(text, maxLength) {
    let clean = String(text).replace(/\s+/g, " ").trim()
    return clean.length > maxLength ? clean.slice(0, maxLength - 1) + "…" : clean
}

// Collect the available process and HTTP failure details.
function _detailsOf(parts) {
    let facts = []
    if (parts.status) facts.push("HTTP " + parts.status)
    if (parts.curlExit) facts.push("curl exit " + parts.curlExit)
    if (parts.processExit) facts.push("process exit " + parts.processExit)
    if (parts.stderr) facts.push("stderr: " + _short(parts.stderr, Constants.ERROR_BODY_SNIPPET_CHARS))
    if (parts.body) facts.push("body: " + _short(parts.body, Constants.ERROR_BODY_SNIPPET_CHARS))
    return facts.join("; ")
}

// Build a typed error with bounded user text and diagnostic details.
function _error(code, message, parts, retryable) {
    return new PluginError.PluginError(code, _short(message, Constants.ERROR_USER_MESSAGE_MAX_CHARS), _detailsOf(parts),
                                       { status: parts.status || 0, retryable: retryable === true })
}

// curl exit codes that mean "the network or the server hiccuped": worth retrying.
var _CURL_NETWORK  = { 5: true, 6: true, 7: true, 52: true, 55: true, 56: true }   // proxy/DNS/connect/empty reply/send/recv
var _CURL_TIMEOUT  = { 28: true }
var _CURL_SSL      = { 35: true, 51: true, 53: true, 54: true, 58: true, 59: true, 60: true, 64: true, 66: true, 77: true, 80: true, 82: true, 83: true, 90: true, 91: true }

// Classify a curl failure and decide whether retrying may help.
function _fromCurlExit(name, parts) {
    let code = parts.curlExit
    if (_CURL_TIMEOUT[code])
        return _error(PluginError.Code.TIMEOUT, name + " took too long to answer.", parts, true)
    if (_CURL_NETWORK[code])
        return _error(PluginError.Code.NETWORK, "Can't reach " + name + ". Check your internet connection.", parts, true)
    if (_CURL_SSL[code])
        return _error(PluginError.Code.NETWORK, "Couldn't make a secure connection to " + name + ".", parts, false)
    if (code === 22)
        return _error(PluginError.Code.HTTP, name + " returned an error.", parts, false)
    return _error(PluginError.Code.NETWORK, "The request to " + name + " failed.", parts, false)
}

// Translate an HTTP failure into a friendly typed error.
function _fromHttpStatus(name, parts, apiMessage) {
    let status = parts.status
    let api = apiMessage ? _short(apiMessage, 100) : ""
    if (status === 429)
        return _error(PluginError.Code.RATE_LIMITED, name + " is limiting requests right now; it will be tried again later.", parts, true)
    if (status >= 500)
        return _error(PluginError.Code.HTTP, name + " is having problems (HTTP " + status + ").", parts, true)
    if (status === 401 || status === 403)
        return _error(PluginError.Code.CREDENTIAL, name + " refused access (HTTP " + status + ").", parts, false)
    if (status === 404)
        return _error(PluginError.Code.NOT_FOUND, api ? name + ": " + api : name + " doesn't know this symbol.", parts, false)
    if (status >= 400)
        return _error(PluginError.Code.HTTP, api ? name + ": " + api : name + " rejected the request (HTTP " + status + ").", parts, false)
    return _error(PluginError.Code.HTTP, name + " answered with HTTP " + status + ".", parts, false)
}

// ── Process result → ProviderResponse ────────────────────────────────────────
//
// result: { exitCode, stdout, stderr }   hooks (all optional):
//   extractApiError(status, body) → string   the web API's own error message, if any
//   credentialSentinel / authErrorMessage    provider-declared "bad API key" marker
// `name` is the provider's display name for messages.
function fromProcess(providerId, name, result, hooks) {
    let options = hooks || {}
    let exitCode = result && typeof result.exitCode === "number" ? result.exitCode : -1
    let stdout = result && result.stdout !== undefined && result.stdout !== null ? String(result.stdout) : ""
    let stderr = result && result.stderr ? String(result.stderr).trim() : ""
    let parts = { stderr: stderr, processExit: exitCode }

    // The wrapper script itself failed (bash/curl missing, killed, …).
    if (exitCode !== 0 && !stdout.length) {
        let cannotRun = exitCode === 127 || exitCode === 126 || exitCode < 0
        return failure(providerId, cannotRun
            ? _error(PluginError.Code.PROCESS, "Couldn't run curl. Make sure curl and bash are installed.", parts, false)
            : _error(PluginError.Code.NETWORK, "The request to " + name + " failed.", parts, false))
    }

    let envelope = parseEnvelope(stdout)
    parts.status   = envelope.status
    parts.curlExit = envelope.curlExit
    let body = envelope.body

    if (envelope.hasEnvelope) {
        if (envelope.curlExit !== 0) return failure(providerId, _fromCurlExit(name, parts), envelope.status, body)
        if (envelope.status !== 0 && (envelope.status < 200 || envelope.status > 299)) {
            let apiMessage = options.extractApiError ? options.extractApiError(envelope.status, body) : ""
            parts.body = body
            return failure(providerId, _fromHttpStatus(name, parts, apiMessage), envelope.status, body)
        }
    } else if (exitCode !== 0) {
        // Custom script (no envelope) that exited non-zero.
        parts.curlExit = exitCode
        return failure(providerId, _fromCurlExit(name, parts), 0, body)
    }

    let status = envelope.status || 200
    if (options.credentialSentinel
            && body.trim().toLowerCase().indexOf(String(options.credentialSentinel).toLowerCase()) === 0)
        return failure(providerId, _error(PluginError.Code.CREDENTIAL,
            options.authErrorMessage || (name + " credential missing or invalid"), parts, false), status, body)

    if (body.trim() === "")
        return failure(providerId, _error(PluginError.Code.NO_DATA, name + " returned an empty answer.", parts, false), status, body)

    // Some APIs report errors inside a successful (2xx) answer.
    let embedded = options.extractApiError ? options.extractApiError(status, body) : ""
    if (embedded) {
        parts.body = body
        return failure(providerId, _error(PluginError.Code.HTTP, name + ": " + _short(embedded, 100), parts, false), status, body)
    }
    return success(providerId, status, body)
}
