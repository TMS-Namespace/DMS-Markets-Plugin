// The settings page the way DMS loads it: a Loader creates the page FIRST, and only afterwards sets its pluginService
// (onLoaded). The real DMS controls save on every value change, even before the service exists, and the plugin data
// can change later (the widget migrates the saved symbols). Nothing of that may produce an error toast, and the list of
// configured symbols must fill in once the service arrives and follow later data changes.
import QtQuick
import "../../../src/QML/Services"
import "../../../src/QML/Views"
import "../../Helpers"
import qs.Modules.Plugins
import qs.Services
import qs.Widgets

TestSuite {
    id: suite

    readonly property var current: [
        {
            uid: "11111111-1111-4111-8111-111111111111",
            ticker: "EURUSD=X",
            name: "EUR",
            provider: "yahoo",
            priceResolution: "1h",
            chartResolution: "1d",
            chartRange: "1M",
            showChangeWhenPinned: false,
            invert: false,
            pinned: false
        }
    ]
    property var loader: null
    property Component loaderType: Component {
        Loader {
            property var service: null

            asynchronous: false
            height: 800
            width: 600

            onLoaded: {
                (item as PluginSettings).pluginService = service;
            }      // after loading, as DMS does
        }
    }
    readonly property var older: [
        {
            id: "EURUSD=X",
            name: "EUR",
            provider: "yahoo",
            priceInterval: "1h",
            graphInterval: "1M",
            showChangeWhenPinned: false,
            invert: false,
            pinned: false
        },
        {
            id: "DX-Y.NYB",
            name: "USDX",
            provider: "yahoo",
            priceInterval: "1h",
            graphInterval: "1M",
            showChangeWhenPinned: false,
            invert: false,
            pinned: true
        },
        {
            id: "BRLPLN",
            name: "BRL/PLN",
            provider: "wise",
            priceInterval: "1h",
            graphInterval: "1M",
            showChangeWhenPinned: false,
            invert: false,
            pinned: false
        }
    ]
    property var pollCondition: null
    property var pollDone: null
    property Timer poller: Timer {
        interval: 50
        repeat: true

        onTriggered: {
            if (suite.pollCondition()) {
                stop();
                suite.pollDone("");
            } else if (--suite.pollsLeft <= 0) {
                stop();
                suite.pollDone("timed out: list " + (suite.loader.item ? suite.loader.item.symbolsList.length : -1) + ", toasts " + JSON.stringify(ToastService.errors));
            }
        }
    }
    property int pollsLeft: 0
    property var service: null

    // Like DMS's PluginService: saving changes the data and announces it.
    property Component serviceType: Component {
        QtObject {
            id: service

            property var availablePlugins: ({})
            property var data: ({})

            signal pluginDataChanged(string pluginId)

            function getPluginVariants(id) {
                return [];
            }
            function loadPluginData(id, key, fallback) {
                return key in data ? data[key] : fallback;
            }
            function savePluginData(id, key, value) {
                var copy = Object.assign({}, data);
                copy[key] = value;
                data = copy;
                pluginDataChanged(id);
            }
        }
    }

    // ── Picking a configured symbol fills EVERY field of the form from it ────
    readonly property var twoSymbols: [
        {
            uid: "11111111-1111-4111-8111-111111111111",
            ticker: "EURUSD=X",
            name: "EUR",
            provider: "yahoo",
            priceResolution: "5m",
            changeResolution: "1w",
            chartResolution: "1h",
            chartRange: "1W",
            showChangeWhenPinned: true,
            invert: true,
            pinned: false
        },
        {
            uid: "22222222-2222-4222-8222-222222222222",
            ticker: "BRLPLN",
            name: "BRL/PLN",
            provider: "wise",
            priceResolution: "1d",
            changeResolution: "1h",
            chartResolution: "1d",
            chartRange: "3M",
            showChangeWhenPinned: false,
            invert: false,
            pinned: true
        }
    ]

    // Exercise adding through the fields and button, including the disabled state for invalid input.
    function async_add_symbol_through_settings_controls(done) {
        let page = open({
            symbols: "[]"
        });
        waitFor(function () {
            return page._formReset && page.tickerText === "";
        }, function (problem) {
            try {
                if (problem)
                    throw new Error(problem);
                same(formButton(page, "Add Symbol").enabled, false, "empty input cannot be saved");
                enterText(page, page.selectedProvider.symbolPlaceholder, "NOT A SYMBOL");
                enterText(page, "Gold", "Gold");
                same(formButton(page, "Add Symbol").enabled, false, "invalid ticker cannot be saved");
                enterText(page, page.selectedProvider.symbolPlaceholder, "HG=F");
                let button = formButton(page, "Add Symbol");
                check(button.enabled);
                button.clicked(null);
                waitFor(function () {
                    return page.symbolsList.length === 1 && page.tickerText === "";
                }, function (saveProblem) {
                    try {
                        if (saveProblem)
                            throw new Error(saveProblem);
                        let saved = JSON.parse(service.data.symbols);
                        same(saved.length, 1);
                        same(saved[0].ticker, "HG=F");
                        same(saved[0].name, "Gold");
                        check(/^[0-9a-f-]{36}$/i.test(saved[0].uid), "new symbol has a persisted ID");
                        check(configuredRow(page, saved[0].uid) !== null, "new row is displayed");
                        same(page.editIndex, -1);
                        same(page.nameText, "", "form resets after saving");
                        equal(ToastService.errors, []);
                        done("");
                    } catch (error) {
                        done(error.message);
                    }
                });
            } catch (error) {
                done(error.message);
            }
        });
    }

    // Deleting the row currently being edited must persist the removal and leave the form in add mode.
    function async_delete_symbol_through_settings_controls(done) {
        let page = open({
            symbols: JSON.stringify(twoSymbols)
        });
        waitFor(function () {
            return page._formReset && configuredRow(page, twoSymbols[1].uid) !== null;
        }, function (problem) {
            try {
                if (problem)
                    throw new Error(problem);
                let row = configuredRow(page, twoSymbols[1].uid);
                let selection = findItem(row, function (item) {
                    return item as MouseArea;
                }) as MouseArea;
                selection.clicked(null);
                same(page.editIndex, 1);
                let icon = findItem(row, function (item) {
                    return (item as DankIcon) && item.name === "delete";
                });
                check(icon !== null);
                let button = icon.parent as MouseArea;
                check(button.enabled);
                button.clicked(null);
                waitFor(function () {
                    return page.symbolsList.length === 1 && page.editIndex === -1;
                }, function (saveProblem) {
                    try {
                        if (saveProblem)
                            throw new Error(saveProblem);
                        equal(JSON.parse(service.data.symbols), [twoSymbols[0]], "only the selected entry is removed");
                        same(configuredRow(page, twoSymbols[1].uid), null, "removed row disappears");
                        check(configuredRow(page, twoSymbols[0].uid) !== null, "other row remains");
                        same(page.tickerText, "");
                        same(page.nameText, "");
                        equal(ToastService.errors, []);
                        done("");
                    } catch (error) {
                        done(error.message);
                    }
                });
            } catch (error) {
                done(error.message);
            }
        });
    }
    function async_every_field_is_set_from_the_symbol_after_changing_each_dropdown_in_turn(done) {
        let page = open({
            symbols: JSON.stringify(twoSymbols)
        });
        waitFor(function () {
            return page.symbolsList.length === 2 && page._formReset;
        }, function (problem) {
            if (problem) {
                done(problem);
                return;
            }
            settled(page, done, function () {
                ["_addProvider", "_addPriceResolution", "_addChangeResolution", "_addChartResolution", "_addChartRange", "_addShowChange", "_addInvert"].forEach(function (key) {
                    service.savePluginData("markets", key, key === "_addProvider" ? "wise" : (key === "_addShowChange" || key === "_addInvert" ? true : "1d"));
                    page.editSymbol(0);
                    equal(page.formState, fieldsOf(twoSymbols[0]), "after changing " + key);
                    page.cancelEdit();
                });
            });
        });
    }
    function async_picking_a_configured_symbol_sets_every_field_even_after_the_form_was_changed(done) {
        let page = open({
            symbols: JSON.stringify(twoSymbols)
        });
        waitFor(function () {
            return page.symbolsList.length === 2 && page._formReset;
        }, function (problem) {
            if (problem) {
                done(problem);
                return;
            }
            settled(page, done, function () {
                // The user plays with the form (what the controls do: save their draft key)…
                service.savePluginData("markets", "_addChartRange", "1M");
                service.savePluginData("markets", "_addPriceResolution", "1h");
                service.savePluginData("markets", "_addInvert", true);
                // …then picks the first symbol, then the second, then the first again.
                page.editSymbol(0);
                equal(page.formState, fieldsOf(twoSymbols[0]), "first symbol");
                page.editSymbol(1);
                equal(page.formState, fieldsOf(twoSymbols[1]), "second symbol");
                page.editSymbol(0);
                equal(page.formState, fieldsOf(twoSymbols[0]), "first symbol again");
            });
        });
    }
    function async_symbols_in_the_current_format_are_listed(done) {
        let page = open({
            symbols: JSON.stringify(current)
        });
        waitFor(function () {
            return page.symbolsList.length === 1;
        }, function (problem) {
            try {
                if (problem) {
                    done(problem);
                    return;
                }
                equal(ToastService.errors, [], "no error toast");
                done("");
            } catch (e) {
                done(e.message);
            }
        });
    }
    function async_symbols_saved_by_an_older_version_are_listed_once_the_service_arrives(done) {
        let page = open({
            symbols: JSON.stringify(older)
        });
        waitFor(function () {
            return page.symbolsList.length === 3;
        }, function (problem) {
            if (problem) {
                done(problem);
                return;
            }
            try {
                check(page.symbolsList.every(function (symbol) {
                    return symbol.uid && symbol.ticker;
                }), "migrated");
                equal(ToastService.errors, [], "no error toast");
                done("");
            } catch (e) {
                done(e.message);
            }
        });
    }

    // What was typed or chosen in the "add a symbol" form last time is not brought back when the page is expanded again.
    function async_the_add_form_always_starts_from_its_defaults(done) {
        let left = {
            _addTicker: "EURUSD=X",
            _addName: "Old",
            _addProvider: "wise",
            _addPriceResolution: "1d",
            _addChartRange: "1Y",
            _addShowChange: true,
            _addInvert: true
        };
        let page = open(Object.assign({
            symbols: JSON.stringify(current)
        }, left));
        waitFor(function () {
            return page._formReset && page.tickerText === "" && page.nameText === "";
        }, function (problem) {
            if (problem) {
                done(problem);
                return;
            }
            // give the deferred reset and DMS's own loads time to settle, then look again
            waitFor(function () {
                return false;
            }, function () {
                try {
                    same(page.tickerText, "", "no ticker");
                    same(page.nameText, "", "no name");
                    same(page.selectedProviderId, "yahoo", "the default provider");
                    same(service.data._addShowChange, false);
                    same(service.data._addInvert, false);
                    same(service.data._addTicker, "", "the saved draft was reset too");
                    same(service.data._addName, "");
                    same(service.data._addProvider, "yahoo");
                    equal(ToastService.errors, [], "no error");
                    done("");
                } catch (e) {
                    done(e.message);
                }
            });
        });
    }
    function async_the_list_follows_plugin_data_that_changes_later(done) {
        let page = open({});
        service.data = {
            symbols: JSON.stringify(current)
        };      // e.g. the widget saved, or DMS delivered the data late
        service.pluginDataChanged("markets");
        waitFor(function () {
            return page.symbolsList.length === 1;
        }, function (problem) {
            try {
                if (problem) {
                    done(problem);
                    return;
                }
                equal(ToastService.errors, [], "no error toast");
                done("");
            } catch (e) {
                done(e.message);
            }
        });
    }

    // The popup height set before a restart is what the slider shows once the page has its service (not its default).
    function async_the_popup_height_slider_shows_the_saved_value(done) {
        let page = open({
            symbols: JSON.stringify(current),
            popoutRows: 10
        });
        waitFor(function () {
            return page.popoutRowsValue === 10;
        }, function (problem) {
            if (problem) {
                done(problem + " (shows " + page.popoutRowsValue + ")");
                return;
            }
            waitFor(function () {
                return false;
            }, function () {
                try {
                    same(page.popoutRowsValue, 10, "still the saved value after everything settled");
                    same(service.data.popoutRows, 10, "and it was not overwritten by the default");
                    done("");
                } catch (e) {
                    done(e.message);
                }
            });
        });
    }

    // ── The symbol's own settings are locked until there is a valid ticker and name ──
    function async_the_symbol_settings_unlock_with_a_valid_ticker_and_name_and_for_a_picked_symbol(done) {
        let page = open({
            symbols: JSON.stringify(twoSymbols)
        });
        waitFor(function () {
            return page.symbolsList.length === 2 && page._formReset;
        }, function (problem) {
            if (problem) {
                done(problem);
                return;
            }
            settled(page, done, function () {
                same(page.formUnlocked, false, "an empty form is locked");
                let base = {
                    provider: "yahoo",
                    priceResolution: "1h",
                    changeResolution: "1d",
                    chartResolution: "1d",
                    chartRange: "1M",
                    showChange: false,
                    invert: false
                };
                page.setDraft(Object.assign({
                    ticker: "EURUSD=X",
                    name: ""
                }, base));
                same(page.formUnlocked, false, "a ticker without a name stays locked");
                page.setDraft(Object.assign({
                    ticker: "",
                    name: "EUR"
                }, base));
                same(page.formUnlocked, false, "a name without a ticker stays locked");
                page.setDraft(Object.assign({
                    ticker: "NOT A TICKER",
                    name: "EUR"
                }, base));
                same(page.formUnlocked, false, "an invalid ticker stays locked");
                page.setDraft(Object.assign({
                    ticker: "EURUSD=X",
                    name: "a;b"
                }, base));
                same(page.formUnlocked, false, "an invalid name stays locked");
                page.setDraft(Object.assign({
                    ticker: "EURUSD=X",
                    name: "EUR USD"
                }, base));
                same(page.formUnlocked, true, "a valid ticker and name unlock it");
                page.clearForm();
                same(page.formUnlocked, false, "clearing locks it again");
                page.editSymbol(1);
                same(page.formUnlocked, true, "a picked symbol has both: unlocked");
                page.cancelEdit();
                same(page.formUnlocked, false, "deselecting locks it again");
                // The ticker is validated against the provider, so the provider stays choosable while locked.
                page.setDraft(Object.assign({
                    ticker: "BRLPLN",
                    name: "BRL"
                }, base, {
                    provider: "wise"
                }));
                same(page.formUnlocked, true);
            });
        });
    }

    // Updating from a selected row must preserve its ID and pin without modifying another entry.
    function async_update_symbol_through_settings_controls(done) {
        let page = open({
            symbols: JSON.stringify(twoSymbols)
        });
        waitFor(function () {
            return page._formReset && configuredRow(page, twoSymbols[1].uid) !== null;
        }, function (problem) {
            try {
                if (problem)
                    throw new Error(problem);
                let row = configuredRow(page, twoSymbols[1].uid);
                let selection = findItem(row, function (item) {
                    return item as MouseArea;
                }) as MouseArea;
                selection.clicked(null);
                same(page.editIndex, 1);
                same(page.tickerText, "BRLPLN", "selected row fills the edit form");
                enterText(page, page.selectedProvider.symbolPlaceholder, "EURUSD");
                enterText(page, "Gold", "Euro");
                let button = formButton(page, "Update Symbol");
                check(button.enabled);
                button.clicked(null);
                waitFor(function () {
                    return page.editIndex === -1 && page.symbolsList[1].ticker === "EURUSD";
                }, function (saveProblem) {
                    try {
                        if (saveProblem)
                            throw new Error(saveProblem);
                        let saved = JSON.parse(service.data.symbols);
                        same(saved.length, 2);
                        equal(saved[0], twoSymbols[0], "other entry is unchanged");
                        same(saved[1].uid, twoSymbols[1].uid);
                        same(saved[1].pinned, true);
                        same(saved[1].ticker, "EURUSD");
                        same(saved[1].name, "Euro");
                        same(saved[1].provider, "wise");
                        same(configuredRow(page, saved[1].uid).symbolData.name, "Euro", "row displays the update");
                        equal(ToastService.errors, []);
                        done("");
                    } catch (error) {
                        done(error.message);
                    }
                });
            } catch (error) {
                done(error.message);
            }
        });
    }

    // Select a configured row by saved identity so reordering cannot silently target another symbol.
    function configuredRow(page: Item, uid: string): ConfiguredSymbol {
        return findItem(page, function (item) {
            return (item as ConfiguredSymbol) && item.symbolData.uid === uid;
        }) as ConfiguredSymbol;
    }

    // Enter text and finish editing through the same control signals used by DMS.
    function enterText(page: Item, placeholder: string, value: string) {
        let field = findItem(page, function (item) {
            return (item as DankTextField) && item.placeholderText === placeholder;
        }) as DankTextField;
        check(field !== null, "text field exists: " + placeholder);
        field.text = value;
        field.editingFinished();
    }
    function fieldsOf(symbol) {
        return {
            ticker: symbol.ticker,
            name: symbol.name,
            provider: symbol.provider,
            priceResolution: symbol.priceResolution,
            changeResolution: symbol.changeResolution,
            chartResolution: symbol.chartResolution,
            chartRange: symbol.chartRange,
            showChange: symbol.showChangeWhenPinned,
            invert: symbol.invert
        };
    }

    // Find rendered controls without exposing the page's private QML IDs.
    function findItem(parentItem: Item, predicate): Item {
        if (predicate(parentItem))
            return parentItem;
        for (let child of parentItem.children) {
            let found = findItem(child, predicate);
            if (found)
                return found;
        }
        return null;
    }

    // Locate a form action by its visible label, then activate its actual input handler.
    function formButton(page: Item, label: string): MouseArea {
        let text = findItem(page, function (item) {
            return "text" in item && item.text === label;
        });
        check(text !== null, "button label exists: " + label);
        let button = findItem(text.parent, function (item) {
            return item as MouseArea;
        }) as MouseArea;
        check(button !== null, "button input exists: " + label);
        return button;
    }
    function open(data) {
        service = serviceType.createObject(null, {
            data: data
        });
        loader = (loaderType.createObject(null, {
                service: service,
                source: "file://" + repoRoot + "/src/QML/Settings.qml"
            }) as Loader);
        check(loader.status === Loader.Ready, "the page loads: " + loader.status);
        return loader.item;
    }
    function settled(page, done, action) {
        // The controls load their values from the saved draft when plugin data changes: let everything settle, then look.
        waitFor(function () {
            return false;
        }, function () {
            try {
                action();
                done("");
            } catch (e) {
                done(e.message);
            }
        });
    }
    function setup() {
        if (loader) {
            loader.destroy();
            loader = null;
        }
        ToastService.errors = [];
        ToastService.infos = [];
        ErrorHandler.reset();
        Logger.configure({
            devMode: false
        });
        ProvidersManager.reload(ProvidersManager.sources);
    }
    function test_nothing_is_reported_while_the_service_is_not_attached_yet() {
        let component = Qt.createComponent("file://" + repoRoot + "/src/QML/Settings.qml");
        check(component.status === Component.Ready, component.errorString());
        let page = component.createObject(null, {
            pluginId: "markets"
        }) as PluginSettings;      // no service, like the moment after the Loader created it
        check(page !== null);
        same(page.saveValue("_addProvider", "yahoo"), false, "a control saving before the service exists saves nothing...");
        equal(ToastService.errors, [], "the controls saving their defaults before the service exists is not an error");
        page.destroy();
    }
    function waitFor(condition, done) {
        pollCondition = condition;
        pollDone = done;
        pollsLeft = 60;
        poller.start();
    }
}
