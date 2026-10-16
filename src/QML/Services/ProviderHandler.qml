// ProviderHandler.qml — one market-data provider, wrapped: the ONLY way the plugin talks to a provider.
//
// ProvidersManager creates one per supported provider (ProviderType) and hands it out; the UI never
// touches a provider's JS. The handler exposes
//   • `type` and `properties`  which provider it is and what it declares (a ProviderProperties)
//   • questions about the provider: validateSymbol, symbolPageUrl, the dropdown options, default and
//     clamped selections, credentials
//   • fetchPrice / fetchChart / fetchChange  build a request through the provider's JS API (after checking that the
//     provider is enabled, has its credential, and was asked for something it can serve), run it, retry
//     transient failures, parse the newest candles needed and report ONE final result through `finished`
//
// It is a stateful service: it owns the provider's request queue (one call at a time), the retry queue,
// the keys in flight and the pending counts, and the provider's credential. It never throws from a
// running call and never leaves a queue slot occupied: a failure of any kind (including an unexpected
// exception) becomes a failed ProviderResponse. Callers decide what to do with the result (store it,
// show the error); this item knows nothing about symbols' storage or charts.
//
// Usage:
//   var handler = ProvidersManager.handlerFor(ProviderType.Wise)
//   handler.fetchPrice(ticker, resolution, context, isCurrent)      → false if that call is already in flight
//   onFinished: (context, response, series) => …   context is the FetchContext you passed, untouched;
//                                         series = the newest candles (null when the response failed)

import QtQuick
import Quickshell
import Quickshell.Io
import "../Contracts"
import "../../JS/Helpers/Constants.js" as JsK
import "../../JS/Helpers/Helpers.js" as Helpers
import "../../JS/Contracts/FetchType.js" as FetchType
import "../../JS/Helpers/FetchCommand.js" as FetchCommand
import "../../JS/Helpers/ResponseInterpreter.js" as ResponseInterpreter
import "../../JS/Helpers/SeriesRules.js" as SeriesRules
import "../../JS/Helpers/SymbolRules.js" as SymbolRules
import "../../JS/Helpers/SelectionPolicy.js" as SelectionPolicy
import "../../JS/Helpers/ProviderRules.js" as ProviderRules
import "../../JS/Helpers/ChartRules.js" as ChartRules
import "../../JS/Contracts/Resolution.js" as Resolution
import "../../JS/Contracts/ChartSpan.js" as ChartSpan
import "../../JS/Contracts/PluginError.js" as PluginError

