// The settings page the way DMS loads it: a Loader creates the page FIRST, and only afterwards sets its pluginService
// (onLoaded). The real DMS controls save on every value change, even before the service exists, and the plugin data
// can change later (the widget migrates the saved symbols). Nothing of that may produce an error toast, and the list of
// configured symbols must fill in once the service arrives and follow later data changes.
import QtQuick
import "../../../src/QML/Services"
import "../../../src/QML/Views"
import "../../Helpers"
import qs.DCommon.Widgets
import qs.Modules.Plugins
import qs.Services

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
                suite.pollDone("timed out: list " + (suite.loader.item ? suite.loader.item.controller.symbolsList.length : -1) + ", toasts " + JSON.stringify(ToastService.errors));
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
            property bool rejectSymbols: false

            signal pluginDataChanged(string pluginId)

            function getPluginVariants(id) {
                return [];
            }
            function loadPluginData(id, key, fallback) {
                return key in data ? data[key] : fallback;
            }
            function savePluginData(id, key, value) {
                if (rejectSymbols && key === "symbols")
                    return false;
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
            return page.controller._formReset && page.controller.tickerText === "";
        }, function (problem) {
            try {
                if (problem)
                    throw new Error(problem);
                same(formButton(page, "Add Symbol").enabled, false, "empty input cannot be saved");
                enterText(page, page.controller.selectedProvider.symbolPlaceholder, "NOT A SYMBOL");
                enterText(page, "Gold", "Gold");
                same(formButton(page, "Add Symbol").enabled, false, "invalid ticker cannot be saved");
                enterText(page, page.controller.selectedProvider.symbolPlaceholder, "HG=F");
                let button = formButton(page, "Add Symbol");
                check(button.enabled);
                button.clicked(null);
                waitFor(function () {
                    return page.controller.symbolsList.length === 1 && page.controller.tickerText === "";
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
                        same(page.controller.editIndex, -1);
                        same(page.controller.nameText, "", "form resets after saving");
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

    // The editor's cancel signal resets the form without writing unsaved changes to the symbol list.
    function async_cancel_button_discards_symbol_edits(done) {
        let page = open({
            symbols: JSON.stringify(twoSymbols)
        });
        waitFor(function () {
            return page.controller._formReset && page.controller.symbolsList.length === 2;
        }, function (problem) {
            try {
                if (problem)
                    throw new Error(problem);
                page.controller.editSymbol(0);
                enterText(page, "Gold", "Changed");
                same(service.data._addName, "Changed", "the editor sends draft changes to storage");
                formButton(page, "Cancel").clicked(null);
                same(page.controller.editIndex, -1);
                same(page.controller.tickerText, "");
                same(page.controller.nameText, "");
                equal(JSON.parse(service.data.symbols), twoSymbols, "cancel preserves saved symbols");
                same(formButton(page, "Add Symbol").enabled, false);
                equal(ToastService.errors, []);
                done("");
            } catch (error) {
                done(error.message);
            }
        });
    }

    // Collapsing cancels an armed deletion; the two actions keep readable labels when reopened.
    function async_cleanup_group_can_collapse_without_confirming_removal(done) {
        let page = open({
            symbols: JSON.stringify(twoSymbols)
        });
        waitFor(function () {
            return page.controller.symbolsList.length === 2;
        }, function (problem) {
            if (problem) {
                done(problem);
                return;
            }
            settled(page, done, function () {
                let maintenance = findItem(page, function (item) {
                    return item as DataMaintenance;
                }) as DataMaintenance;
                same(maintenance.title, "CleanUp");
                same(maintenance.expanded, false, "cleanup starts collapsed");
                maintenance.toggle();
                same(maintenance.expanded, true);
                let remove = findItem(maintenance, function (item) {
                    return (item as DButton) && item.text === "Clear Symbols";
                }) as DButton;
                let clear = findItem(maintenance, function (item) {
                    return (item as DButton) && item.text === "Clear Cache";
                }) as DButton;
                check(remove !== null && clear !== null, "both labels exist");
                same(remove.textColor.toString(), clear.textColor.toString(), "both actions use the host's contrasting button text color");
                same(remove.visible, true);
                remove.clicked();
                same(remove.text, "Confirm Clear Symbols");
                maintenance.toggle();
                same(maintenance.confirmRemoval, false, "collapsing cancels confirmation");
                same(remove.visible, false);
                maintenance.toggle();
                same(remove.text, "Clear Symbols");
                same(JSON.parse(service.data.symbols).length, 2, "no actual removal occurred");
            });
        });
    }

    // Clear-cache activation stays inside a disposable directory and never edits configured symbols.
    function async_clear_cache_button_keeps_the_symbol_list(done) {
        let page = open({
            symbols: JSON.stringify(twoSymbols)
        });
        page.controller.cacheDirectory = freshDirectory("settings-cache-button");
        waitFor(function () {
            return page.controller.symbolsList.length === 2;
        }, function (problem) {
            if (problem) {
                done(problem);
                return;
            }
            let maintenance = suite.findItem(page, function (item) {
                return item as DataMaintenance;
            }) as DataMaintenance;
            maintenance.toggle();
            let clear = suite.findItem(maintenance, function (item) {
                return (item as DButton) && item.text === "Clear Cache";
            }) as DButton;
            let originalSymbols = suite.service.data.symbols;
            clear.clicked();
            suite.same(maintenance.cacheClearing, true);
            suite.same(clear.enabled, false, "repeated clears are blocked");
            suite.waitFor(function () {
                return !maintenance.cacheClearing;
            }, function (clearProblem) {
                try {
                    suite.check(!clearProblem, clearProblem);
                    suite.same(suite.service.data.symbols, originalSymbols);
                    suite.same(page.controller.symbolsList.length, 2);
                    suite.check(ToastService.infos.length > 0, "completion is shown");
                    done("");
                } catch (error) {
                    done(error.message);
                }
            });
        });
    }

    // A refused save must leave the configured symbols and active edit intact and report the failure.
    function async_delete_all_symbols_reports_failed_storage_without_losing_the_list(done) {
        let page = open({
            symbols: JSON.stringify(twoSymbols)
        });
        waitFor(function () {
            return page.controller.symbolsList.length === 2;
        }, function (problem) {
            if (problem) {
                done(problem);
                return;
            }
            settled(page, done, function () {
                page.controller.editSymbol(0);
                service.rejectSymbols = true;
                Logger.configure({
                    isDevMode: false
                }); // this test deliberately refuses a save
                let maintenance = findItem(page, function (item) {
                    return item as DataMaintenance;
                }) as DataMaintenance;
                maintenance.toggle();
                let remove = findItem(maintenance, function (item) {
                    return (item as DButton) && item.text === "Clear Symbols";
                }) as DButton;
                remove.clicked();
                remove.clicked();
                same(JSON.parse(service.data.symbols).length, 2);
                same(page.controller.symbolsList.length, 2);
                same(page.controller.editIndex, 0);
                check(ToastService.errors.length > 0, "save failure is visible");
            });
        });
    }

    // Both confirmation and cancel go through the real maintenance buttons; all data belongs to the fake service.
    function async_delete_all_symbols_requires_confirmation_and_preserves_display_settings(done) {
        let page = open({
            symbols: JSON.stringify(twoSymbols),
            upColor: "#123456"
        });
        waitFor(function () {
            return page.controller.symbolsList.length === 2;
        }, function (problem) {
            if (problem) {
                done(problem);
                return;
            }
            settled(page, done, function () {
                let maintenance = findItem(page, function (item) {
                    return item as DataMaintenance;
                }) as DataMaintenance;
                check(maintenance !== null);
                maintenance.toggle();
                let remove = findItem(maintenance, function (item) {
                    return (item as DButton) && item.text === "Clear Symbols";
                }) as DButton;
                let configured = findItem(page, function (item) {
                    let candidate = item as Repeater;
                    return candidate && candidate.count > 0 && (candidate.itemAt(0) as ConfiguredSymbol);
                }) as Repeater;
                check(configured !== null);
                same(configured.count, 2, "both configured rows exist before clearing");
                page.controller.editSymbol(0);
                remove.clicked();
                same(maintenance.confirmRemoval, true);
                same(page.controller.symbolsList.length, 2, "first click does not delete");
                let cancel = findItem(maintenance, function (item) {
                    return (item as DButton) && item.text === "Cancel";
                }) as DButton;
                cancel.clicked();
                same(maintenance.confirmRemoval, false);
                same(JSON.parse(service.data.symbols).length, 2);
                remove.clicked();
                remove.clicked();
                same(service.data.symbols, "[]");
                same(page.controller.symbolsList.length, 0);
                same(configured.count, 0, "the configured-symbol list is actually empty");
                same(page.controller.editIndex, -1);
                same(service.data.upColor, "#123456");
                same(remove.enabled, false, "nothing left to delete");
            });
        });
    }

    // Deleting the row currently being edited must persist the removal and leave the form in add mode.
    function async_delete_symbol_through_settings_controls(done) {
        let page = open({
            symbols: JSON.stringify(twoSymbols)
        });
        waitFor(function () {
            return page.controller._formReset && configuredRow(page, twoSymbols[1].uid) !== null;
        }, function (problem) {
            try {
                if (problem)
                    throw new Error(problem);
                let row = configuredRow(page, twoSymbols[1].uid);
                let selection = findItem(row, function (item) {
                    return item as MouseArea;
                }) as MouseArea;
                selection.clicked(null);
                same(page.controller.editIndex, 1);
                let icon = findItem(row, function (item) {
                    return (item as DIcon) && item.name === "delete";
                });
                check(icon !== null);
                let button = icon.parent as MouseArea;
                check(button.enabled);
                button.clicked(null);
                waitFor(function () {
                    return page.controller.symbolsList.length === 1 && page.controller.editIndex === -1;
                }, function (saveProblem) {
                    try {
                        if (saveProblem)
                            throw new Error(saveProblem);
                        equal(JSON.parse(service.data.symbols), [twoSymbols[0]], "only the selected entry is removed");
                        same(configuredRow(page, twoSymbols[1].uid), null, "removed row disappears");
                        check(configuredRow(page, twoSymbols[0].uid) !== null, "other row remains");
                        same(page.controller.tickerText, "");
                        same(page.controller.nameText, "");
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

    // Nested host controls must still find the page when loading and saving global settings.
    function async_display_view_loads_and_saves_settings(done) {
        let page = open({
            symbols: "[]",
            showTicker: false
        });
        waitFor(function () {
            let toggle = findItem(page, function (item) {
                return (item as ToggleSetting) && item.settingKey === "showTicker";
            });
            return page.controller._formReset && toggle !== null && toggle.isInitialized;
        }, function (problem) {
            try {
                if (problem)
                    throw new Error(problem);
                let toggle = findItem(page, function (item) {
                    return (item as ToggleSetting) && item.settingKey === "showTicker";
                }) as ToggleSetting;
                same(toggle.value, false, "saved value reaches the extracted view");
                toggle.value = true;
                same(service.data.showTicker, true, "nested control saves through the page");
                equal(ToastService.errors, []);
                done("");
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
            return page.controller.symbolsList.length === 2 && page.controller._formReset;
        }, function (problem) {
            if (problem) {
                done(problem);
                return;
            }
            settled(page, done, function () {
                ["_addProvider", "_addPriceResolution", "_addChangeResolution", "_addChartResolution", "_addChartRange", "_addShowChange", "_addInvert"].forEach(function (key) {
                    service.savePluginData("markets", key, key === "_addProvider" ? "wise" : (key === "_addShowChange" || key === "_addInvert" ? true : "1d"));
                    page.controller.editSymbol(0);
                    equal(page.controller.formState, fieldsOf(twoSymbols[0]), "after changing " + key);
                    page.controller.cancelEdit();
                });
            });
        });
    }

    // All controls remain instantiated for loading saved values even though their sections start collapsed.
    function async_global_and_per_symbol_groups_start_collapsed(done) {
        let page = open({
            symbols: JSON.stringify(twoSymbols),
            popoutRows: 7
        }, true);
        waitFor(function () {
            return page.controller.symbolsList.length === 2 && page.popoutRowsValue === 7;
        }, function (problem) {
            if (problem) {
                done(problem);
                return;
            }
            settled(page, done, function () {
                let globalGroup = findItem(page, function (item) {
                    return (item as DCollapsibleSection) && item.title === "Global View Settings";
                }) as DCollapsibleSection;
                let symbolGroup = findItem(page, function (item) {
                    return (item as DCollapsibleSection) && item.title === "Per Symbol Settings";
                }) as DCollapsibleSection;
                check(globalGroup !== null && symbolGroup !== null);
                same(globalGroup.expanded, false);
                same(symbolGroup.expanded, false);
                let display = findItem(globalGroup, function (item) {
                    return item as DisplaySettings;
                }) as DisplaySettings;
                let editor = findItem(symbolGroup, function (item) {
                    return item as SymbolEditor;
                }) as SymbolEditor;
                check(display !== null && editor !== null, "controls are inside the matching sections");
                same(display.popoutRowsValue, 7, "collapsed controls still load their saved values");
                symbolGroup.toggle();
                let row = findItem(symbolGroup, function (item) {
                    return item as ConfiguredSymbol;
                }) as ConfiguredSymbol;
                check(row !== null && row.visible);
                globalGroup.toggle();
                same(display.visible, true);
            });
        });
    }
    function async_picking_a_configured_symbol_sets_every_field_even_after_the_form_was_changed(done) {
        let page = open({
            symbols: JSON.stringify(twoSymbols)
        });
        waitFor(function () {
            return page.controller.symbolsList.length === 2 && page.controller._formReset;
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
                page.controller.editSymbol(0);
                equal(page.controller.formState, fieldsOf(twoSymbols[0]), "first symbol");
                page.controller.editSymbol(1);
                equal(page.controller.formState, fieldsOf(twoSymbols[1]), "second symbol");
                page.controller.editSymbol(0);
                equal(page.controller.formState, fieldsOf(twoSymbols[0]), "first symbol again");
            });
        });
    }
    function async_symbols_in_the_current_format_are_listed(done) {
        let page = open({
            symbols: JSON.stringify(current)
        });
        waitFor(function () {
            return page.controller.symbolsList.length === 1;
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
            return page.controller.symbolsList.length === 3;
        }, function (problem) {
            if (problem) {
                done(problem);
                return;
            }
            try {
                check(page.controller.symbolsList.every(function (symbol) {
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
            return page.controller._formReset && page.controller.tickerText === "" && page.controller.nameText === "";
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
                    same(page.controller.tickerText, "", "no ticker");
                    same(page.controller.nameText, "", "no name");
                    same(page.controller.selectedProviderId, "yahoo", "the default provider");
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
            return page.controller.symbolsList.length === 1;
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
            return page.controller.symbolsList.length === 2 && page.controller._formReset;
        }, function (problem) {
            if (problem) {
                done(problem);
                return;
            }
            settled(page, done, function () {
                same(page.controller.formUnlocked, false, "an empty form is locked");
                let base = {
                    provider: "yahoo",
                    priceResolution: "1h",
                    changeResolution: "1d",
                    chartResolution: "1d",
                    chartRange: "1M",
                    showChange: false,
                    invert: false
                };
                page.controller.setDraft(Object.assign({
                    ticker: "EURUSD=X",
                    name: ""
                }, base));
                same(page.controller.formUnlocked, false, "a ticker without a name stays locked");
                page.controller.setDraft(Object.assign({
                    ticker: "",
                    name: "EUR"
                }, base));
                same(page.controller.formUnlocked, false, "a name without a ticker stays locked");
                page.controller.setDraft(Object.assign({
                    ticker: "NOT A TICKER",
                    name: "EUR"
                }, base));
                same(page.controller.formUnlocked, false, "an invalid ticker stays locked");
                page.controller.setDraft(Object.assign({
                    ticker: "EURUSD=X",
                    name: "a;b"
                }, base));
                same(page.controller.formUnlocked, false, "an invalid name stays locked");
                page.controller.setDraft(Object.assign({
                    ticker: "EURUSD=X",
                    name: "EUR USD"
                }, base));
                same(page.controller.formUnlocked, true, "a valid ticker and name unlock it");
                page.controller.clearForm();
                same(page.controller.formUnlocked, false, "clearing locks it again");
                page.controller.editSymbol(1);
                same(page.controller.formUnlocked, true, "a picked symbol has both: unlocked");
                page.controller.cancelEdit();
                same(page.controller.formUnlocked, false, "deselecting locks it again");
                // The ticker is validated against the provider, so the provider stays choosable while locked.
                page.controller.setDraft(Object.assign({
                    ticker: "BRLPLN",
                    name: "BRL"
                }, base, {
                    provider: "wise"
                }));
                same(page.controller.formUnlocked, true);
            });
        });
    }

    // Updating from a selected row must preserve its ID and pin without modifying another entry.
    function async_update_symbol_through_settings_controls(done) {
        let page = open({
            symbols: JSON.stringify(twoSymbols)
        });
        waitFor(function () {
            return page.controller._formReset && configuredRow(page, twoSymbols[1].uid) !== null;
        }, function (problem) {
            try {
                if (problem)
                    throw new Error(problem);
                let row = configuredRow(page, twoSymbols[1].uid);
                let selection = findItem(row, function (item) {
                    return item as MouseArea;
                }) as MouseArea;
                selection.clicked(null);
                same(page.controller.editIndex, 1);
                same(page.controller.tickerText, "BRLPLN", "selected row fills the edit form");
                enterText(page, page.controller.selectedProvider.symbolPlaceholder, "EURUSD");
                enterText(page, "Gold", "Euro");
                let button = formButton(page, "Update Symbol");
                check(button.enabled);
                button.clicked(null);
                waitFor(function () {
                    return page.controller.editIndex === -1 && page.controller.symbolsList[1].ticker === "EURUSD";
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
            return (item as DTextField) && item.placeholderText === placeholder;
        }) as DTextField;
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
    function open(data, keepCollapsed) {
        service = serviceType.createObject(null, {
            data: data
        });
        loader = (loaderType.createObject(null, {
                service: service,
                source: "file://" + repoRoot + "/src/QML/Settings.qml"
            }) as Loader);
        check(loader.status === Loader.Ready, "the page loads: " + loader.status);
        // Form interaction tests open the sections as a user would; the startup test keeps their defaults.
        if (!keepCollapsed) {
            ["Global View Settings", "Per Symbol Settings"].forEach(function (title) {
                let section = suite.findItem(suite.loader.item, function (item) {
                    return (item as DCollapsibleSection) && item.title === title;
                }) as DCollapsibleSection;
                suite.check(section !== null, title + " exists");
                section.toggle();
            });
        }
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
            isDevMode: false
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
