// The last market data of every symbol is kept on disk and shown right after a start, before any provider answers.
// The real widget (with the fake plugin service and the stand-in curl of the other widget tests) against a real cache
// directory: the saved data is shown first, fresh data replaces it and is saved in the background, a failed refresh
// keeps what is shown, data of a symbol whose settings changed is not reused, damaged files are a first run.
import QtQuick
import Quickshell
import "../../Helpers"
import "../../../src/QML/Services"

TestSuite {
    id: suite

    property Component serviceType: Component {
        QtObject {
            property var data: ({})
            function loadPluginData(id, key, fallback) { return key in data ? data[key] : fallback }
            function savePluginData(id, key, value) { var copy = Object.assign({}, data); copy[key] = value; data = copy }
        }
    }
    property var service: null
    property var widget: null
    property string directory: ""
    property var seen: []                                 // every change of the widget's prices: { uid: { close, refreshed } }

    readonly property string uidA: "aaaaaaaa-1111-4111-8111-111111111111"
    readonly property string uidB: "bbbbbbbb-2222-4222-8222-222222222222"
    readonly property real cachedClose: 4242
    readonly property real twoDaysAgo: Date.now() - 2 * 86400000

    function setup() {
        if (widget) { widget.destroy(); widget = null }
        ErrorHandler.reset(); Logger.configure({ devMode: false })
        ProvidersManager.reload(ProvidersManager.sources)
        directory = freshDirectory("widget-cache")
        seen = []
    }
    function teardown() { if (widget) { widget.destroy(); widget = null } }

    function symbol(uid, ticker, extra) {
        return Object.assign({ uid: uid, ticker: ticker, name: ticker, provider: "yahoo", priceResolution: "1h", changeResolution: "1d", chartResolution: "1d",
                               chartRange: "1M", showChangeWhenPinned: false, invert: false, pinned: false }, extra || {})
    }
    function signatureOf(s) { return [s.provider, s.ticker, s.priceResolution, s.changeResolution, s.chartResolution, s.chartRange, s.invert].join("|") }
    function recordOf(s, extra) {
        return Object.assign({ version: 1, uid: s.uid, savedAt: twoDaysAgo, signature: signatureOf(s),
            price: { open: cachedClose - 7, high: cachedClose + 1, low: cachedClose - 8, close: cachedClose, date: "2026-01-02", time: "10:00:00", change: 7, changePercent: 0.17 },
            reference: cachedClose - 7,
            graph: [{ date: "2026-01-01", time: "", open: 4200, high: 4250, low: 4190, close: 4230, volume: 0 }, { date: "2026-01-02", time: "", open: 4230, high: 4260, low: 4220, close: cachedClose, volume: 0 }],
            refreshedAt: { price: twoDaysAgo, change: twoDaysAgo, graph: twoDaysAgo } }, extra || {})
    }
    function seed(uid, text, done) { shell('mkdir -p -- "$1" && printf %s "$3" > "$1/$2.json"', [directory, uid, text], function() { done() }) }
    function seedRecord(s, extra, done) { seed(s.uid, JSON.stringify(recordOf(s, extra)), done) }
    function files(done) { shell('ls -1 -- "$1" 2>/dev/null | sort', [directory], function(code, text) { done(text.split("\n").filter(Boolean)) }) }
    function fileText(uid, done) { shell('cat -- "$1/$2.json"', [directory, uid], function(code, text) { done(text) }) }

    function start(symbols, extraData) {
        let data = Object.assign({ symbols: JSON.stringify(symbols) }, extraData || {})
        service = serviceType.createObject(null, { data: data })
        let component = Qt.createComponent("file://" + repoRoot + "/src/QML/Widget.qml")
        check(component.status === Component.Ready, component.errorString())
        widget = component.createObject(null, { pluginId: "markets", pluginService: service, pluginData: Qt.binding(function() { return service.data }),
                                                cacheDirectory: directory })
        check(widget !== null, "the widget was created")
        Logger.configure({ sink: function() {} })              // the widget turns dev logging on; the expected failures need not print
        // Watch what the card would show, in order: the first value of a symbol must be the saved one.
        widget.priceDataChanged.connect(function() {
            let now = {}
            Object.keys(widget.priceData).forEach(function(uid) {
                now[uid] = { close: widget.priceData[uid].close, refreshed: widget.refreshedTimes[uid + "_price"] }
            })
            seen.push(now)
        })
    }
    function firstSeen(uid) { for (let i = 0; i < seen.length; i++) if (seen[i][uid]) return seen[i][uid]; return null }
    function priceOf(uid) { return widget.priceData[uid] ? widget.priceData[uid].close : null }
    function freshPrice(uid) { return widget.priceData[uid] !== undefined && widget.priceData[uid].close !== cachedClose }
    function everythingOnDisk() { return widget.marketCache.busy === 0 && Object.keys(widget.marketCache._dirty).length === 0 }
    function describe() {
        return "prices " + JSON.stringify(Object.keys(widget.priceData).map(function(uid) { return widget.priceData[uid].close })) + ", errors " + Object.keys(widget.symbolErrors).length
               + ", busy " + widget.marketCache.busy + ", dirty " + Object.keys(widget.marketCache._dirty).length
    }

    // ── Where it lives ───────────────────────────────────────────────────────
    function test_by_default_the_data_lives_in_the_users_cache_directory() {
        let cache = (Qt.createComponent("file://" + repoRoot + "/src/QML/Services/MarketCache.qml").createObject(null) as MarketCache)
        same(cache.defaultDirectory, Quickshell.env("XDG_CACHE_HOME") + "/dms-markets-plugin")
        same(cache.directory, cache.defaultDirectory)
        cache.destroy()
    }

    // ── Saved data first, fresh data after ───────────────────────────────────
    // A reload with fresh, matching cached data must not spend any public API requests.
    function async_fresh_cache_avoids_startup_requests_but_manual_refresh_still_fetches(done) {
        let savedSymbol = symbol(uidA, "EURUSD=X")
        let timestamp = Date.now() - 60000
        seedRecord(savedSymbol, { refreshedAt: { price: timestamp, change: timestamp, graph: timestamp } }, function() {
            start([savedSymbol])
            let started = []
            Logger.configure({ devMode: true, sink: function(level, scope, text) {
                if (scope === "providers" && text.indexOf("started ") !== -1) started.push(text)
            } })
            waitUntil(function() { return widget.lastFetchTimes[uidA + "_graph"] === timestamp }, function(problem) {
                if (problem) { done(problem); return }
                // Allow both the symbol watcher and initial graph delay to run before checking request counts.
                waitUntil(function() { return false }, function() {
                    try {
                        equal(started, [], "fresh cache starts zero API processes")
                        same(priceOf(uidA), cachedClose)
                        same(widget.refreshedTimes[uidA + "_price"], timestamp)
                        same(widget.graphData[uidA].length, 2)
                        let fetcher = widget.children.filter(function(child) { return typeof child.forceRefreshAll === "function" })[0]
                        check(!!fetcher)
                        fetcher.forceRefreshAll()
                        waitUntil(function() { return freshPrice(uidA) }, function(refreshProblem) {
                            done(refreshProblem || (started.length > 0 ? "" : "manual refresh did not start a request"))
                        }, 10000, describe)
                    } catch (error) { done(error.message) }
                }, 700)
            }, 10000, describe)
        })
    }

    function async_saved_data_is_shown_first_then_replaced_by_what_the_provider_answers(done) {
        let s = symbol(uidA, "EURUSD=X")
        seedRecord(s, {}, function() {
            start([s])
            waitUntil(function() { return freshPrice(uidA) && widget.graphData[uidA] !== undefined && everythingOnDisk() }, function(problem) {
                if (problem) { done(problem); return }
                let first = firstSeen(uidA), problems = []
                if (!first || first.close !== cachedClose) problems.push("the first thing shown was " + JSON.stringify(first) + ", not the saved price")
                if (!first || Math.abs(first.refreshed - twoDaysAgo) > 1) problems.push("the saved time of the fetch is not shown with it: " + (first && first.refreshed))
                if (widget.refreshedTimes[uidA + "_price"] <= twoDaysAgo) problems.push("refreshed time not updated by the fresh answer")
                if (Object.keys(widget.symbolErrors).length) problems.push("an error is shown")
                done(problems.join("; "))
            }, 15000, describe)
        })
    }
    function async_the_saved_chart_and_reference_are_restored_too(done) {
        let s = symbol(uidA, "EURUSD=X")
        seedRecord(s, {}, function() {
            start([s])
            waitUntil(function() { return widget.priceData[uidA] !== undefined }, function(problem) {
                if (problem) { done(problem); return }
                let chart = widget.graphData[uidA]
                let problems = []
                if (!chart || chart.length !== 2 || chart[1].close !== cachedClose) problems.push("chart " + JSON.stringify(chart && chart.length))
                if (widget.priceData[uidA].change !== 7) problems.push("change " + widget.priceData[uidA].change)
                done(problems.join("; "))
            }, 15000, describe)
        })
    }
    function async_fresh_data_is_saved_in_the_background_and_only_the_latest_stays(done) {
        let s = symbol(uidA, "EURUSD=X")
        let begun = Date.now()
        seedRecord(s, {}, function() {
            start([s])
            waitUntil(function() { return freshPrice(uidA) && widget.graphData[uidA] !== undefined && everythingOnDisk() }, function(problem) {
                if (problem) { done(problem); return }
                files(function(names) {
                    fileText(uidA, function(text) {
                        let saved = JSON.parse(text), problems = []
                        if (names.join() !== uidA + ".json") problems.push("files " + names)
                        if (saved.price.close !== widget.priceData[uidA].close) problems.push("the file has " + saved.price.close + ", the card shows " + widget.priceData[uidA].close)
                        if (!(saved.refreshedAt.price >= begun)) problems.push("it does not say when it was fetched")
                        if (saved.signature !== signatureOf(s)) problems.push("signature " + saved.signature)
                        if (saved.graph.length < 2 || saved.graph[saved.graph.length - 1].close !== widget.graphData[uidA][saved.graph.length - 1].close) problems.push("chart not saved")
                        done(problems.join("; "))
                    })
                })
            }, 15000, describe)
        })
    }
    function async_a_first_run_saves_its_data_too(done) {
        let s = symbol(uidA, "EURUSD=X")
        start([s])
        waitUntil(function() { return freshPrice(uidA) && widget.graphData[uidA] !== undefined && everythingOnDisk() }, function(problem) {
            if (problem) { done(problem); return }
            files(function(names) { done(names.join() === uidA + ".json" ? "" : "files " + names) })
        }, 15000, describe)
    }

    // ── A refresh that fails keeps what is shown and saved ───────────────────
    function async_a_failed_refresh_keeps_the_saved_data_on_screen_and_on_disk(done) {
        let s = symbol(uidA, "NOPE=X")                       // the stand-in curl answers "No data found" for it
        seedRecord(s, {}, function() {
            start([s])
            waitUntil(function() { return widget.symbolErrors[uidA] !== undefined && widget.symbolErrors[uidA].price !== undefined }, function(problem) {
                if (problem) { done(problem); return }
                let problems = []
                if (priceOf(uidA) !== cachedClose) problems.push("the price on screen is " + priceOf(uidA))
                if (!widget.graphData[uidA] || widget.graphData[uidA].length !== 2) problems.push("the chart was lost")
                if (Math.abs(widget.refreshedTimes[uidA + "_price"] - twoDaysAgo) > 1) problems.push("the refreshed time was changed by a failure")
                waitUntil(function() { return everythingOnDisk() }, function(problem2) {
                    fileText(uidA, function(text) {
                        let saved = JSON.parse(text)
                        if (saved.price.close !== cachedClose || Math.abs(saved.refreshedAt.price - twoDaysAgo) > 1) problems.push("the saved file was overwritten by a failure")
                        done(problem2 || problems.join("; "))
                    })
                }, 5000, describe)
            }, 15000, describe)
        })
    }

    // ── What must not be reused ──────────────────────────────────────────────
    function async_data_saved_for_other_settings_of_the_symbol_is_not_shown(done) {
        let s = symbol(uidA, "EURUSD=X")
        seedRecord(s, { signature: signatureOf(symbol(uidA, "EURUSD=X", { chartRange: "1Y" })) }, function() {   // saved while the chart range was 1Y
            start([s])
            waitUntil(function() { return freshPrice(uidA) && widget.graphData[uidA] !== undefined }, function(problem) {
                if (problem) { done(problem); return }
                let shownAtAnyTime = seen.some(function(snapshot) { return snapshot[uidA] && snapshot[uidA].close === cachedClose })
                done(shownAtAnyTime ? "stale data of another configuration was shown" : "")
            }, 15000, describe)
        })
    }
    function async_inverted_and_not_inverted_data_are_never_mixed(done) {
        let s = symbol(uidA, "EURUSD=X", { invert: true })
        seedRecord(s, { signature: signatureOf(symbol(uidA, "EURUSD=X", { invert: false })) }, function() {
            start([s])
            waitUntil(function() { return freshPrice(uidA) }, function(problem) {
                done(problem || (seen.some(function(snapshot) { return snapshot[uidA] && snapshot[uidA].close === cachedClose }) ? "the other inversion's data was shown" : ""))
            }, 15000, describe)
        })
    }
    function async_damaged_files_are_a_first_run_not_an_error(done) {
        let s = symbol(uidA, "EURUSD=X")
        seed(uidA, "{ this is not json", function() {
            start([s])
            waitUntil(function() { return freshPrice(uidA) && widget.graphData[uidA] !== undefined && everythingOnDisk() }, function(problem) {
                if (problem) { done(problem); return }
                let problems = []
                if (Object.keys(widget.symbolErrors).length) problems.push("an error is shown")
                if (ErrorHandler.recent.length) problems.push("an error was recorded: " + JSON.stringify(ErrorHandler.recent[0]))
                fileText(uidA, function(text) { done(problems.concat(JSON.parse(text).price ? [] : ["the damaged file was not replaced"]).join("; ")) })
            }, 15000, describe)
        })
    }
    function async_saved_values_that_make_no_sense_are_ignored_piece_by_piece(done) {
        let s = symbol(uidA, "EURUSD=X")
        // A good chart with a nonsense price: the chart may be used, the price must not.
        seedRecord(s, { price: { open: "x", high: 1, low: 1, close: -5, date: "d", time: "t", change: 0, changePercent: 0 } }, function() {
            start([s])
            waitUntil(function() { return widget.graphData[uidA] !== undefined }, function(problem) {
                if (problem) { done(problem); return }
                done(seen.some(function(snapshot) { return snapshot[uidA] && snapshot[uidA].close === -5 }) ? "a nonsense price was shown" : "")
            }, 15000, describe)
        })
    }

    // ── Symbols arriving late, and removed ones ──────────────────────────────
    function async_symbols_delivered_after_the_start_show_their_saved_data_too(done) {
        let s = symbol(uidA, "EURUSD=X")
        seedRecord(s, {}, function() {
            start([])                                          // DMS starts the widget with no data and delivers it a moment later
            service.data = Object.assign({}, service.data, { symbols: JSON.stringify([s]) })
            waitUntil(function() { return freshPrice(uidA) && everythingOnDisk() }, function(problem) {
                let first = firstSeen(uidA)
                done(problem || (first && first.close === cachedClose ? "" : "the first thing shown was " + JSON.stringify(first)))
            }, 15000, describe)
        })
    }
    function async_a_removed_symbols_file_is_deleted_and_the_others_stay(done) {
        let a = symbol(uidA, "EURUSD=X"), b = symbol(uidB, "HG=F")
        seedRecord(a, {}, function() {
            seedRecord(b, {}, function() {
                start([a, b])
                waitUntil(function() { return freshPrice(uidA) && freshPrice(uidB) && everythingOnDisk() }, function(problem) {
                    if (problem) { done(problem); return }
                    service.data = Object.assign({}, service.data, { symbols: JSON.stringify([a]) })
                    waitUntil(function() {
                        return widget.symbols.length === 1 && widget.marketCache.busy === 0
                    }, function(problem2) {
                        // the removal is noticed by the symbol watcher after its delay
                        waitUntil(function() { return false }, function() {
                            files(function(names) {
                                try {
                                    check(!widget.priceData[uidB] && !widget.graphData[uidB], "removed market data is released")
                                    check(!widget.lastFetchTimes[uidB + "_price"] && !widget.refreshedTimes[uidB + "_graph"], "removed scheduling state is released")
                                    check(!widget.symbolErrors[uidB], "removed errors are released")
                                    check(!!widget.priceData[uidA] && !!widget.graphData[uidA], "other symbols remain loaded")
                                    done(problem2 || (names.join() === uidA + ".json" ? "" : "files " + names))
                                } catch (error) { done(error.message) }
                            })
                        }, 1500)
                    }, 10000, describe)
                }, 15000, describe)
            })
        })
    }
    function async_removing_the_last_symbol_deletes_its_file_too(done) {
        let s = symbol(uidA, "EURUSD=X")
        seedRecord(s, {}, function() {
            start([s])
            waitUntil(function() { return freshPrice(uidA) && widget.graphData[uidA] !== undefined && everythingOnDisk() }, function(problem) {
                if (problem) { done(problem); return }
                service.data = Object.assign({}, service.data, { symbols: JSON.stringify([]) })
                waitUntil(function() { return false }, function() {
                    waitUntil(function() { return widget.marketCache.busy === 0 }, function() {
                        files(function(names) {
                            try {
                                equal(widget.priceData, {}); equal(widget.graphData, {})
                                equal(widget.lastFetchTimes, {}); equal(widget.refreshedTimes, {})
                                equal(widget.symbolErrors, {})
                                done(names.length === 0 ? "" : "left behind: " + names)
                            } catch (error) { done(error.message) }
                        })
                    }, 3000)
                }, 1500)
            }, 15000, describe)
        })
    }
    function async_changing_a_symbols_settings_drops_the_shown_and_saved_data_until_the_new_answer(done) {
        let s = symbol(uidA, "NOPE=X")                  // never answers with data, so nothing can fill the gap
        seedRecord(s, {}, function() {
            start([s])
            waitUntil(function() { return priceOf(uidA) === cachedClose }, function(problem) {
                if (problem) { done(problem); return }
                let changed = symbol(uidA, "NOPE=X", { chartRange: "1Y" })
                service.data = Object.assign({}, service.data, { symbols: JSON.stringify([changed]) })
                waitUntil(function() { return widget.priceData[uidA] === undefined && widget.graphData[uidA] === undefined && widget.marketCache.busy === 0 }, function(problem2) {
                    if (problem2) { done(problem2); return }
                    files(function(names) {
                        done(names.length === 0 && widget.refreshedTimes[uidA + "_price"] === undefined ? "" : "left: files " + names + ", refreshed " + widget.refreshedTimes[uidA + "_price"])
                    })
                }, 8000, describe)
            }, 15000, describe)
        })
    }
    function async_changed_settings_then_save_the_fresh_data_under_the_new_signature(done) {
        let s = symbol(uidA, "EURUSD=X")
        seedRecord(s, {}, function() {
            start([s])
            waitUntil(function() { return freshPrice(uidA) && widget.graphData[uidA] !== undefined && everythingOnDisk() }, function(problem) {
                if (problem) { done(problem); return }
                let changed = symbol(uidA, "EURUSD=X", { invert: true })
                service.data = Object.assign({}, service.data, { symbols: JSON.stringify([changed]) })
                waitUntil(function() { return widget.symbols[0].invert === true && freshPrice(uidA) && widget.graphData[uidA] !== undefined && everythingOnDisk() }, function(problem2) {
                    if (problem2) { done(problem2); return }
                    waitUntil(function() { return false }, function() {
                        waitUntil(everythingOnDisk, function() {
                            fileText(uidA, function(text) {
                                done(JSON.parse(text).signature === signatureOf(changed) ? "" : "the file has " + JSON.parse(text).signature)
                            })
                        }, 5000)
                    }, 1200)
                }, 15000, function() { return describe() + ", invert " + widget.symbols[0].invert })
            }, 6000, describe)
        })
    }
    function async_an_empty_list_never_deletes_anything(done) {
        // DMS starts widgets with an empty symbol list; that must not be taken for "the user removed everything".
        let s = symbol(uidA, "EURUSD=X")
        seedRecord(s, {}, function() {
            start([])
            waitUntil(function() { return false }, function() {
                files(function(names) { done(names.join() === uidA + ".json" ? "" : "files " + names) })
            }, 1500)
        })
    }
    function async_an_edit_during_cache_loading_cannot_restore_the_old_configuration(done) {
        let original = symbol(uidA, "EURUSD=X")
        seedRecord(original, {}, function() {
            start([])
            widget.symbols = [original]
            widget._restoreThen([original], function() {
                done(priceOf(uidA) === null ? "" : "cached data for the old ticker was restored after an edit")
            })
            widget.symbols = [symbol(uidA, "HG=F")]
        })
    }

}