Item {
    id: root

    // ── Which provider ────────────────────────────────────────────────────────
    property int  type: -1             // ProviderType
    property var  properties: null     // ProviderProperties: what the provider declares (read it freely)
    property var  api: null            // the provider's JS API module; used only inside this handler

    // ── Configuration ─────────────────────────────────────────────────────────
    property int  maxRetries: JsK.MAX_RETRIES

    // ── Outputs ───────────────────────────────────────────────────────────────
    // Number of calls per `group` (the symbol's uid) that are queued, running, or waiting to be retried.
    property var  pending: ({})
    // The final result of one call: `response` is a ProviderResponse (ok or failed).
    signal finished(var context, var response, var series)

    // ── State ─────────────────────────────────────────────────────────────────
    property int  _activeCount: 0
    property var  _queue:       []     // jobs waiting for a slot
    property var  _keys:        ({})   // keys of calls in flight (queued, running or awaiting retry)
    property var  _retryQueue:  []     // jobs waiting for their retry delay

    Component { id: callType;      FetchCall {} }
    Component { id: requestType;   ProviderRequest {} }
    Component { id: selectionType; Selection {} }
    Component { id: statusType;    ChartStatus {} }

    // ── Questions about the provider ──────────────────────────────────────────
    function validateSymbol(symbol) { return SymbolRules.validate(properties, symbol) }

    // Browser page of a symbol; throws INVALID_SYMBOL for a symbol the provider would not accept.
    function symbolPageUrl(symbol) {
        SymbolRules.assertValid(properties, symbol)
        return api.pageUrl(symbol)
    }

    function setCredential(value) { properties.credential = value || "" }
    function isValidCredential(value) { return ProviderRules.isValidCredential(properties, value) }
    function hasRequiredCredential() { return isValidCredential(properties.credential) }

    // Dropdown entries for DMS's SelectionSetting: { label, value }, limited to what the provider serves
    // and ChartRules allows.
    function _options(values, labelOf) { return values.map(function(value) { return { label: labelOf(value), value: value } }) }
    function priceResolutionOptions() { return _options(SelectionPolicy.priceResolutions(properties), Resolution.label) }
    function changeResolutionOptions() { return _options(SelectionPolicy.changeResolutions(properties), Resolution.label) }
    function chartResolutionOptions() { return _options(SelectionPolicy.allowedChartResolutions(properties), Resolution.label) }
    function chartSpanOptions(resolution) { return _options(SelectionPolicy.allowedChartSpans(properties, resolution), ChartSpan.label) }

    function defaultSelection() { return selectionType.createObject(null, SelectionPolicy.defaultSelection(properties)) }

    // The closest selection this provider serves that is also readable (see SelectionPolicy.clamp).
    function clampSelection(selection) {
        var fields = SelectionPolicy.clamp(properties, selection)
        return selectionType.createObject(null, fields)
    }

    // How well a chart resolution fits a chart range (a ChartStatus).
    function chartRangeStatus(resolution, span) { return statusType.createObject(null, ChartRules.evaluate(resolution, span)) }

    // ── Fetching ──────────────────────────────────────────────────────────────
    // `context` is a FetchContext (returned untouched with the result); `isCurrent(context)` is asked
    // before a retry and before reporting, and returns false for calls nobody waits for any more (e.g. the
    // symbol was removed meanwhile). Throws PluginError when the request cannot be made: provider disabled,
    // credential missing, symbol or selection not acceptable for this provider.

    function fetchPrice(symbol, resolution, context, isCurrent) { return _submit(priceRequest(symbol, resolution), context, isCurrent) }
    function fetchChart(symbol, resolution, span, context, isCurrent) { return _submit(chartRequest(symbol, resolution, span), context, isCurrent) }
    function fetchChange(symbol, resolution, context, isCurrent) { return _submit(changeRequest(symbol, resolution), context, isCurrent) }

    // The request for a price / a chart (a ProviderRequest), after every check; `candles` says how many of
    // the newest candles the answer is needed for. Throws PluginError when it cannot be made.
    function priceRequest(symbol, resolution) {
        _assertUsable()
        SymbolRules.assertValid(properties, symbol)
        SelectionPolicy.assertPrice(properties, resolution)
        SelectionPolicy.assertPull(properties, resolution)        // the price is pulled every `resolution`
        // The price is the newest candle, with the one before it (a provider's "live" snapshot row is merged into it).
        return _request(api.priceUrl(symbol, resolution, properties.credential), 0, 2)
    }

    // The change reference (the close of the period before the current one, at `resolution`): what the
    // price is compared with, so the change matches the provider's own quote page.
    function changeRequest(symbol, resolution) {
        _assertUsable()
        SymbolRules.assertValid(properties, symbol)
        SelectionPolicy.assertChange(properties, resolution)
        return _request(api.changeUrl(symbol, resolution, properties.credential), 0, 2)
    }

    function chartRequest(symbol, resolution, span) {
        _assertUsable()
        SymbolRules.assertValid(properties, symbol)
        SelectionPolicy.assertChart(properties, resolution, span)
        SelectionPolicy.assertPull(properties, resolution)        // the chart is pulled every `resolution`
        // A chart needs exactly as many candles as its range holds at its resolution: no more are parsed
        // (or, where the API and fetch script allow it, fetched).
        var candles = ChartSpan.pointLimit(resolution, span)
        return _request(api.historyUrl(symbol, resolution, span, properties.credential),
                        properties.tailHistory ? candles : 0, candles)
    }

    // What a fetch process produced → ProviderResponse (status, body, or a friendly PluginError).
    // `result` has exitCode, stdout, stderr.
    function interpret(result) {
        var response = ResponseInterpreter.fromProcess(properties.providerId, properties.name, result, {
            extractApiError: api.extractApiError,
            credentialSentinel: properties.credentialErrorSentinel,
            authErrorMessage: properties.authErrorMessage
        })
        return responseComponent.createObject(null, response)
    }

    // The newest `limit` candles of a successful response (0 = all): the answer is read by the provider's
    // own parser and checked (valid candles, oldest first). A failed response is rethrown.
    function parsePrice(response, limit) {
        ResponseInterpreter.assertOk(response)
        return SeriesRules.assertSeries(api.parsePrice(response.body, limit))
    }
    // The reference close (a number) of a successful change response.
    function parseChange(response) {
        ResponseInterpreter.assertOk(response)
        var reference = api.parseChange(response.body)
        if (typeof reference !== "number" || !isFinite(reference) || reference === 0)
            throw new PluginError.PluginError(PluginError.Code.PARSE, "The provider sent an answer that couldn't be understood.",
                                              properties.providerId + ": unusable previous close '" + reference + "'")
        return reference
    }
    function parseChart(response, limit) {
        ResponseInterpreter.assertOk(response)
        return SeriesRules.assertSeries(api.parseHistory(response.body, limit))
    }

    function _assertUsable() {
        if (properties.disabled)
            throw new PluginError.PluginError(PluginError.Code.UNSUPPORTED, properties.name + " is currently disabled.",
                                              "provider " + properties.providerId + " is disabled")
        if (!hasRequiredCredential())
            throw new PluginError.PluginError(PluginError.Code.CREDENTIAL, "Add your " + properties.credentialLabel + " in the settings.",
                                              "no valid credential for " + properties.providerId)
    }

    function _request(url, tailLines, candles) {
        return requestType.createObject(null, {
            url: url, tailLines: tailLines, candles: candles,
            command: FetchCommand.build(url, tailLines, api.fetchScript ? api.fetchScript(tailLines) : "")
        })
    }

    // Development log (dev mode only). Never put a URL or key in it: they can carry the credential.
    function _log(text) { Logger.debug("providers", properties.providerId + ": " + text) }
    function _label(request) { return request.context.ticker + " " + request.context.fetchType }

    function _submit(request, context, isCurrent) {
        var call = callType.createObject(null, {
            key: context.uid + "_" + context.fetchType + "_" + request.url + (context.signature ? "|" + context.signature : ""), group: context.uid,
            command: request.command, candles: request.candles, context: context, isCurrent: isCurrent || null
        })
        if (_keys[call.key]) {                                    // this very call is already in flight
            _log("skipped " + _label(call) + ": already in flight")
            return false
        }

        _keys = Helpers.withEntry(_keys, call.key, true)

        _changePending(call.group, 1)
        _enqueue({ request: call, attempt: 0 })
        _log("queued " + _label(call) + " (needs " + call.candles + " candles, " + _queue.length + " waiting)")
        return true
    }

    // The handler outlives the widgets that ask it for data (DMS recreates widgets, e.g. after a reload or
    // wake-up), so a callback may belong to an object that is gone and throw when called. Such a call is not
    // a failed fetch: it stays current and its result is simply reported.
    function _isCurrent(request) {
        if (!request.isCurrent) return true
        try {
            return request.isCurrent(request.context) !== false
        } catch (e) {
            _log("the owner of " + _label(request) + " is gone (" + String(e && e.message) + "): reporting the result anyway")
            return true
        }
    }

    // ── Queue, running, retries ───────────────────────────────────────────────

    function _enqueue(job) {
        var queue = _queue.slice()
        queue.push(job)
        _queue = queue
        pumpTimer.restart()
    }

    // ── Running ───────────────────────────────────────────────────────────────
    Timer {
        id: pumpTimer
        interval: JsK.FETCH_QUEUE_PUMP_MS
        repeat: false
        onTriggered: root._pump()
    }

    function _pump() {
        if (_queue.length === 0) return
        if (_activeCount >= JsK.MAX_CONCURRENT_FETCHES) return

        var queue = _queue.slice()
        var job = queue.shift()
        _queue = queue
        _activeCount = _activeCount + 1
        _log("started " + _label(job.request) + " (attempt " + (job.attempt + 1) + ")")

        var process
        try {
            process = processComponent.createObject(root, { job: job })
            process.command = job.request.command
            process.running = true
        } catch (e) {
            // The process could not even be started: that is a failed call, not a stalled queue.
            _log("could not start the process for " + _label(job.request) + ": " + String(e && e.message))
            _handleFinished(job, -1, "", String(e && e.message))
        }
    }

    Component {
        id: processComponent

        Process {
            property var    job
            property string _buffer: ""
            property string _stderr: ""

            stdout: StdioCollector {
                onStreamFinished: { _buffer = text }
            }

            stderr: SplitParser {
                onRead: line => {
                    if (_stderr.length < JsK.STDERR_MAX_CHARS) _stderr += line + "\n"
                }
            }

            onExited: exitCode => {
                try {
                    root._handleFinished(job, exitCode, _buffer, _stderr)
                } finally {
                    destroy()
                }
            }
        }
    }

    // ── A finished process ────────────────────────────────────────────────────
    // Never throws, always frees the slot, and reports a final result at most once per call
    // (a retry reports nothing yet).
    function _handleFinished(job, exitCode, stdout, stderr) {
        var request = job.request
        var finalResponse = null
        var series = null
        var retrying = false
        var current = true

        try {
            current = _isCurrent(request)
            if (current) {
                var response = interpret({ exitCode: exitCode, stdout: stdout, stderr: stderr })
                if (response.ok) {
                    try {
                        series = _parse(request, response)
                    } catch (e) {
                        response = _failed(e)   // an unreadable answer is final, never retried
                    }
                }
                if (!response.ok && ErrorHandler.shouldRetry(response.error, job.attempt, maxRetries)
                        && _scheduleRetry({ request: request, attempt: job.attempt + 1 })) {
                    _log("retrying " + _label(request) + " (retry " + (job.attempt + 1) + "/" + maxRetries + "): " + response.error.userMessage)
                    retrying = true
                } else {
                    finalResponse = response
                    _log("finished " + _label(request) + ": " + (response.ok ? "HTTP " + response.status + ", " + (Array.isArray(series) ? series.length + " candles" : "reference " + series)
                                                                              : "failed [" + response.error.code + "] " + response.error.userMessage))
                }
            } else {
                _log("dropped " + _label(request) + ": nobody waits for it any more")
            }
        } catch (e) {
            // Unexpected: still a final, failed ProviderResponse for the caller to show.
            _log("unexpected failure for " + _label(request) + ": " + String(e && e.message))
            finalResponse = _failed(e)
        } finally {
            _activeCount = Math.max(0, _activeCount - 1)
            pumpTimer.restart()
        }

        if (!retrying) _complete(request, finalResponse, series)
    }

    Component { id: responseComponent; ProviderResponse {} }

    function _failed(error) {
        var failure = ResponseInterpreter.failure(properties.providerId, error)
        return responseComponent.createObject(null, failure)
    }

    // The newest `request.candles` candles of a successful answer (0 = all).
    function _parse(request, response) {
        var fetchType = request.context.fetchType
        if (fetchType === FetchType.Values.CHANGE) return parseChange(response)
        return fetchType === FetchType.Values.PRICE ? parsePrice(response, request.candles) : parseChart(response, request.candles)
    }

    // Reports the final result (if anyone still waits for it) and forgets the call —
    // even when the listener throws.
    function _complete(request, response, series) {
        try {
            if (response) finished(request.context, response, series)
        } finally {
            _keys = Helpers.withoutEntry(_keys, request.key)
            _changePending(request.group, -1)
        }
    }

    // ── Retrying ──────────────────────────────────────────────────────────────
    // Bounded: only transient errors reach here, never beyond `maxRetries` attempts per call,
    // and the queue itself is capped.
    function _scheduleRetry(job) {
        if (_retryQueue.length >= JsK.RETRY_QUEUE_MAX) {
            _log("retry queue is full: not retrying " + _label(job.request))
            return false
        }
        for (var i = 0; i < _retryQueue.length; i++)
            if (_retryQueue[i].request.key === job.request.key) return false
        var queue = _retryQueue.slice()
        queue.push(job)
        _retryQueue = queue
        retryTimer.interval = JsK.RETRY_INTERVAL_MS * job.attempt   // backoff grows with the attempt
        retryTimer.restart()
        return true
    }

    Timer {
        id: retryTimer
        interval: JsK.RETRY_INTERVAL_MS
        repeat: false
        onTriggered: root._processRetryQueue()
    }

    function _processRetryQueue() {
        if (_retryQueue.length === 0) return
        var queue = _retryQueue.slice()
        var job = queue.shift()
        _retryQueue = queue

        if (!_isCurrent(job.request)) {                              // nobody waits any more
            _log("dropped the retry of " + _label(job.request) + ": nobody waits for it any more")
            _complete(job.request, null)
        } else {
            _enqueue(job)
        }

        if (_retryQueue.length > 0) {
            retryTimer.interval = JsK.RETRY_SUBSEQUENT_MS
            retryTimer.restart()
        }
    }

    // ── Pending counter (drives the "refreshing…" state) ──────────────────────
    function _changePending(group, delta) {
        if (!group) return
        var count = Math.max(0, (pending[group] || 0) + delta)
        pending = count === 0 ? Helpers.withoutEntry(pending, group) : Helpers.withEntry(pending, group, count)   // notifies through the property's own pendingChanged()
    }
}
