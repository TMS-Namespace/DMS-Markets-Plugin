import QtQuick
import "../../../../src/JS/Contracts/ChartSpan.js" as ChartSpan
import "../../../../src/JS/Contracts/PluginError.js" as PluginError
import "../../../../src/QML/Contracts"
import "../../../../src/QML/Helpers"
import "../../../../src/QML/Services"
import "../../../Helpers"

TestSuite {
    id: suite

    property Component contextType: Component {
        FetchContext {
        }
    }
    readonly property real day: 86400000
    property var fetcher: null
    property Component fetcherType: Component {
        MarketDataFetcher {
        }
    }
    readonly property var fine: ({
            uid: "u-fine",
            ticker: "EURUSD=X",
            provider: "yahoo",
            priceResolution: "1m",
            chartResolution: "1h",
            chartRange: "1D"
        })
    readonly property real hour: 3600000
    readonly property string live: JSON.stringify([
        {
            value: 2,
            time: Date.UTC(2026, 0, 1, 10)
        },
        {
            value: 4,
            time: Date.UTC(2026, 0, 1, 11)
        }
    ])
    property var logs: []
    readonly property real minute: 60000
    property var received: ({})
    property Component responseType: Component {
        ProviderResponse {
        }
    }
    // ── Saved market data: what is kept, and what is taken back ──────────────
    readonly property string signature: "wise|BRLPLN|1h|1d|1d|1M|false"
    property var toasts: []
    readonly property var wise: ({
            uid: "u-wise",
            ticker: "BRLPLN",
            provider: "wise",
            priceResolution: "1h",
            chartResolution: "1d",
            chartRange: "1M"
        })

    function context(fetchType, uid) {
        return (contextType.createObject(null, {
                uid: uid || "u-wise",
                ticker: "BRLPLN",
                providerId: "wise",
                fetchType: fetchType || "price",
                chartRange: "1M",
                chartResolution: "1d"
            }) as FetchContext);
    }
    function failed(error) {
        return (responseType.createObject(null, {
                providerId: "wise",
                ok: false,
                error: error
            }) as ProviderResponse);
    }
    function make(symbols, times) {
        if (fetcher)
            fetcher.destroy();
        fetcher = (fetcherType.createObject(null, {
                symbols: symbols,
                lastFetchTimes: times || ({})
            }) as MarketDataFetcher);
        fetcher.priceDataReady.connect(function (priceData) {
            received.price = priceData;
        });
        fetcher.graphDataReady.connect(function (graphData) {
            received.graph = graphData;
        });
        fetcher.fetchTimesUpdated.connect(function (times) {
            received.times = times;
        });
        fetcher.refreshedTimesUpdated.connect(function (times) {
            received.refreshed = times;
        });
        fetcher.symbolStored.connect(function (uid) {
            received.stored.push(uid);
        });
        fetcher.symbolErrorChanged.connect(function (uid, type, record) {
            received.status.push([uid, type, record]);
        });
        fetcher.pendingFetchesUpdated.connect(function (pending) {
            received.pending.push(Object.assign({}, pending));
        });
    }
    function ok(body) {
        return (responseType.createObject(null, {
                providerId: "wise",
                ok: true,
                status: 200,
                body: body
            }) as ProviderResponse);
    }
    // Price and chart pulls only (the change pull has its own tests).
    function pulled(symbols, times) {
        return pulledAll(symbols, times).filter(function (key) {
            return key.slice(-7) !== "_change";
        });
    }

    // ── Scheduling: price and chart each refresh at their own resolution ─────
    // `_checkAndFetch` pulls what is due and stamps it with `now`: a stamp newer than before = pulled.
    function pulledAll(symbols, times) {
        make(symbols, times);
        fetcher._checkAndFetch();
        let result = [];
        for (let key in received.times)
            if (received.times[key] !== (times[key] || 0))
                result.push(key);
        return result.sort();
    }
    function respond(fetchContext, response, limit) {
        let series = null;
        if (response.ok) {
            try {
                series = seriesOf(fetchContext.providerId, fetchContext.fetchType, response, limit);
            } catch (error) {
                response = failed(error);
            }
        }
        fetcher._onResponse(fetchContext, response, series);
    }
    function rows(values, step, start) {
        return JSON.stringify(values.map(function (value, i) {
            return {
                value: value,
                time: (start || Date.UTC(2026, 0, 1)) + i * step
            };
        }));
    }
    function savedRecord(extra) {
        return Object.assign({
            signature: signature,
            price: {
                open: 1,
                high: 3,
                low: 1,
                close: 2,
                date: "2026-01-02",
                time: "10:00:00",
                change: 1,
                changePercent: 100
            },
            reference: 1,
            graph: [
                {
                    date: "2026-01-01",
                    time: "",
                    open: 1,
                    high: 2,
                    low: 0.5,
                    close: 1.5,
                    volume: 0
                },
                {
                    date: "2026-01-02",
                    time: "",
                    open: 1.5,
                    high: 2,
                    low: 1,
                    close: 2,
                    volume: 3
                }
            ],
            refreshedAt: {
                price: 5000,
                change: 6000,
                graph: 7000
            }
        }, extra || {});
    }
    // What ProviderHandler hands over: the newest `limit` candles of a successful answer; an unreadable
    // answer arrives as a failed response instead.
    function seriesOf(providerId, fetchType, response, limit) {
        let handler = ProvidersManager.requireFromId(providerId);
        if (fetchType === "change")
            return handler.parseChange(response);
        return fetchType === "price" ? handler.parsePrice(response, limit) : handler.parseChart(response, limit);
    }
    function setup() {
        if (fetcher)
            fetcher.destroy();
        ProvidersManager.reload(ProvidersManager.sources);          // fresh handlers: no queued calls leak between tests
        ErrorHandler.reset();
        toasts = [];
        logs = [];
        Logger.configure({
            devMode: false,
            sink: function (level, scope, text) {
                logs.push([level, scope, text]);
            }
        });
        ErrorHandler.configure({
            notify: function (message, details, category) {
                toasts.push({
                    message: message,
                    details: details,
                    category: category
                });
            }
        });
        received = {
            price: null,
            graph: null,
            times: null,
            refreshed: null,
            stored: [],
            status: [],
            pending: []
        };
        make([wise,
            {
                uid: "u2",
                ticker: "EURUSD=X",
                provider: "yahoo",
                invert: true,
                priceResolution: "1h",
                chartResolution: "1d",
                chartRange: "1M"
            },
            {
                uid: "u1",
                ticker: "BRLPLN",
                provider: "wise"
            }
        ]);
    }
    function store(uid, fetchType, response, limit) {
        fetcher._store(uid, "wise", fetchType, seriesOf("wise", fetchType, response, limit));
    }
    function test_a_disabled_provider_reports_why() {
        fetcher.doFetch({
            uid: "u-stooq",
            ticker: "eurusd",
            provider: "stooq",
            priceResolution: "1d",
            chartResolution: "1d",
            chartRange: "1M"
        }, "price");
        same(received.status[0][2].code, "unsupported");
        same(received.status[0][2].userMessage, "Stooq is currently disabled.");
    }
    function test_a_failed_change_pull_is_not_shown_on_the_card() {
        fetcher._reportSymbolError("u1", "change", new Error("boom"));
        same(received.status.length, 0, "the price still shows with its own change; the card stays clean");
    }
    function test_a_failed_pull_is_not_worth_saving() {
        fetcher._onResponse(context("price"), failed(new PluginError.PluginError(PluginError.Code.HTTP, "x", "y")), null);
        equal(received.stored, []);
        same(received.refreshed, null);
    }
    function test_a_saved_record_is_restored_with_when_it_was_fetched() {
        check(fetcher.restore("u1", savedRecord(), signature));
        same(received.price.u1.close, 2);
        same(received.price.u1.change, 1);
        same(received.graph.u1.length, 2);
        same(received.graph.u1[1].volume, 3);
        same(received.refreshed["u1_price"], 5000);
        same(received.refreshed["u1_change"], 6000);
        same(received.refreshed["u1_graph"], 7000);
        same(fetcher._references["u1"], 1, "the change reference comes back too");
        same(received.stored.length, 0, "restoring is not new data: nothing to save");
        same(received.status.length, 0, "and no error state is touched");
    }
    function test_a_stored_result_is_reported_as_worth_saving_and_stamps_when_it_succeeded() {
        store("u1", "price", ok(live));
        equal(received.stored, ["u1"], "the symbol has new data to save");
        check(received.refreshed["u1_price"] > 0, "the time of the success is published");
        store("u1", "graph", ok(rows([1, 2, 3], day)));
        check(received.refreshed["u1_graph"] > 0);
        equal(received.stored, ["u1", "u1"]);
    }

    // ── doFetch ──────────────────────────────────────────────────────────────
    function test_a_valid_request_is_submitted_keyed_by_uid() {
        fetcher.doFetch(wise, "price");
        equal(received.pending.pop(), {
            "u-wise": 1
        }, "one call, grouped by uid");
        same(received.status.length, 0);
    }
    function test_an_inverted_symbols_reference_is_inverted_too() {
        store("u2", "price", ok(live));
        fetcher.priceData = received.price;
        store("u2", "change", ok(rows([1, 3], hour)));                      // reference 1 → 1/1; the price is 1/4
        near(received.price.u2.change, 0.25 - 1, 1e-9);
    }
    function test_cadences_are_independent() {
        let now = Date.now();
        equal(pulled([fine], {
            "u-fine_price": now - minute,
            "u-fine_graph": now - minute
        }), ["u-fine_price"], "a 1m price over a 1h chart");
        equal(pulled([fine], {
            "u-fine_price": now - hour,
            "u-fine_graph": now - hour
        }), ["u-fine_graph", "u-fine_price"]);
        let slow = {
            uid: "u-slow",
            ticker: "EURUSD=X",
            provider: "yahoo",
            priceResolution: "1d",
            chartResolution: "15m",
            chartRange: "1D"
        };
        equal(pulled([slow], {
            "u-slow_price": now - 15 * minute,
            "u-slow_graph": now - 15 * minute
        }), ["u-slow_graph"], "a 15m chart refreshes while a daily price waits");
    }
    function test_chart_holds_exactly_the_window_it_asked_for_and_is_stamped() {
        let values = [];
        for (let i = 0; i < 80; i++)
            values.push(1 + i / 100);
        store("u1", "graph", ok(rows(values, day)), ChartSpan.pointLimit("1d", "1M"));
        same(received.graph.u1.length, ChartSpan.pointLimit("1d", "1M"), "only the candles the window needs were processed");
        same(received.graph.u1[received.graph.u1.length - 1].close, 1.79, "the newest candle is kept");
        same(typeof received.times["u1_graph"], "number");
    }
    function test_credential_problems_also_toast() {
        respond(context("price"), failed(new PluginError.PluginError("credential", "Wise refused access (HTTP 403).", "HTTP 403")));
        same(toasts.length, 1);
        check(toasts[0].message.indexOf("Wise refused access") !== -1);
        same(toasts[0].category, "markets-credential");
    }
    function test_data_saved_for_another_configuration_is_refused() {
        same(fetcher.restore("u1", savedRecord(), "wise|BRLPLN|1h|1d|1d|1Y|false"), false);
        same(fetcher.restore("u1", null, signature), false);
        same(received.price, null);
        same(received.graph, null);
        same(received.refreshed, null);
    }
    function test_dev_mode_logging_only_when_enabled() {
        Logger.configure({
            devMode: false
        });
        respond(context("price"), failed(new PluginError.PluginError("network", "Down.", "curl exit 6")));
        same(logs.length, 0, "no logging without devMode");
        Logger.configure({
            devMode: true
        });
        respond(context("price"), failed(new PluginError.PluginError("network", "Down.", "curl exit 6")));
        check(logs.some(function (entry) {
            return entry[0] === "error" && entry[1] === "fetcher" && /network/.test(entry[2]) && /BRLPLN price/.test(entry[2]) && /curl exit 6/.test(entry[2]);
        }));
    }
    function test_failed_responses_become_the_symbols_error() {
        let cases = [[new PluginError.PluginError("network", "Can't reach Wise. Check your internet connection.", "curl exit 6", {
                    retryable: true
                }), "network", "Can't reach Wise."], [new PluginError.PluginError("notFound", "Yahoo Finance: No data found, symbol may be delisted", "HTTP 404", {
                    status: 404
                }), "notFound", "No data found"], [new PluginError.PluginError("timeout", "Wise took too long to answer."), "timeout", "took too long"]];
        for (let i = 0; i < cases.length; i++) {
            setup();
            respond(context("graph"), failed(cases[i][0]));
            same(received.status.length, 1, cases[i][1] + ": reported once");
            same(received.status[0][0], "u-wise");
            same(received.status[0][1], "graph", "the error belongs to the pull that failed");
            same(received.status[0][2].code, cases[i][1]);
            check(received.status[0][2].userMessage.indexOf(cases[i][2]) !== -1);
            same(toasts.length, 0, "ordinary errors live on the card, not in a toast");
            same(ErrorHandler.recent.length, 1, "...but they are recorded");
            same(received.graph, null);
        }
    }
    function test_fetch_new_symbols_only_pulls_unknown_uids() {
        make([wise, fine], {
            keep: 1
        });
        fetcher.fetchNewSymbols([wise, fine], ["u-wise"]);
        check("u-fine_price" in received.times && "u-fine_graph" in received.times);
        check(!("u-wise_price" in received.times));
        same(received.times.keep, 1);
    }

    // ── Refresh entry points ─────────────────────────────────────────────────
    function test_force_refresh_pulls_both_only_for_known_uids() {
        fetcher.forceRefreshSymbol("u-wise");
        same(received.pending.length > 0, true);
        received.pending = [];
        fetcher.forceRefreshSymbol("unknown");
        same(received.pending.length, 0);
    }

    // A symbol removed during the initial stagger must release its queued graph and all scheduling keys.
    function test_forget_releases_staggered_requests_and_start_times() {
        fetcher.lastFetchTimes = {
            u1_price: 1,
            u1_change: 2,
            u1_graph: 3,
            u2_price: 4
        };
        fetcher._initialGraphQueue = [
            {
                uid: "u1"
            },
            {
                uid: "u2"
            }
        ];
        fetcher.forget("u1");
        equal(received.times, {
            u2_price: 4
        });
        equal(fetcher._initialGraphQueue.map(function (symbol) {
            return symbol.uid;
        }), ["u2"]);
    }
    function test_forgetting_a_symbol_drops_everything_held_for_it() {
        store("u1", "price", ok(live));
        fetcher.priceData = received.price;
        store("u1", "graph", ok(rows([1, 2, 3], day)), 3);
        fetcher.graphData = received.graph;
        store("u1", "change", ok(rows([1, 3], hour)));
        fetcher.refreshedTimes = received.refreshed;
        store("u2", "price", ok(live));
        fetcher.priceData = received.price;
        fetcher.refreshedTimes = received.refreshed;
        fetcher.forget("u1");
        same(received.price.u1, undefined);
        same(received.graph.u1, undefined);
        same(fetcher._references["u1"], undefined);
        same(received.refreshed["u1_price"], undefined);
        same(received.refreshed["u1_graph"], undefined);
        same(received.refreshed["u1_change"], undefined);
        check(received.price.u2 !== undefined && received.refreshed["u2_price"] !== undefined, "other symbols are untouched");
        doesNotThrow(function () {
            fetcher.forget("never-seen");
        });
    }

    // Restoring tomorrow's timestamps must never suppress requests indefinitely.
    function test_future_cache_timestamps_do_not_delay_requests() {
        fetcher.restore("u1", savedRecord({
            refreshedAt: {
                price: Date.now() + day,
                change: Date.now() + day,
                graph: Date.now() + day
            }
        }), signature);
        equal(received.times, {});
        equal(received.refreshed, {});
    }
    function test_inversion_edits_allow_a_replacement_request_with_the_same_url() {
        make([wise]);
        fetcher.doFetch(wise, "price");
        let handler = ProvidersManager.requireFromId("wise");
        let oldContext = handler._queue[0].request.context;
        let inverted = Object.assign({}, wise, {
            invert: true
        });
        fetcher.symbols = [inverted];
        fetcher.doFetch(inverted, "price");
        same(handler._queue.length, 1, "the replacement can use the same provider answer");
        same(handler._queue[0].listeners.length, 2, "both configurations keep separate delivery contexts");
        check(!fetcher._isLive(oldContext));
        check(fetcher._isLive(handler._queue[0].listeners[1].context));
        check(handler._pruneJob(handler._queue[0]));
        same(handler._queue[0].listeners.length, 1, "the obsolete configuration is dropped");
    }
    function test_inversion_is_looked_up_by_uid_and_keeps_candles_consistent() {
        store("u2", "price", ok(live));
        let price = received.price.u2;
        same(price.close, 0.25, "close inverted");
        same(price.open, 0.5, "open inverted");
        same(price.high, 0.5);
        same(price.low, 0.25);
        same(price.change, -0.25);
        check(price.high >= price.low && price.high >= price.open && price.high >= price.close && price.low <= price.open && price.low <= price.close);
        store("u2", "graph", ok(rows([2, 3, 4, 5], day)));
        check(received.graph.u2.every(function (candle) {
            return candle.high >= candle.low && candle.high >= Math.max(candle.open, candle.close) && candle.low <= Math.min(candle.open, candle.close);
        }));
    }

    // Bulk chart data stays plain and serializable rather than allocating a QObject for every candle.
    function test_live_and_restored_charts_use_plain_candles() {
        store("u1", "graph", ok(rows([1, 2, 3], day)), 3);
        same(typeof received.graph.u1[0].destroy, "undefined");
        equal(JSON.parse(JSON.stringify(received.graph.u1)), received.graph.u1);
        setup();
        fetcher.restore("u1", savedRecord(), signature);
        same(typeof received.graph.u1[0].destroy, "undefined");
        equal(JSON.parse(JSON.stringify(received.graph.u1)), received.graph.u1);
    }
    function test_never_fetched_pulls_both() {
        equal(pulled([wise], {}), ["u-wise_graph", "u-wise_price"]);
    }
    function test_nonsense_times_and_references_are_ignored() {
        fetcher.restore("u1", savedRecord({
            reference: "x",
            refreshedAt: {
                price: -5,
                change: "now",
                graph: 0
            }
        }), signature);
        same(fetcher._references["u1"], undefined);
        same(received.refreshed["u1_price"], undefined);
        same(received.refreshed["u1_graph"], undefined);
        setup();
        fetcher.restore("u1", savedRecord({
            reference: 0,
            refreshedAt: undefined
        }), signature);
        same(fetcher._references["u1"], undefined, "a zero reference would divide by zero");
        setup();
        check(!fetcher.restore("u1", {
            signature: signature,
            price: null,
            graph: null
        }, signature), "an empty record restores nothing");
    }
    function test_nothing_is_due_before_a_resolution_elapses() {
        let now = Date.now();
        let times = {
            "u-wise_price": now - 59 * minute,
            "u-wise_graph": now - 59 * minute
        };
        equal(pulled([wise], times), []);
        times = {
            "u-wise_price": now - hour,
            "u-wise_graph": now - hour
        };
        equal(pulled([wise], times), ["u-wise_price"], "hourly price is due after an hour, the daily chart is not");
        times = {
            "u-wise_price": now - day,
            "u-wise_graph": now - day
        };
        equal(pulled([wise], times), ["u-wise_graph", "u-wise_price"], "the daily chart is due after a day");
    }
    function test_old_saved_ranges_are_clamped_before_scheduling() {
        let selection = fetcher._selectionFor({
            provider: "wise",
            priceResolution: "5m",
            chartRange: "10Y"
        });
        same(selection.priceResolution, "1h");
    }
    function test_only_the_valid_parts_of_a_record_are_used() {
        let badPrices = [null, "x",
            {},
            {
                open: 1,
                high: 1,
                low: 1,
                close: "2",
                date: "d",
                time: "t",
                change: 0,
                changePercent: 0
            },
            {
                open: 1,
                high: 1,
                low: 1,
                close: -1,
                date: "d",
                time: "t",
                change: 0,
                changePercent: 0
            },
            {
                open: 1,
                high: 1,
                low: 1,
                close: NaN,
                date: "d",
                time: "t",
                change: 0,
                changePercent: 0
            },
            {
                open: 1,
                high: 1,
                low: 1,
                close: 2,
                date: 5,
                time: "t",
                change: 0,
                changePercent: 0
            }
        ];
        badPrices.forEach(function (price, index) {
            setup();
            fetcher.restore("u1", savedRecord({
                price: price
            }), signature);
            same(received.price, null, "bad price #" + index + " is not shown");
            same(received.graph.u1.length, 2, "…the good chart still is");
        });
        let badCharts = [null, [], "x", [
                {}
            ], [
                {
                    date: "2026-01-01",
                    time: "",
                    open: 1,
                    high: 1,
                    low: 1,
                    close: "1",
                    volume: 0
                }
            ], [
                {
                    date: "yesterday",
                    time: "",
                    open: 1,
                    high: 1,
                    low: 1,
                    close: 1,
                    volume: 0
                }
            ], [
                {
                    date: "2026-01-01",
                    time: "late",
                    open: 1,
                    high: 1,
                    low: 1,
                    close: 1,
                    volume: 0
                }
            ], [null]];
        badCharts.forEach(function (graph, index) {
            setup();
            fetcher.restore("u1", savedRecord({
                graph: graph
            }), signature);
            same(received.graph, null, "bad chart #" + index + " is not shown");
            same(received.price.u1.close, 2, "…the good price still is");
        });
    }

    // ── Storing a successful response ────────────────────────────────────────
    function test_price_is_stored_under_the_uid_as_a_price_info() {
        store("u1", "price", ok(live));
        same(received.price.u1.close, 4);
        same(received.price.u1.open, 2);
        same(received.price.u1.change, 2);
        same(received.price.u1.changePercent, 100);
        same(typeof received.times["u1_price"], "number");
        same(received.price.BRLPLN, undefined, "never keyed by the ticker");
        equal(received.status, [["u1", "price", null]], "success clears the error for that pull");
    }
    function test_removed_symbols_do_not_receive_other_widgets_responses() {
        fetcher.doFetch(wise, "price");
        let callContext = ProvidersManager.requireFromId("wise")._queue[0].request.context;
        fetcher.symbols = [];
        respond(callContext, ok(live), 2);
        same(received.price, null);
        same(received.stored.length, 0);
    }
    function test_requests_that_cannot_be_made_are_reported_for_the_card() {
        let bads = ["BRL PLN; rm -rf /", "", "$(id)"];
        for (let i = 0; i < bads.length; i++) {
            setup();
            fetcher.doFetch({
                uid: "u-wise",
                ticker: bads[i],
                provider: "wise",
                priceResolution: "1h",
                chartResolution: "1d",
                chartRange: "1M"
            }, "price");
            same(received.pending.length, 0, "not submitted");
            same(received.status.length, 1, "reported, not swallowed");
            same(received.status[0][0], "u-wise");
            same(received.status[0][1], "price");
            same(received.status[0][2].code, "invalidSymbol");
        }
    }
    function test_responses_for_edited_symbols_are_ignored() {
        let original = Object.assign({}, wise);
        make([original]);
        fetcher.doFetch(original, "price");
        let handler = ProvidersManager.requireFromId("wise");
        let oldContext = handler._queue[0].request.context;
        fetcher.symbols = [Object.assign({}, original, {
                ticker: "EURUSD"
            })];
        check(!fetcher._isLive(oldContext), "a request for the previous ticker is obsolete");
        respond(oldContext, ok(live), 2);
        same(received.price, null, "an old success cannot replace the edited symbol's price");
        respond(oldContext, failed(new PluginError.PluginError("network", "old failure", "")));
        same(received.status.length, 0, "an old failure cannot mark the edited symbol as failed");
    }
    function test_restoring_never_throws_whatever_the_record_holds() {
        [undefined, 5, "text", [],
            {
                signature: signature,
                price: {
                    get close() {
                        throw new Error("boom");
                    }
                }
            }
        ].forEach(function (record) {
            doesNotThrow(function () {
                fetcher.restore("u1", record, signature);
            });
        });
    }
    function test_saved_data_never_replaces_newer_data() {
        store("u1", "price", ok(live));
        fetcher.priceData = received.price;
        store("u1", "graph", ok(rows([1, 2, 3], day)), 3);
        fetcher.graphData = received.graph;
        fetcher.refreshedTimes = received.refreshed;
        let freshTime = received.refreshed["u1_price"];
        same(fetcher.restore("u1", savedRecord(), signature), false);
        same(received.price.u1.close, 4, "the live price stays");
        same(received.graph.u1.length, 3, "the live chart stays");
        same(received.refreshed["u1_price"], freshTime, "and so does its time");
    }
    function test_starting_a_pull_does_not_claim_the_data_is_fresh() {
        // The schedule remembers when a pull was STARTED; "refreshed x min ago" must only follow successful answers.
        make([wise], {});
        fetcher._checkAndFetch();
        check(received.times["u-wise_price"] > 0, "the schedule knows the pull started");
        same(received.refreshed, null, "...but nothing is claimed to be refreshed");
        fetcher.startInitialFetches([wise]);
        same(received.refreshed, null);
    }

    // Cache freshness applies independently to each data type; unusable data cannot postpone a fetch.
    function test_startup_fetches_only_stale_or_invalid_cached_parts() {
        let now = Date.now();
        make([
            {
                uid: "u1",
                ticker: "BRLPLN",
                provider: "wise",
                priceResolution: "1h",
                changeResolution: "1d",
                chartResolution: "1d",
                chartRange: "1M"
            }
        ]);
        fetcher.restore("u1", savedRecord({
            graph: [
                {}
            ],
            refreshedAt: {
                price: now - 1000,
                change: now - 2 * hour,
                graph: now - 1000
            }
        }), signature);
        fetcher.lastFetchTimes = received.times;
        fetcher.startInitialFetches(fetcher.symbols);
        let handler = ProvidersManager.requireFromId("wise");
        same(handler._queue.length, 1, "only the stale change reference starts immediately");
        same(handler._queue[0].request.context.fetchType, "change");
        same(fetcher._initialGraphQueue.length, 1, "an invalid cached chart still needs a fetch");
        same(received.times.u1_price, now - 1000, "fresh price timestamp is preserved");
    }

    // ── The final response ───────────────────────────────────────────────────
    function test_successful_responses_are_stored_and_clear_the_error() {
        respond(context("price"), ok(live));
        same(received.price["u-wise"].close, 4);
        same(toasts.length, 0);
        equal(received.status.map(function (status) {
            return [status[0], status[1], status[2]];
        }), [["u-wise", "price", null]]);
    }
    function test_symbols_without_a_uid_are_not_fetched() {
        fetcher.doFetch({
            ticker: "BRLPLN",
            provider: "wise"
        }, "price");
        same(received.pending.length, 0);
        same(received.status.length, 0);
    }
    function test_symbols_without_uid_are_skipped_and_untouched_times_kept() {
        let now = Date.now();
        make([wise, fine,
            {
                ticker: "NOUID",
                provider: "yahoo"
            }
        ], {
            "u-wise_price": now,
            "u-wise_graph": now
        });
        fetcher._checkAndFetch();
        same(received.times["u-wise_price"], now, "fresh ones are left alone");
        check(received.times["u-fine_price"] > 0 && received.times["u-fine_graph"] > 0);
        check(Object.keys(received.times).every(function (key) {
            return key.indexOf("NOUID") === -1;
        }));
    }
    function test_the_change_is_pulled_on_its_own_cadence() {
        let now = Date.now();
        let symbol = {
            uid: "u-c",
            ticker: "BRLPLN",
            provider: "wise",
            priceResolution: "1h",
            changeResolution: "1d",
            chartResolution: "1d",
            chartRange: "1M"
        };
        let fresh = {
            "u-c_price": now,
            "u-c_graph": now,
            "u-c_change": now - 59 * minute
        };
        equal(pulledAll([symbol], fresh), [], "a daily change is re-read hourly, not before");
        fresh = {
            "u-c_price": now,
            "u-c_graph": now,
            "u-c_change": now - hour
        };
        equal(pulledAll([symbol], fresh), ["u-c_change"], "…and is due after an hour");
        equal(pulledAll([symbol], {}), ["u-c_change", "u-c_graph", "u-c_price"], "never fetched: all three");
    }
    // The change is measured against the provider's reference close (the previous period's), whichever answer arrives first.
    function test_the_change_uses_the_reference_in_either_arrival_order() {
        store("u1", "price", ok(live));
        same(received.price.u1.change, 2, "before the reference arrives: the candle's own change");
        fetcher.priceData = received.price;
        store("u1", "change", ok(rows([1, 3], hour)));                      // the previous period closed at 1
        same(received.price.u1.change, 3, "the price shown is re-measured when the reference arrives");
        same(received.price.u1.changePercent, 300);
        equal(received.status[received.status.length - 1], ["u1", "change", null]);
        store("u1", "price", ok(live));
        same(received.price.u1.change, 3, "and a later price keeps using it");
    }
    function test_the_restored_reference_is_used_by_the_next_price() {
        fetcher.restore("u1", savedRecord({
            reference: 2.5
        }), signature);
        store("u1", "price", ok(live));                                        // the live answer closes at 4
        same(received.price.u1.change, 1.5, "measured against the saved reference until a fresh one arrives");
    }
    function test_the_snapshot_is_plain_data_and_empty_for_a_symbol_without_data() {
        same(fetcher.snapshotOf("u1"), null);
        store("u1", "price", ok(live));
        fetcher.priceData = received.price;
        fetcher.refreshedTimes = received.refreshed;
        store("u1", "graph", ok(rows([1, 2, 3], day)), 3);
        fetcher.graphData = received.graph;
        fetcher.refreshedTimes = received.refreshed;
        store("u1", "change", ok(rows([1, 3], hour)));
        fetcher.refreshedTimes = received.refreshed;
        let snapshot = fetcher.snapshotOf("u1");
        let text = JSON.stringify(snapshot);                                  // plain data: it survives a round trip unchanged
        equal(JSON.parse(text), snapshot);
        same(snapshot.price.close, 4);
        same(snapshot.reference, 1);
        same(snapshot.graph.length, 3);
        equal(Object.keys(snapshot.price).sort(), ["changePercent", "change", "close", "date", "high", "low", "open", "time"].sort());
        equal(Object.keys(snapshot.graph[0]).sort(), ["close", "date", "high", "low", "open", "time", "volume"]);
        check(snapshot.refreshedAt.price > 0 && snapshot.refreshedAt.change > 0 && snapshot.refreshedAt.graph > 0, "when each pull succeeded");
    }
    function test_unexpected_errors_are_reported_without_leaking_internals() {
        respond(context("price", "u-wise"), ok(live));   // known symbol, fine
        received.status = [];
        respond((contextType.createObject(null, {
                uid: "u-wise",
                ticker: "X",
                providerId: "ghost",
                fetchType: "price",
                chartRange: "1M",
                chartResolution: "1d"
            }) as FetchContext), ok(live));
        same(received.status.length, 1);
        same(received.status[0][2].code, "unknownProvider");
    }
    function test_unreadable_and_empty_answers_show_on_the_card() {
        respond(context("price"), ok("not json"));
        same(received.status[0][2].code, "parse");
        same(received.status[0][2].userMessage, "Wise sent an answer that couldn't be understood.");
        respond(context("graph"), ok("[]"));
        same(received.status[1][2].code, "noData");
        same(received.status[1][2].userMessage, "Wise has no chart data for this symbol.");
        same(received.price, null);
        same(received.graph, null);
    }
    function test_unreadable_or_empty_answers_are_typed_errors() {
        throws(function () {
            store("u1", "graph", ok("not json"));
        }, "not valid JSON");
        throws(function () {
            store("u1", "price", ok("not json"));
        }, "not valid JSON");
        same(received.graph, null, "the chart data is left alone");
        let thrown = throws(function () {
            store("u1", "graph", ok("[]"));
        }, "");
        same(thrown.code, "noData");
        same(thrown.userMessage, "Wise has no chart data for this symbol.");
        thrown = throws(function () {
            store("u1", "price", ok("[]"));
        }, "");
        same(thrown.userMessage, "Wise has no price for this symbol.");
        throws(function () {
            store("u1", "price", failed(new PluginError.PluginError("network", "Down.")));
        }, "Down.", "a failure is never parsed as data");
    }
    function test_unsupported_resolutions_are_clamped_not_requested() {
        fetcher.doFetch({
            uid: "u-x",
            ticker: "BRLPLN",
            provider: "wise",
            priceResolution: "5m",
            chartResolution: "5m",
            chartRange: "10Y"
        }, "graph");
        same(received.status.length, 0, "clamped to what Wise serves");
        equal(received.pending.pop(), {
            "u-x": 1
        });
    }
}
