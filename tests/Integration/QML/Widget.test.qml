// The real widget and settings page, loaded the way DMS loads them (against stand-ins for DMS's own qs.* modules and
// a fake plugin service that, like DMS, delivers plugin data again after every save), with saved symbols in the
// current and in older formats. curl is a stand-in (tests/Helpers/FakeBin), so the whole path runs: migration, fetching
// through the provider handlers, parsing, storing. This is what a unit test of one file cannot see.
import QtQuick
import "../../../src/QML/Services"
import "../../Helpers"

TestSuite {
    id: suite

    readonly property var currentSymbols: [
        {
            uid: "11111111-1111-4111-8111-111111111111",
            ticker: "EURUSD=X",
            name: "EUR/USD",
            provider: "yahoo",
            priceResolution: "1h",
            changeResolution: "1d",
            chartResolution: "1d",
            chartRange: "1M",
            showChangeWhenPinned: false,
            invert: false,
            pinned: false
        },
        {
            uid: "22222222-2222-4222-8222-222222222222",
            ticker: "BRLPLN",
            name: "BRL/PLN",
            provider: "wise",
            priceResolution: "1h",
            changeResolution: "1d",
            chartResolution: "1d",
            chartRange: "1M",
            showChangeWhenPinned: false,
            invert: true,
            pinned: true
        }
    ]
    readonly property var legacySymbols: [
        {
            id: "EURUSD=X",
            name: "EUR/USD",
            provider: "yahoo",
            priceInterval: "1h",
            graphInterval: "1M"
        },
        {
            id: "BRLPLN",
            name: "BRL/PLN",
            provider: "wise",
            priceInterval: "1h",
            graphInterval: "1M",
            pinned: true
        }
    ]
    property var pollCondition: null
    property var pollDone: null
    property Timer poller: Timer {
        interval: 100
        repeat: true

        onTriggered: {
            if (suite.pollCondition()) {
                stop();
                suite.pollDone("");
            } else if (--suite.pollsLeft <= 0) {
                stop();
                suite.pollDone("timed out: " + suite.describe());
            }
        }
    }
    property int pollsLeft: 0
    property var service: null

    // Like DMS's PluginService: saving changes the plugin data right away (as a property change).
    property Component serviceType: Component {
        QtObject {
            property var data: ({})
            property int saves: 0

            function loadPluginData(id, key, fallback) {
                return key in data ? data[key] : fallback;
            }
            function savePluginData(id, key, value) {
                var copy = Object.assign({}, data);
                copy[key] = value;
                data = copy;
                saves++;
            }
        }
    }
    property var widget: null

    function allLoaded() {
        return widget.symbols.length > 0 && everyone(widget.priceData, widget.symbols) && everyone(widget.graphData, widget.symbols);
    }
    function async_every_pull_is_stamped_so_nothing_is_fetched_again_at_once(done) {
        start(currentSymbols);
        waitFor(allLoaded, function (problem) {
            if (problem) {
                done(problem);
                return;
            }
            try {
                check(widget.symbols.every(function (symbol) {
                    return Object.keys(widget.pendingFetches || {}).indexOf(symbol.uid) === -1;
                }), "nothing left pending");
                done("");
            } catch (e) {
                done(e.message);
            }
        });
    }
    // DMS starts the widget with EMPTY plugin data and delivers the saved data a moment later (seen in the real logs:
    // "initialized: 0 symbols", then "read 9 saved symbols"). Saved symbols from an older version must be migrated
    // when they arrive, not only at startup.
    function async_older_symbols_that_arrive_after_startup_are_migrated_and_load(done) {
        start([]);
        equal(widget.symbols, []);
        let delivered = legacySymbols.concat([
            {
                id: "^GSPC",
                name: "S&P",
                provider: "yahoo",
                priceInterval: "1h",
                graphInterval: "1M",
                showChangeWhenPinned: false,
                invert: false,
                pinned: false
            }
        ]);
        service.data = Object.assign({}, service.data, {
            symbols: JSON.stringify(delivered),
            showPriceRange: true,
            _addPriceRange: "1h",
            _addChartRange: "1M"
        });
        waitFor(allLoaded, function (problem) {
            if (problem) {
                done(problem);
                return;
            }
            try {
                let saved = JSON.parse(service.data.symbols);
                same(saved.length, 3);
                check(saved.every(function (symbol) {
                    return symbol.uid && symbol.ticker;
                }), "the delivered list was migrated and saved");
                equal(Object.keys(widget.symbolErrors), [], "no symbol shows an error");
                done("");
            } catch (e) {
                done(e.message);
            }
        });
    }
    function async_symbols_in_the_current_format_load_prices_and_charts(done) {
        start(currentSymbols);
        waitFor(allLoaded, function (problem) {
            if (problem) {
                done(problem);
                return;
            }
            try {
                equal(Object.keys(widget.symbolErrors), []);
                same(service.saves, 0, "nothing needed saving");
                // The second symbol is inverted: its price is 1/x of the fake answer, so below 1.
                check(widget.priceData["22222222-2222-4222-8222-222222222222"].close < 1, "inversion is applied");
                done("");
            } catch (e) {
                done(e.message);
            }
        });
    }
    function async_symbols_saved_by_an_older_version_are_migrated_and_then_load_prices_and_charts(done) {
        start(legacySymbols);
        waitFor(allLoaded, function (problem) {
            if (problem) {
                done(problem);
                return;
            }
            let saved = JSON.parse(service.data.symbols);
            try {
                check(saved.every(function (symbol) {
                    return symbol.uid && symbol.ticker && symbol.priceResolution && symbol.chartResolution && symbol.chartRange;
                }), "the migrated list was saved");
                equal(saved.map(function (symbol) {
                    return symbol.ticker;
                }), ["EURUSD=X", "BRLPLN"]);
                equal(Object.keys(widget.symbolErrors), [], "no symbol shows an error");
                same(widget.priceData[saved[0].uid].close > 0, true);
                // Yahoo ends its answer with a flat "live" row; the change must still be the real one, not 0.
                same(widget.priceData[saved[0].uid].change, 1, "the change is measured against the previous day's close (the live snapshot row is no day)");
                check(widget.priceData[saved[1].uid].change > 0, "a Wise step change is not 0 either");
                same(widget.graphData[saved[0].uid].length > 1, true);
                done("");
            } catch (e) {
                done(e.message);
            }
        });
    }
    function describe() {
        return "symbols " + widget.symbols.length + ", prices " + Object.keys(widget.priceData).length + ", graphs " + Object.keys(widget.graphData).length + ", errors " + JSON.stringify(Object.keys(widget.symbolErrors).map(function (uid) {
            var entry = widget.symbolErrors[uid];
            return (entry.price || entry.graph).userMessage;
        }));
    }
    function everyone(map, symbols) {
        return symbols.every(function (symbol) {
            return symbol.uid && map[symbol.uid] !== undefined;
        });
    }
    function setup() {
        if (widget) {
            widget.destroy();
            widget = null;
        }
        ErrorHandler.reset();
        Logger.configure({
            devMode: false
        });
        ProvidersManager.reload(ProvidersManager.sources);
    }
    function start(savedSymbols, extraData) {
        let data = Object.assign({
            symbols: JSON.stringify(savedSymbols)
        }, extraData || {});
        service = serviceType.createObject(null, {
            data: data
        });
        let component = Qt.createComponent("file://" + repoRoot + "/src/QML/Widget.qml");
        check(component.status === Component.Ready, component.errorString());
        widget = component.createObject(null, {
            pluginId: "markets",
            pluginService: service,
            pluginData: Qt.binding(function () {
                return service.data;
            })
        });
        check(widget !== null, "the widget was created");
    }
    function test_no_symbols_is_a_quiet_start() {
        start([]);
        equal(widget.symbols, []);
        equal(widget.symbolErrors, {});
        same(service.saves, 0);
    }
    function test_the_settings_page_builds_with_saved_symbols_of_any_format() {
        let component = Qt.createComponent("file://" + repoRoot + "/src/QML/Settings.qml");
        check(component.status === Component.Ready, component.errorString());
        [legacySymbols, currentSymbols].forEach(function (saved) {
            let settingsService = serviceType.createObject(null, {
                data: {
                    symbols: JSON.stringify(saved)
                }
            });
            let settings = component.createObject(null, {
                pluginId: "markets",
                pluginService: settingsService
            });
            check(settings !== null, "the settings page was created");
            same(settings.symbolsList.length, 2, "its list shows the saved symbols");
            check(settings.symbolsList.every(function (symbol) {
                return symbol.uid && symbol.ticker;
            }), "...migrated");
            settings.destroy();
        });
    }
    function waitFor(condition, done) {
        pollCondition = condition;
        pollDone = done;
        pollsLeft = 150;
        poller.start();
    }
}
