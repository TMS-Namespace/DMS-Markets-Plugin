import QtQuick
import "../../../Helpers"
import "../../../../src/QML/Services"
import "../../../../src/QML/Contracts"
import "../../../../src/JS/Helpers/Constants.js" as JsConstants

TestSuite {
    id: suite

    property Component contextType: Component { FetchContext {} }
    property var seen: ({ finished: [], pendingChanges: [] })
    property var handler: null
    property bool current: true
    property real now: 1000
    readonly property int max: JsConstants.MAX_RETRIES

    function envelope(curlExit, status, body) { return "MARKETS-RESPONSE " + curlExit + " " + status + "\n" + (body || "") }
    readonly property string wiseBody: JSON.stringify([{ value: 2, time: 1000 }, { value: 4, time: 2000 }])

    function setup() {
        ProvidersManager.reload(ProvidersManager.sources)         // fresh handlers: no state leaks between tests
        seen = { finished: [], pendingChanges: [] }
        current = true; now = 1000
        handler = ProvidersManager.handlerFor(ProviderType.Wise)
        handler.clock = function() { return suite.now }
        handler.finished.connect(function(context, response, series) { seen.finished.push({ context: context, response: response, series: series }) })
        handler.pendingChanged.connect(function() { seen.pendingChanges.push(Object.assign({}, handler.pending)) })
    }

    function context() { return contextType.createObject(null, { uid: "u1", ticker: "BRLPLN", providerId: "wise", fetchType: "price", chartRange: "1M", chartResolution: "1d" }) }
    // A call as plain data: what the handler builds from a ProviderRequest and a FetchContext.
    function request(key, extra) {
        var fields = { url: key || "price_url", group: "u1", command: ["bash", "-c", "x"], candles: 0 }
        for (var field in extra) fields[field] = extra[field]
        fields.context = contextType.createObject(null, { uid: fields.group, ticker: "BRLPLN", providerId: "wise", fetchType: "price", chartRange: "1M", chartResolution: "1d" })
        fields.key = fields.group + "_price_" + fields.url
        return fields
    }
    function isCurrentCallback(context) { seen.contexts = (seen.contexts || []).concat([context]); return suite.current }
    function send(call) { return handler._submit({ url: call.url, command: call.command, candles: call.candles }, call.context, isCurrentCallback) }

    // Runs the oldest queued job as ProviderHandler._pump would, minus the real process.
    function runNext(exitCode, stdout, stderr) {
        var job = handler._queue[0]
        check(!!job, "a job is queued")
        handler._queue = handler._queue.slice(1)
        handler._activeCount += 1
        handler._handleFinished(job, exitCode, stdout, stderr || "")
        return job
    }
    // Move the fake clock to the next deadline; no wall-clock waiting in queue unit tests.
    function advanceRetry() {
        now = Math.max(now, handler._retryQueue[0].readyAt, handler._retryAfter)
        handler._processRetryQueue()
    }
    function keyCount() { return Object.keys(handler._keys).length }

    // ── Submitting ───────────────────────────────────────────────────────────
    function test_submit_counts_pending_per_group_and_refuses_duplicates() {
        check(send(request()))
        same(handler._queue.length, 1)
        equal(handler.pending, { u1: 1 })
        check(!send(request()), "the same call is never in flight twice")
        same(handler._queue.length, 1)
        check(send(request("u1_graph_url")), "a different call is separate")
        equal(handler.pending, { u1: 2 })
        check(send(request("nogroup", { group: "" })), "a group is optional")
        equal(handler.pending, { u1: 2 })
    }
    // ── Final response ───────────────────────────────────────────────────────
    function test_success_reports_one_final_response_with_the_callers_context() {
        send(request())
        runNext(0, envelope(0, 200, wiseBody))
        same(seen.finished.length, 1)
        var finished = seen.finished[0]
        same(finished.context.uid, "u1"); same(finished.context.fetchType, "price")
        check(finished.response.ok); same(finished.response.status, 200); same(finished.response.body, wiseBody)
        equal(handler.pending, {}); same(keyCount(), 0)
        check(send(request()), "the call is forgotten, so it can be submitted again")
        equal(seen.pendingChanges.map(function(pending) { return pending.u1 || 0 }), [1, 0, 1])
    }
    function test_permanent_failures_are_final_at_once() {
        var cases = [[envelope(0, 404, "{}"), "notFound"], [envelope(0, 400, "x"), "http"], [envelope(0, 403, "x"), "credential"],
                     [envelope(0, 200, " "), "noData"], [envelope(35, "000"), "network"]]
        for (var i = 0; i < cases.length; i++) {
            setup()
            send(request())
            runNext(0, cases[i][0])
            same(handler._retryQueue.length, 0, cases[i][1] + ": no retry")
            same(seen.finished.length, 1); check(!seen.finished[0].response.ok)
            same(seen.finished[0].response.error.code, cases[i][1])
            equal(handler.pending, {})
        }
    }
    function test_process_failures() {
        var cases = [[127, "process"], [126, "process"], [-1, "process"], [1, "network"]]
        for (var i = 0; i < cases.length; i++) {
            setup()
            send(request())
            runNext(cases[i][0], "", "bash: curl: command not found")
            same(seen.finished[0].response.error.code, cases[i][1], "exit " + cases[i][0])
            check(seen.finished[0].response.error.details.indexOf("command not found") !== -1, "stderr is kept for the log")
        }
    }

    // ── Parsing is bounded by the window the call asked for ──────────────────
    function test_only_the_requested_newest_candles_are_parsed() {
        var body = JSON.stringify([1, 2, 3, 4, 5].map(function(value) { return { value: value, time: value * 1000 } }))
        send(request("a", { candles: 3 }))
        runNext(0, envelope(0, 200, body))
        var series = seen.finished[0].series
        equal(series.map(function(candle) { return candle.close }), [3, 4, 5], "the newest three, oldest first")
        equal(series.map(function(candle) { return candle.open }), [2, 3, 4], "the oldest wanted candle still has its real open")
        setup()
        send(request("b", { candles: 0 }))
        runNext(0, envelope(0, 200, body))
        same(seen.finished[0].series.length, 5, "0 means unbounded")
    }
    function test_an_unreadable_answer_is_a_final_failure_not_a_retry() {
        send(request("c", { candles: 3 }))
        runNext(0, envelope(0, 200, "not json"))
        same(handler._retryQueue.length, 0)
        same(seen.finished.length, 1); check(!seen.finished[0].response.ok); same(seen.finished[0].response.error.code, "parse")
        same(seen.finished[0].series, null)
    }

    // ── Development log (dev mode only, never a URL or credential) ───────────
    function test_the_handler_logs_its_work_in_dev_mode_without_urls_or_credentials() {
        var lines = []
        Logger.configure({ devMode: true, sink: function(level, scope, text) { lines.push(text) } })
        handler.properties.credential = "SECRET-KEY"
        send(request("https://x.test/?apikey=SECRET-KEY"))
        runNext(0, envelope(6, "000"))                          // transient: a retry
        advanceRetry()
        runNext(0, envelope(0, 200, wiseBody))
        var text = lines.join("\n")
        check(/queued BRLPLN price/.test(text), "queued"); check(/retrying BRLPLN price/.test(text), "retry")
        check(/finished BRLPLN price: HTTP 200, 2 candles/.test(text), "result with the candle count")
        check(text.indexOf("SECRET-KEY") === -1 && text.indexOf("x.test") === -1, "no URL and no credential in the log")
    }
    function test_nothing_is_logged_when_dev_mode_is_off() {
        var lines = []
        Logger.configure({ devMode: false, sink: function(level, scope, text) { lines.push(text) } })
        send(request("a")); runNext(0, envelope(0, 200, wiseBody))
        same(lines.length, 0)
    }

    // ── Retries ──────────────────────────────────────────────────────────────
    function test_transient_failure_is_retried_then_succeeds() {
        send(request())
        runNext(0, envelope(6, "000"), "curl: (6) Could not resolve host")
        same(seen.finished.length, 0, "a retry reports nothing yet")
        same(handler._retryQueue.length, 1); same(handler._retryQueue[0].attempt, 1)
        same(handler._activeCount, 0, "the failed attempt frees the slot")
        equal(handler.pending, { u1: 1 })
        check(!send(request()), "cannot be submitted again meanwhile")
        advanceRetry()
        same(handler._retryQueue.length, 0); same(handler._queue.length, 1)
        runNext(0, envelope(0, 200, wiseBody))
        same(seen.finished.length, 1); check(seen.finished[0].response.ok)
        equal(handler.pending, {})
    }
    function test_a_permanently_failing_provider_is_called_one_plus_max_retries_times() {
        send(request())
        var attempts = 0
        for (;;) {
            attempts++
            check(attempts <= max + 1, "never more attempts than the limit allows")
            runNext(0, envelope(28, "000"), "timed out")
            if (handler._retryQueue.length === 0) break
            advanceRetry()
        }
        same(attempts, max + 1)
        same(seen.finished.length, 1)
        same(seen.finished[0].response.error.code, "timeout")
        same(seen.finished[0].response.error.userMessage, "Wise took too long to answer.")
        equal(handler.pending, {}); same(keyCount(), 0)
    }
    function test_server_errors_and_rate_limits_are_transient() {
        var statuses = [429, 500, 502, 503]
        for (var i = 0; i < statuses.length; i++) {
            setup()
            send(request("k", { command: ["bash", "-c", "same-command"] }))
            runNext(0, envelope(0, statuses[i], "x"))
            same(handler._retryQueue.length, 1, "HTTP " + statuses[i] + " is retried")
            advanceRetry()
            equal(handler._queue[0].request.command, ["bash", "-c", "same-command"], "the same request is repeated")
            same(handler._queue[0].attempt, 1)
        }
    }
    function test_retry_queue_is_bounded_and_deduplicated() {
        function job(key) { return { request: request(key), attempt: 1 } }
        check(handler._scheduleRetry(job("a")))
        check(!handler._scheduleRetry(job("a")), "the same call is never queued twice")
        for (var i = 0; i < JsConstants.RETRY_QUEUE_MAX * 2; i++) handler._scheduleRetry(job("k" + i))
        same(handler._retryQueue.length, JsConstants.RETRY_QUEUE_MAX, "hard cap")
        check(!handler._scheduleRetry(job("extra")))
    }
    function test_max_retries_zero_means_none() {
        handler.maxRetries = 0
        send(request())
        runNext(0, envelope(6, "000"))
        same(handler._retryQueue.length, 0); same(seen.finished.length, 1)
        check(max >= 1 && max <= 5, "a small, finite default retry limit")
    }

    // ── Removed symbols ──────────────────────────────────────────────────────
    function test_calls_nobody_waits_for_are_dropped_silently() {
        current = false
        send(request())
        runNext(0, envelope(0, 200, wiseBody))
        same(seen.finished.length, 0, "no result for a removed symbol")
        equal(handler.pending, {}); same(handler._activeCount, 0); same(keyCount(), 0)
    }
    function test_a_removed_symbols_retry_is_dropped_when_its_turn_comes() {
        send(request())
        runNext(0, envelope(6, "000"))
        current = false
        advanceRetry()
        same(handler._queue.length, 0); same(seen.finished.length, 0)
        equal(handler.pending, {}); same(keyCount(), 0)
    }
    function test_is_current_receives_the_callers_context() {
        send(request())
        runNext(0, envelope(0, 200, wiseBody))
        same(seen.contexts[0].uid, "u1")
    }

    // The handler outlives the widgets that call it: DMS recreates widgets (reload, wake from sleep) and the old
    // owner's callback then throws ("Property '_findSymbol' of object [null] is not a function"). That is not a
    // failed fetch: the result is still reported.
    function test_a_callback_of_a_destroyed_owner_does_not_fail_the_call() {
        handler._submit({ url: "u", command: ["x"], candles: 2 }, request().context, function() { throw new TypeError("Property '_findSymbol' of object [null] is not a function") })
        runNext(0, envelope(0, 200, wiseBody))
        same(seen.finished.length, 1, "the result is reported")
        check(seen.finished[0].response.ok, "…as a success, not 'Something went wrong'")
        equal(handler.pending, {}); same(handler._activeCount, 0)
    }

    // ── Never throws, never stalls ───────────────────────────────────────────
    function test_unexpected_exceptions_become_failed_responses() {
        send(request("x"))
        handler.api = null                                         // interpreting now throws a TypeError
        runNext(0, envelope(0, 200, "x"))
        same(seen.finished.length, 1)
        check(!seen.finished[0].response.ok)
        same(handler._activeCount, 0, "the slot is released")
        equal(handler.pending, {})
    }
    function test_a_retry_cannot_leak_a_slot_or_a_key() {
        send(request("a")); send(request("b", { group: "u2" }))
        runNext(0, envelope(6, "000"))
        same(handler._activeCount, 0)
        runNext(0, envelope(0, 200, wiseBody))
        equal(handler.pending, { u1: 1 }, "only the call waiting for its retry remains")
    }

    // ── A real process, end to end ───────────────────────────────────────────
    function async_runs_a_real_command_and_reports_its_answer(done) {
        var call = request("real", { candles: 1, command: ["bash", "-c", "printf 'MARKETS-RESPONSE 0 200\\n%s' \"$1\"", "x", JSON.stringify([{ value: 2, time: 1000 }, { value: 3, time: 2000 }])] })
        handler.finished.connect(function(context, response, series) {
            done(response.ok && series.length === 1 && series[0].close === 3 && response.status === 200 ? "" : "unexpected response: " + response.body + " " + (response.error && response.error.details))
        })
        send(call)
    }
    function test_new_request_queue_is_bounded_without_leaking_pending_counts() {
        for (var i = 0; i < JsConstants.FETCH_QUEUE_MAX; i++) check(send(request("request-" + i)))
        var failure = throws(function() { send(request("overflow")) }, "queue reached its limit")
        same(failure.code, "process")
        same(handler._queue.length, JsConstants.FETCH_QUEUE_MAX)
        same(handler.pending.u1, JsConstants.FETCH_QUEUE_MAX)
        same(keyCount(), JsConstants.FETCH_QUEUE_MAX)
        check(!send(request("request-0")), "a duplicate still reports already in flight")
    }

    function test_each_retry_keeps_its_deadline_when_more_failures_arrive() {
        check(handler._scheduleRetry({ request: request("first"), attempt: 1 }))
        now += 1000
        check(handler._scheduleRetry({ request: request("later"), attempt: 2 }))
        now = 1000 + JsConstants.RETRY_INTERVAL_MS - 1
        handler._processRetryQueue()
        same(handler._queue.length, 0, "never before the first backoff expires")
        now++
        handler._processRetryQueue()
        same(handler._queue.length, 1, "a later failure never postpones the first retry")
        same(handler._queue[0].request.url, "first")
        now = 2000 + JsConstants.RETRY_INTERVAL_MS * 2 - 1
        handler._processRetryQueue()
        same(handler._queue.length, 1, "the second attempt keeps its longer delay")
        now++
        handler._processRetryQueue()
        same(handler._queue.length, 2)
        same(handler._queue[1].request.url, "later")
    }

}
