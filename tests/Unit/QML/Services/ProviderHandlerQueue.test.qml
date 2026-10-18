import QtQuick
import "../../../../src/JS/Helpers/Constants.js" as JsConstants
import "../../../../src/QML/Contracts"
import "../../../../src/QML/Services"
import "../../../Helpers"

TestSuite {
    id: suite

    property Component contextType: Component {
        FetchContext {
        }
    }
    property bool current: true
    property var handler: null
    readonly property int max: JsConstants.MAX_RETRIES
    property real now: 1000
    property var seen: ({
            finished: [],
            pendingChanges: []
        })
    readonly property string wiseBody: JSON.stringify([
        {
            value: 2,
            time: 1000
        },
        {
            value: 4,
            time: 2000
        }
    ])

    // Move the fake clock to the next deadline; no wall-clock waiting in queue unit tests.
    function advanceRetry() {
        now = Math.max(now, handler._retryQueue[0].readyAt, handler._retryAfter, handler._rateLimitUntil);
        handler._processRetryQueue();
    }

    // ── A real process, end to end ───────────────────────────────────────────
    function async_runs_a_real_command_and_reports_its_answer(done) {
        let call = request("real", {
            candles: 1,
            command: ["bash", "-c", "printf 'MARKETS-RESPONSE 0 200\\n%s' \"$1\"", "x", JSON.stringify([
                    {
                        value: 2,
                        time: 1000
                    },
                    {
                        value: 3,
                        time: 2000
                    }
                ])]
        });
        handler.finished.connect(function (context, response, series) {
            done(response.ok && series.length === 1 && series[0].close === 3 && response.status === 200 ? "" : "unexpected response: " + response.body + " " + (response.error && response.error.details));
        });
        send(call);
    }

    // Verify physical process counts, not only queue contents, when two views share one response.
    function async_shared_calls_start_one_real_process(done) {
        let starts = 0;
        Logger.configure({
            devMode: true,
            sink: function (level, scope, text) {
                if (text.indexOf("started ") !== -1)
                    starts++;
            }
        });
        let command = ["bash", "-c", "printf 'MARKETS-RESPONSE 0 200\\n%s' \"$1\"", "test", wiseBody];
        send(request("shared-process", {
            command: command,
            candles: 1
        }));
        let graph = request("shared-process", {
            command: command,
            candles: 2,
            group: "u2"
        });
        graph.context.fetchType = "graph";
        send(graph);
        waitUntil(function () {
            return seen.finished.length === 2 && keyCount() === 0;
        }, function (problem) {
            try {
                if (problem)
                    throw new Error(problem);
                same(starts, 1, "one physical request serves both callers");
                same(seen.finished[0].series.length, 1);
                same(seen.finished[1].series.length, 2);
                equal(handler.pending, {});
                done("");
            } catch (error) {
                done(error.message);
            }
        });
    }
    function context() {
        return (contextType.createObject(null, {
                uid: "u1",
                ticker: "BRLPLN",
                providerId: "wise",
                fetchType: "price",
                chartRange: "1M",
                chartResolution: "1d"
            }) as FetchContext);
    }
    function envelope(curlExit, status, body) {
        return "MARKETS-RESPONSE " + curlExit + " " + status + "\n" + (body || "");
    }
    function isCurrentCallback(context) {
        seen.contexts = (seen.contexts || []).concat([context]);
        return suite.current;
    }
    function keyCount() {
        return Object.keys(handler._keys).length;
    }
    // A call as plain data: what the handler builds from a ProviderRequest and a FetchContext.
    function request(key, extra) {
        let fields = {
            url: key || "price_url",
            group: "u1",
            command: ["bash", "-c", "x"],
            candles: 0
        };
        for (let field in extra)
            fields[field] = extra[field];
        fields.context = (contextType.createObject(null, {
                uid: fields.group,
                ticker: "BRLPLN",
                providerId: "wise",
                fetchType: "price",
                chartRange: "1M",
                chartResolution: "1d"
            }) as FetchContext);
        fields.key = fields.group + "_price_" + fields.url;
        return fields;
    }

    // Runs the oldest queued job as ProviderHandler._pump would, minus the real process.
    function runNext(exitCode, stdout, stderr) {
        let job = handler._queue[0];
        check(!!job, "a job is queued");
        handler._queue = handler._queue.slice(1);
        handler._activeCount += 1;
        handler._handleFinished(job, exitCode, stdout, stderr || "");
        return job;
    }
    function send(call) {
        return handler._submit({
            url: call.url,
            command: call.command,
            candles: call.candles
        }, call.context, isCurrentCallback);
    }
    function setup() {
        ProvidersManager.reload(ProvidersManager.sources);         // fresh handlers: no state leaks between tests
        seen = {
            finished: [],
            pendingChanges: []
        };
        current = true;
        now = 1000;
        handler = ProvidersManager.handlerFor(ProviderType.Wise);
        handler.clock = function () {
            return suite.now;
        };
        handler.finished.connect(function (context, response, series) {
            seen.finished.push({
                context: context,
                response: response,
                series: series
            });
        });
        handler.pendingChanged.connect(function () {
            seen.pendingChanges.push(Object.assign({}, handler.pending));
        });
    }

    // The handler outlives the widgets that call it: DMS recreates widgets (reload, wake from sleep) and the old
    // owner's callback then throws ("Property '_findSymbol' of object [null] is not a function"). That is not a
    // failed fetch: the result is still reported.
    function test_a_callback_of_a_destroyed_owner_does_not_fail_the_call() {
        handler._submit({
            url: "u",
            command: ["x"],
            candles: 2
        }, request().context, function () {
            throw new TypeError("Property '_findSymbol' of object [null] is not a function");
        });
        runNext(0, envelope(0, 200, wiseBody));
        same(seen.finished.length, 1, "the result is reported");
        check(seen.finished[0].response.ok, "…as a success, not 'Something went wrong'");
        equal(handler.pending, {});
        same(handler._activeCount, 0);
    }
    function test_a_permanently_failing_provider_is_called_one_plus_max_retries_times() {
        send(request());
        let attempts = 0;
        for (; ; ) {
            attempts++;
            check(attempts <= max + 1, "never more attempts than the limit allows");
            runNext(0, envelope(28, "000"), "timed out");
            if (handler._retryQueue.length === 0)
                break;
            advanceRetry();
        }
        same(attempts, max + 1);
        same(seen.finished.length, 1);
        same(seen.finished[0].response.error.code, "timeout");
        same(seen.finished[0].response.error.userMessage, "Wise took too long to answer.");
        equal(handler.pending, {});
        same(keyCount(), 0);
    }
    function test_a_removed_symbols_retry_is_dropped_when_its_turn_comes() {
        send(request());
        runNext(0, envelope(6, "000"));
        current = false;
        advanceRetry();
        same(handler._queue.length, 0);
        same(seen.finished.length, 0);
        equal(handler.pending, {});
        same(keyCount(), 0);
    }
    function test_a_retry_cannot_leak_a_slot_or_a_key() {
        send(request("a"));
        send(request("b", {
            group: "u2"
        }));
        runNext(0, envelope(6, "000"));
        same(handler._activeCount, 0);
        runNext(0, envelope(0, 200, wiseBody));
        equal(handler.pending, {
            u1: 1
        }, "only the call waiting for its retry remains");
    }
    function test_an_unreadable_answer_is_a_final_failure_not_a_retry() {
        send(request("c", {
            candles: 3
        }));
        runNext(0, envelope(0, 200, "not json"));
        same(handler._retryQueue.length, 0);
        same(seen.finished.length, 1);
        check(!seen.finished[0].response.ok);
        same(seen.finished[0].response.error.code, "parse");
        same(seen.finished[0].series, null);
    }

    // ── Removed symbols ──────────────────────────────────────────────────────
    function test_calls_nobody_waits_for_are_dropped_silently() {
        current = false;
        send(request());
        runNext(0, envelope(0, 200, wiseBody));
        same(seen.finished.length, 0, "no result for a removed symbol");
        equal(handler.pending, {});
        same(handler._activeCount, 0);
        same(keyCount(), 0);
    }

    // Different shell output limits or credentials cannot safely share a response.
    function test_different_commands_for_the_same_url_stay_separate() {
        check(send(request("same", {
            command: ["x", "tail-2"]
        })));
        check(send(request("same", {
            group: "u2",
            command: ["x", "tail-30"]
        })));
        same(handler._queue.length, 2);
    }
    function test_each_retry_keeps_its_deadline_when_more_failures_arrive() {
        check(handler._scheduleRetry({
            request: request("first"),
            attempt: 1
        }));
        now += 1000;
        check(handler._scheduleRetry({
            request: request("later"),
            attempt: 2
        }));
        now = 1000 + JsConstants.RETRY_INTERVAL_MS - 1;
        handler._processRetryQueue();
        same(handler._queue.length, 0, "never before the first backoff expires");
        now++;
        handler._processRetryQueue();
        same(handler._queue.length, 1, "a later failure never postpones the first retry");
        same(handler._queue[0].request.url, "first");
        now = 2000 + JsConstants.RETRY_INTERVAL_MS * 2 - 1;
        handler._processRetryQueue();
        same(handler._queue.length, 1, "the second attempt keeps its longer delay");
        now++;
        handler._processRetryQueue();
        same(handler._queue.length, 2);
        same(handler._queue[1].request.url, "later");
    }

    // One HTTP response serves callers with different symbols, fetch types and candle windows.
    function test_identical_transfers_keep_each_callers_context_and_parse_limit() {
        let price = request("shared", {
            candles: 2
        });
        let graph = request("shared", {
            group: "u2",
            candles: 3
        });
        graph.context.fetchType = "graph";
        check(send(price));
        check(send(graph));
        same(handler._queue.length, 1, "one transfer");
        equal(handler.pending, {
            u1: 1,
            u2: 1
        });
        runNext(0, envelope(0, 200, JSON.stringify([1, 2, 3, 4].map(function (value) {
            return {
                value: value,
                time: value * 1000
            };
        }))));
        same(seen.finished.length, 2);
        same(seen.finished[0].context, price.context);
        same(seen.finished[1].context, graph.context);
        equal(seen.finished[0].series.map(function (candle) {
            return candle.close;
        }), [3, 4]);
        equal(seen.finished[1].series.map(function (candle) {
            return candle.close;
        }), [2, 3, 4]);
        equal(handler.pending, {});
        same(keyCount(), 0);
        same(Object.keys(handler._transfers).length, 0, "completed transfers release their listeners");
    }
    function test_is_current_receives_the_callers_context() {
        send(request());
        runNext(0, envelope(0, 200, wiseBody));
        same(seen.contexts[0].uid, "u1");
    }
    function test_max_retries_zero_means_none() {
        handler.maxRetries = 0;
        send(request());
        runNext(0, envelope(6, "000"));
        same(handler._retryQueue.length, 0);
        same(seen.finished.length, 1);
        check(max >= 1 && max <= 5, "a small, finite default retry limit");
    }
    function test_new_request_queue_is_bounded_without_leaking_pending_counts() {
        for (let i = 0; i < JsConstants.FETCH_QUEUE_MAX; i++)
            check(send(request("request-" + i)));
        let failure = throws(function () {
            send(request("overflow"));
        }, "queue reached its limit");
        same(failure.code, "process");
        same(handler._queue.length, JsConstants.FETCH_QUEUE_MAX);
        same(handler.pending.u1, JsConstants.FETCH_QUEUE_MAX);
        same(keyCount(), JsConstants.FETCH_QUEUE_MAX);
        check(!send(request("request-0")), "a duplicate still reports already in flight");
    }
    function test_nothing_is_logged_when_dev_mode_is_off() {
        let lines = [];
        Logger.configure({
            devMode: false,
            sink: function (level, scope, text) {
                lines.push(text);
            }
        });
        send(request("a"));
        runNext(0, envelope(0, 200, wiseBody));
        same(lines.length, 0);
    }

    // Obsolete jobs must never start their shell command or consume an active slot.
    function test_obsolete_queued_calls_are_dropped_before_starting_a_process() {
        send(request());
        current = false;
        handler._pump();
        same(handler._queue.length, 0);
        same(handler._activeCount, 0);
        equal(handler.pending, {});
        same(keyCount(), 0);
        same(Object.keys(handler._transfers).length, 0);
        same(seen.finished.length, 0);
    }

    // A removed symbol's in-flight response can still tell us that the whole provider is rate limited.
    function test_obsolete_responses_still_apply_provider_rate_limits() {
        send(request("removed"));
        current = false;
        runNext(0, envelope(0, 429, "slow down"));
        same(seen.finished.length, 0);
        equal(handler.pending, {});
        current = true;
        send(request("new"));
        handler._pump();
        same(handler._activeCount, 0);
        same(handler._queue.length, 1, "the next symbol respects the obsolete call's rate-limit response");
    }

    // Parsing one view of a response can fail without breaking another caller's valid view.
    function test_one_shared_parse_failure_does_not_fail_other_callers() {
        send(request("same"));
        let graph = request("same", {
            group: "u2"
        });
        graph.context.fetchType = "graph";
        send(graph);
        handler.api = {
            parsePrice: handler.api.parsePrice,
            parseHistory: function () {
                throw new Error("unreadable chart");
            }
        };
        runNext(0, envelope(0, 200, wiseBody));
        same(seen.finished.length, 2);
        check(seen.finished[0].response.ok);
        check(!seen.finished[1].response.ok);
        same(handler._retryQueue.length, 0);
        equal(handler.pending, {});
    }

    // ── Parsing is bounded by the window the call asked for ──────────────────
    function test_only_the_requested_newest_candles_are_parsed() {
        let body = JSON.stringify([1, 2, 3, 4, 5].map(function (value) {
            return {
                value: value,
                time: value * 1000
            };
        }));
        send(request("a", {
            candles: 3
        }));
        runNext(0, envelope(0, 200, body));
        let series = seen.finished[0].series;
        equal(series.map(function (candle) {
            return candle.close;
        }), [3, 4, 5], "the newest three, oldest first");
        equal(series.map(function (candle) {
            return candle.open;
        }), [2, 3, 4], "the oldest wanted candle still has its real open");
        setup();
        send(request("b", {
            candles: 0
        }));
        runNext(0, envelope(0, 200, body));
        same(seen.finished[0].series.length, 5, "0 means unbounded");
    }
    function test_permanent_failures_are_final_at_once() {
        let cases = [[envelope(0, 404, "{}"), "notFound"], [envelope(0, 400, "x"), "http"], [envelope(0, 403, "x"), "credential"], [envelope(0, 200, " "), "noData"], [envelope(35, "000"), "network"]];
        for (let i = 0; i < cases.length; i++) {
            setup();
            send(request());
            runNext(0, cases[i][0]);
            same(handler._retryQueue.length, 0, cases[i][1] + ": no retry");
            same(seen.finished.length, 1);
            check(!seen.finished[0].response.ok);
            same(seen.finished[0].response.error.code, cases[i][1]);
            equal(handler.pending, {});
        }
    }
    function test_process_failures() {
        let cases = [[127, "process"], [126, "process"], [-1, "process"], [1, "network"]];
        for (let i = 0; i < cases.length; i++) {
            setup();
            send(request());
            runNext(cases[i][0], "", "bash: curl: command not found");
            same(seen.finished[0].response.error.code, cases[i][1], "exit " + cases[i][0]);
            check(seen.finished[0].response.error.details.indexOf("command not found") !== -1, "stderr is kept for the log");
        }
    }

    // One rate-limit response pauses every queued request, including calls submitted during the pause.
    function test_rate_limits_pause_the_provider_instead_of_calling_other_symbols() {
        send(request("limited"));
        send(request("waiting", {
            group: "u2"
        }));
        runNext(0, envelope(0, 429, "slow down"));
        same(handler._rateLimitUntil, now + JsConstants.RATE_LIMIT_COOLDOWN_MS);
        send(request("new", {
            group: "u3"
        }));
        handler._pump();
        same(handler._activeCount, 0);
        same(handler._queue.length, 2, "other symbols cannot bypass the provider cooldown");
        now = handler._retryQueue[0].readyAt;
        handler._processRetryQueue();
        same(handler._retryQueue.length, 1, "even a ready retry respects the provider cooldown");
        advanceRetry();
        same(handler._retryQueue.length, 0);
        // Finish the two other calls, then simulate a second rate limit on the original retry.
        runNext(0, envelope(0, 200, wiseBody));
        runNext(0, envelope(0, 200, wiseBody));
        runNext(0, envelope(0, 429, "slow down"));
        same(handler._rateLimitUntil, now + 2 * JsConstants.RATE_LIMIT_COOLDOWN_MS, "repeated rate limits wait longer");
    }
    function test_retry_queue_is_bounded_and_deduplicated() {
        function job(key) {
            return {
                request: request(key),
                attempt: 1
            };
        }
        check(handler._scheduleRetry(job("a")));
        check(!handler._scheduleRetry(job("a")), "the same call is never queued twice");
        for (let i = 0; i < JsConstants.RETRY_QUEUE_MAX * 2; i++)
            handler._scheduleRetry(job("k" + i));
        same(handler._retryQueue.length, JsConstants.RETRY_QUEUE_MAX, "hard cap");
        check(!handler._scheduleRetry(job("extra")));
    }
    function test_server_errors_and_rate_limits_are_transient() {
        let statuses = [429, 500, 502, 503];
        for (let i = 0; i < statuses.length; i++) {
            setup();
            send(request("k", {
                command: ["bash", "-c", "same-command"]
            }));
            runNext(0, envelope(0, statuses[i], "x"));
            same(handler._retryQueue.length, 1, "HTTP " + statuses[i] + " is retried");
            advanceRetry();
            equal(handler._queue[0].request.command, ["bash", "-c", "same-command"], "the same request is repeated");
            same(handler._queue[0].attempt, 1);
        }
    }

    // Shared failures have one retry budget and keep all subscribers until the final result.
    function test_shared_calls_retry_once_together_and_accept_late_subscribers() {
        send(request("same"));
        send(request("same", {
            group: "u2"
        }));
        runNext(0, envelope(6, "000"));
        same(handler._retryQueue.length, 1);
        send(request("same", {
            group: "u3"
        }));
        same(handler._queue.length, 0, "joining a delayed retry must respect its backoff");
        advanceRetry();
        same(handler._queue.length, 1);
        runNext(0, envelope(0, 200, wiseBody));
        same(seen.finished.length, 3);
        equal(handler.pending, {});
        same(keyCount(), 0);
    }

    // Coalescing cannot bypass the memory bound by attaching unlimited logical callers to one transfer.
    function test_shared_subscribers_are_bounded_too() {
        for (let i = 0; i < JsConstants.FETCH_QUEUE_MAX; i++)
            check(send(request("same", {
                group: "symbol-" + i
            })));
        same(handler._queue.length, 1);
        throws(function () {
            send(request("same", {
                group: "overflow"
            }));
        }, "queue reached its limit");
        same(keyCount(), JsConstants.FETCH_QUEUE_MAX);
        runNext(0, envelope(0, 404, "unknown symbol"));
        same(seen.finished.length, JsConstants.FETCH_QUEUE_MAX, "all subscribers receive the final HTTP failure");
        check(seen.finished.every(function (result) {
            return !result.response.ok;
        }));
        equal(handler.pending, {});
        same(keyCount(), 0);
        same(Object.keys(handler._transfers).length, 0);
    }

    // Removing one subscriber must not discard the live subscriber's shared request.
    function test_shared_transfer_survives_removal_of_its_first_caller() {
        let obsolete = request("same");
        handler._submit(obsolete, obsolete.context, function () {
            return false;
        });
        let liveCall = request("same", {
            group: "u2"
        });
        handler._submit(liveCall, liveCall.context, function () {
            return true;
        });
        let job = handler._queue[0];
        check(handler._pruneJob(job));
        equal(handler.pending, {
            u2: 1
        });
        runNext(0, envelope(0, 200, wiseBody));
        same(seen.finished.length, 1);
        same(seen.finished[0].context.uid, "u2");
        equal(handler.pending, {});
    }

    // ── Submitting ───────────────────────────────────────────────────────────
    function test_submit_counts_pending_per_group_and_refuses_duplicates() {
        check(send(request()));
        same(handler._queue.length, 1);
        equal(handler.pending, {
            u1: 1
        });
        check(!send(request()), "the same call is never in flight twice");
        same(handler._queue.length, 1);
        check(send(request("u1_graph_url")), "a different call is separate");
        equal(handler.pending, {
            u1: 2
        });
        check(send(request("nogroup", {
            group: ""
        })), "a group is optional");
        equal(handler.pending, {
            u1: 2
        });
    }
    // ── Final response ───────────────────────────────────────────────────────
    function test_success_reports_one_final_response_with_the_callers_context() {
        send(request());
        runNext(0, envelope(0, 200, wiseBody));
        same(seen.finished.length, 1);
        let finished = seen.finished[0];
        same(finished.context.uid, "u1");
        same(finished.context.fetchType, "price");
        check(finished.response.ok);
        same(finished.response.status, 200);
        same(finished.response.body, wiseBody);
        equal(handler.pending, {});
        same(keyCount(), 0);
        check(send(request()), "the call is forgotten, so it can be submitted again");
        equal(seen.pendingChanges.map(function (pending) {
            return pending.u1 || 0;
        }), [1, 0, 1]);
    }

    // ── Development log (dev mode only, never a URL or credential) ───────────
    function test_the_handler_logs_its_work_in_dev_mode_without_urls_or_credentials() {
        let lines = [];
        Logger.configure({
            devMode: true,
            sink: function (level, scope, text) {
                lines.push(text);
            }
        });
        handler.properties.credential = "SECRET-KEY";
        send(request("https://x.test/?apikey=SECRET-KEY"));
        runNext(0, envelope(6, "000"));                          // transient: a retry
        advanceRetry();
        runNext(0, envelope(0, 200, wiseBody));
        let text = lines.join("\n");
        check(/queued BRLPLN price/.test(text), "queued");
        check(/retrying BRLPLN price/.test(text), "retry");
        check(/finished BRLPLN price: HTTP 200, 2 candles/.test(text), "result with the candle count");
        check(text.indexOf("SECRET-KEY") === -1 && text.indexOf("x.test") === -1, "no URL and no credential in the log");
    }

    // ── Retries ──────────────────────────────────────────────────────────────
    function test_transient_failure_is_retried_then_succeeds() {
        send(request());
        runNext(0, envelope(6, "000"), "curl: (6) Could not resolve host");
        same(seen.finished.length, 0, "a retry reports nothing yet");
        same(handler._retryQueue.length, 1);
        same(handler._retryQueue[0].attempt, 1);
        same(handler._activeCount, 0, "the failed attempt frees the slot");
        equal(handler.pending, {
            u1: 1
        });
        check(!send(request()), "cannot be submitted again meanwhile");
        advanceRetry();
        same(handler._retryQueue.length, 0);
        same(handler._queue.length, 1);
        runNext(0, envelope(0, 200, wiseBody));
        same(seen.finished.length, 1);
        check(seen.finished[0].response.ok);
        equal(handler.pending, {});
    }

    // ── Never throws, never stalls ───────────────────────────────────────────
    function test_unexpected_exceptions_become_failed_responses() {
        send(request("x"));
        handler.api = null;                                         // interpreting now throws a TypeError
        runNext(0, envelope(0, 200, "x"));
        same(seen.finished.length, 1);
        check(!seen.finished[0].response.ok);
        same(handler._activeCount, 0, "the slot is released");
        equal(handler.pending, {});
    }
}
