// ProviderHandler.qml - one market-data provider, wrapped: the ONLY way the plugin talks to a provider.
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

pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "../Contracts"
import "../../JS/Helpers/Constants.js" as JsConstants
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
    property int  maxRetries: JsConstants.MAX_RETRIES
    property var clock: function() { return Date.now() }

    // ── Outputs ───────────────────────────────────────────────────────────────
    // Number of calls per `group` (the symbol's uid) that are queued, running, or waiting to be retried.
    property var  pending: ({})
    // The final result of one call: `response` is a ProviderResponse (ok or failed).
    signal finished(var context, var response, var series)

    // ── State ─────────────────────────────────────────────────────────────────
    property int  _activeCount: 0
    property var  _queue:       []     // jobs waiting for a slot
    property var  _keys:        ({})   // keys of calls in flight (queued, running or awaiting retry)
    property var _transfers:   ({})   // identical commands share one queued/running transfer and retry budget
    property real _rateLimitUntil: 0  // a provider-wide pause after HTTP 429
    property real _retryAfter: 0      // earliest next retry start, for spacing between ready jobs
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

    // Update the credential held by this provider facade.
    function setCredential(value) { properties.credential = value || "" }
    // Check a credential against the provider declaration.
    function isValidCredential(value) { return ProviderRules.isValidCredential(properties, value) }
    // Check whether the current credential permits a request.
    function hasRequiredCredential() { return isValidCredential(properties.credential) }

    // Dropdown entries for DMS's SelectionSetting: { label, value }, limited to what the provider serves
    // and ChartRules allows.
    function _options(values, labelOf) { return values.map(function(value) { return { label: labelOf(value), value: value } }) }
    // Build display options for the supported price resolutions.
    function priceResolutionOptions() { return _options(SelectionPolicy.priceResolutions(properties), Resolution.label) }
    // Build display options for the supported change resolutions.
    function changeResolutionOptions() { return _options(SelectionPolicy.changeResolutions(properties), Resolution.label) }
    // Build display options for readable chart resolutions.
    function chartResolutionOptions() { return _options(SelectionPolicy.allowedChartResolutions(properties), Resolution.label) }
    // Build display options for readable spans at this chart resolution.
    function chartSpanOptions(resolution) { return _options(SelectionPolicy.allowedChartSpans(properties, resolution), ChartSpan.label) }

    // Build the provider default selection from its supported choices.
    function defaultSelection() { return selectionType.createObject(null, SelectionPolicy.defaultSelection(properties)) }

    // The closest selection this provider serves that is also readable (see SelectionPolicy.clamp).
    function clampSelection(selection) {
        let fields = SelectionPolicy.clamp(properties, selection)
        return selectionType.createObject(null, fields)
    }

    // How well a chart resolution fits a chart range (a ChartStatus).
    function chartRangeStatus(resolution, span) { return statusType.createObject(null, ChartRules.evaluate(resolution, span)) }

    // ── Fetching ──────────────────────────────────────────────────────────────
    // `context` is a FetchContext (returned untouched with the result); `isCurrent(context)` is asked
    // before a retry and before reporting, and returns false for calls nobody waits for any more (e.g. the
    // symbol was removed meanwhile). Throws PluginError when the request cannot be made: provider disabled,
    // credential missing, symbol or selection not acceptable for this provider.

    // Validate and submit a price request through the shared queue.
    function fetchPrice(symbol, resolution, context, isCurrent) { return _submit(priceRequest(symbol, resolution), context, isCurrent) }
    // Validate and submit a chart request through the shared queue.
    function fetchChart(symbol, resolution, span, context, isCurrent) { return _submit(chartRequest(symbol, resolution, span), context, isCurrent) }
    // Validate and submit a change reference request through the shared queue.
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

    // Validate the chart selection and bound the number of candles requested.
    function chartRequest(symbol, resolution, span) {
        _assertUsable()
        SymbolRules.assertValid(properties, symbol)
        SelectionPolicy.assertChart(properties, resolution, span)
        SelectionPolicy.assertPull(properties, resolution)        // the chart is pulled every `resolution`
        // A chart needs exactly as many candles as its range holds at its resolution: no more are parsed
        // (or, where the API and fetch script allow it, fetched).
        let candles = ChartSpan.pointLimit(resolution, span)
        return _request(api.historyUrl(symbol, resolution, span, properties.credential),
                        properties.tailHistory ? candles : 0, candles)
    }

    // What a fetch process produced → ProviderResponse (status, body, or a friendly PluginError).
    // `result` has exitCode, stdout, stderr.
    function interpret(result) {
        let response = ResponseInterpreter.fromProcess(properties.providerId, properties.name, result, {
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
        let reference = api.parseChange(response.body)
        if (typeof reference !== "number" || !isFinite(reference) || reference === 0)
            throw new PluginError.PluginError(PluginError.Code.PARSE, "The provider sent an answer that couldn't be understood.",
                                              properties.providerId + ": unusable previous close '" + reference + "'")
        return reference
    }
    // Parse and validate the requested chart candles from a successful response.
    function parseChart(response, limit) {
        ResponseInterpreter.assertOk(response)
        return SeriesRules.assertSeries(api.parseHistory(response.body, limit))
    }

    // Refuse disabled providers and missing required credentials.
    function _assertUsable() {
        if (properties.disabled)
            throw new PluginError.PluginError(PluginError.Code.UNSUPPORTED, properties.name + " is currently disabled.",
                                              "provider " + properties.providerId + " is disabled")
        if (!hasRequiredCredential())
            throw new PluginError.PluginError(PluginError.Code.CREDENTIAL, "Add your " + properties.credentialLabel + " in the settings.",
                                              "no valid credential for " + properties.providerId)
    }

    // Build the typed request with its command arguments and candle limit.
    function _request(url, tailLines, candles) {
        return requestType.createObject(null, {
            url: url, tailLines: tailLines, candles: candles,
            command: FetchCommand.build(url, tailLines, api.fetchScript ? api.fetchScript(tailLines) : "")
        })
    }

    // Development log (dev mode only). Never put a URL or key in it: they can carry the credential.
    function _log(text) { Logger.debug("providers", properties.providerId + ": " + text) }
    // Describe a queued call without exposing its URL or credential.
    function _label(request) { return request.context.ticker + " " + request.context.fetchType }

    // Deduplicate callers separately from transfers: each caller keeps its context and parse limit.
    function _submit(request, context, isCurrent) {
        let key = context.uid + "_" + context.fetchType + "_" + request.url + (context.signature ? "|" + context.signature : "")
        if (_keys[key]) return false
        if (Object.keys(_keys).length >= JsConstants.FETCH_QUEUE_MAX)
            throw new PluginError.PluginError(PluginError.Code.PROCESS, "Too many market requests are queued. Try again shortly.",
                                              "provider request queue reached its limit", { retryable: true })
        let call = callType.createObject(null, {
            key: key, group: context.uid, command: request.command, candles: request.candles,
            context: context, isCurrent: isCurrent || null
        }) as FetchCall
        // The command includes credentials and output trimming, so only interchangeable responses share work.
        let transferKey = FetchCommand.transferKey(request.url, request.command)
        let transfer = _transfers[transferKey]
        _keys = Helpers.withEntry(_keys, key, true)
        _changePending(call.group, 1)
        if (transfer) {
            transfer.listeners.push(call)
            _log("shared " + _label(call) + " with an existing request")
        } else {
            transfer = { request: call, listeners: [call], transferKey: transferKey, attempt: 0 }
            _transfers = Helpers.withEntry(_transfers, transferKey, transfer)
            _enqueue(transfer)
            _log("queued " + _label(call) + " (needs " + call.candles + " candles, " + _queue.length + " waiting)")
        }
        return true
    }

    // Release obsolete callers before consuming a process slot; another caller may still need this transfer.
    function _pruneJob(job) {
        let live = []
        let listeners = job.listeners || [job.request]
        for (let call of listeners) {
            if (_isCurrent(call)) live.push(call)
            else _complete(call, null)
        }
        job.listeners = live
        if (live.length) job.request = live[0]
        else if (job.transferKey) _transfers = Helpers.withoutEntry(_transfers, job.transferKey)
        return live.length > 0
    }

    // The handler outlives the widgets that ask it for data (DMS recreates widgets, e.g. after a reload or
    // wake-up), so a callback may belong to an object that is gone and throw when called. Such a call is not
    // a failed fetch: it stays current and its result is simply reported.
    function _isCurrent(request) {
        if (!request.isCurrent) return true
        try {
            return request.isCurrent(request.context) !== false
        } catch (caughtError) {
            _log("the owner of " + _label(request) + " is gone (" + String(caughtError && caughtError.message) + "): reporting the result anyway")
            return true
        }
    }

    // ── Queue, running, retries ───────────────────────────────────────────────

    // Append a queued job and schedule the next available process slot.
    function _enqueue(job) {
        let queue = _queue.slice()
        queue.push(job)
        _queue = queue
        pumpTimer.interval = JsConstants.FETCH_QUEUE_PUMP_MS
        pumpTimer.restart()
    }

    // ── Running ───────────────────────────────────────────────────────────────
    Timer {
        id: pumpTimer
        interval: JsConstants.FETCH_QUEUE_PUMP_MS
        repeat: false
        onTriggered: root._pump()
    }

    // Run the oldest queued job when a process slot is available.
    function _pump() {
        if (_queue.length === 0) return
        if (_activeCount >= JsConstants.MAX_CONCURRENT_FETCHES) return
        if (clock() < _rateLimitUntil) {
            pumpTimer.interval = Math.max(1, _rateLimitUntil - clock())
            pumpTimer.restart()
            return
        }
        pumpTimer.interval = JsConstants.FETCH_QUEUE_PUMP_MS

        let queue = _queue.slice()
        let job = queue.shift()
        _queue = queue
        if (!_pruneJob(job)) { pumpTimer.restart(); return }
        _activeCount = _activeCount + 1
        _log("started " + _label(job.request) + " (attempt " + (job.attempt + 1) + ")")

        let process
        try {
            process = processComponent.createObject(root, { job: job }) as Process
            process.command = job.request.command
            process.running = true
        } catch (caughtError) {
            // The process could not even be started: that is a failed call, not a stalled queue.
            _log("could not start the process for " + _label(job.request) + ": " + String(caughtError && caughtError.message))
            _handleFinished(job, -1, "", String(caughtError && caughtError.message))
        }
    }

    Component {
        id: processComponent

        Process {
            id: requestProcess
            property var    job
            property string _buffer: ""
            property string _stderr: ""

            stdout: StdioCollector {
                onStreamFinished: { requestProcess._buffer = text }
            }

            stderr: SplitParser {
                onRead: line => {
                    if (requestProcess._stderr.length < JsConstants.STDERR_MAX_CHARS) requestProcess._stderr += line + "\n"
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
        let response = null
        let retrying = false
        try {
            let current = _pruneJob(job)
            response = interpret({ exitCode: exitCode, stdout: stdout, stderr: stderr })
            // A rate limit applies to the provider even if the requesting symbol was removed meanwhile.
            if (response.status === 429)
                _rateLimitUntil = Math.max(_rateLimitUntil, clock() + JsConstants.RATE_LIMIT_COOLDOWN_MS * Math.pow(2, Math.min(job.attempt, maxRetries)))
            if (current) {
                if (!response.ok && ErrorHandler.shouldRetry(response.error, job.attempt, maxRetries)) {
                    job.attempt++
                    retrying = _scheduleRetry(job)
                    if (retrying) _log("retrying " + _label(job.request) + " (retry " + job.attempt + "/" + maxRetries + "): " + response.error.userMessage)
                }
            }
        } catch (caughtError) {
            response = _failed(caughtError)
        } finally {
            _activeCount = Math.max(0, _activeCount - 1)
            pumpTimer.restart()
        }
        if (!retrying) _finishJob(job, response)
    }

    // Parse each caller's view of the shared answer; one parse failure must not prevent other deliveries.
    function _finishJob(job, response) {
        if (job.transferKey) _transfers = Helpers.withoutEntry(_transfers, job.transferKey)
        for (let call of job.listeners || [job.request]) {
            let finalResponse = response
            let series = null
            if (finalResponse && finalResponse.ok) {
                try { series = _parse(call, finalResponse) }
                catch (caughtError) { finalResponse = _failed(caughtError) }
            }
            try {
                _log("finished " + _label(call) + ": " + (finalResponse && finalResponse.ok
                    ? "HTTP " + finalResponse.status + ", " + (Array.isArray(series) ? series.length + " candles" : "reference " + series)
                    : "failed"))
                _complete(call, finalResponse, series)
            } catch (caughtError) {
                ErrorHandler.handle("providers", PluginError.from(caughtError), { notify: false })
            }
        }
    }

    Component { id: responseComponent; ProviderResponse {} }

    // Turn an exception into a typed failed provider response.
    function _failed(error) {
        let failure = ResponseInterpreter.failure(properties.providerId, error)
        return responseComponent.createObject(null, failure)
    }

    // The newest `request.candles` candles of a successful answer (0 = all).
    function _parse(request, response) {
        let fetchType = request.context.fetchType
        if (fetchType === FetchType.Values.CHANGE) return parseChange(response)
        return fetchType === FetchType.Values.PRICE ? parsePrice(response, request.candles) : parseChart(response, request.candles)
    }

    // Reports the final result (if anyone still waits for it) and forgets the call -
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
        if (_retryQueue.length >= JsConstants.RETRY_QUEUE_MAX) {
            _log("retry queue is full: not retrying " + _label(job.request))
            return false
        }
        for (let i = 0; i < _retryQueue.length; i++)
            if (_retryQueue[i].request.key === job.request.key) return false
        let queue = _retryQueue.slice()
        job.readyAt = clock() + JsConstants.RETRY_INTERVAL_MS * job.attempt
        queue.push(job)
        queue.sort(function(earlier, later) { return earlier.readyAt - later.readyAt })
        _retryQueue = queue
        _armRetryTimer()
        return true
    }

    // New failures cannot postpone an older job or bypass another job's growing backoff.
    function _armRetryTimer() {
        if (_retryQueue.length === 0) return
        retryTimer.interval = Math.max(1, Math.max(_retryQueue[0].readyAt, _retryAfter, _rateLimitUntil) - clock())
        retryTimer.restart()
    }

    Timer {
        id: retryTimer
        interval: JsConstants.RETRY_INTERVAL_MS
        repeat: false
        onTriggered: root._processRetryQueue()
    }

    // Requeue the next live retry and release obsolete requests.
    function _processRetryQueue() {
        if (_retryQueue.length === 0) return
        if (clock() < Math.max(_retryQueue[0].readyAt, _retryAfter, _rateLimitUntil)) { _armRetryTimer(); return }
        let queue = _retryQueue.slice()
        let job = queue.shift()
        _retryQueue = queue
        _retryAfter = clock() + JsConstants.RETRY_SUBSEQUENT_MS

        if (_pruneJob(job)) _enqueue(job)

        if (_retryQueue.length > 0) _armRetryTimer()
    }

    // ── Pending counter (drives the "refreshing…" state) ──────────────────────
    function _changePending(group, delta) {
        if (!group) return
        let count = Math.max(0, (pending[group] || 0) + delta)
        pending = count === 0 ? Helpers.withoutEntry(pending, group) : Helpers.withEntry(pending, group, count)   // notifies through the property's own pendingChanged()
    }
}
