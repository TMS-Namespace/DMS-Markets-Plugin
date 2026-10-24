// Exercise the real popup in a headless window: list updates, action routing, and loading/error recovery.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Window
import "../../../src/QML/Views"
import "../../Helpers"

TestSuite {
    id: suite

    readonly property var firstSymbol: ({
            uid: "11111111-1111-4111-8111-111111111111",
            ticker: "EURUSD=X",
            name: "Euro",
            provider: "yahoo",
            priceResolution: "1h",
            chartRange: "1M",
            pinned: false
        })
    property Window popupWindow: null
    // A duplicate ticker makes accidental routing by ticker instead of saved-symbol ID detectable.
    readonly property var secondSymbol: Object.assign({}, firstSymbol, {
        uid: "22222222-2222-4222-8222-222222222222",
        name: "Other Euro",
        pinned: true
    })
    property Component windowType: Component {
        Window {
            property alias panel: popupPanel

            height: 360
            visible: true
            width: 600

            PopoutPanel {
                id: popupPanel

                anchors.fill: parent
                anchors.topMargin: 60
                downColor: "red"
                headerOffset: 60
                upColor: "green"
            }
        }
    }

    // Activate actual button signals and verify the panel forwards the selected row's stable ID.
    function async_actions_target_the_selected_symbol(done) {
        withPanel([firstSymbol, secondSymbol], done, function (panel, list) {
            let events = [];
            panel.togglePin.connect(function (uid) {
                events.push(["pin", uid]);
            });
            panel.removeSymbol.connect(function (uid) {
                events.push(["remove", uid]);
            });
            panel.refreshSymbol.connect(function (uid) {
                events.push(["refresh", uid]);
            });
            panel.refreshAll.connect(function () {
                events.push(["all"]);
            });
            panel.openSettings.connect(function () {
                events.push(["settings"]);
            });
            panel.closePopout.connect(function () {
                events.push(["close"]);
            });
            let row = list.itemAtIndex(1) as SymbolRow;
            same(row.isPinned, true);
            suite.button(row, "push_pin").clicked();
            suite.button(row, "close").clicked();
            suite.button(row, "refresh").clicked();
            suite.button(panel, "refresh").clicked();
            let settings = suite.button(panel, "settings");
            let refreshAll = suite.button(panel, "refresh");
            let close = suite.button(panel, "close");
            check(refreshAll.x < settings.x && settings.x < close.x, "settings sits between refresh and close");
            same(settings.tooltipText, "Open Markets settings");
            settings.clicked();
            close.clicked();
            suite.equal(events, [["pin", suite.secondSymbol.uid], ["remove", suite.secondSymbol.uid], ["refresh", suite.secondSymbol.uid], ["all"], ["settings"], ["close"]]);
        });
    }

    // The placeholder must follow model changes, including removal of the final symbol.
    function async_empty_state_follows_the_symbol_list(done) {
        withPanel([], done, function (panel, list) {
            let placeholder = findItem(panel, function (item) {
                return "text" in item && item.text === "Add symbols to start…";
            });
            check(placeholder !== null && placeholder.visible, "empty popup explains how to get started");
            panel.symbols = [suite.firstSymbol];
            list.forceLayout();
            same(list.count, 1);
            same(placeholder.visible, false);
            panel.symbols = [];
            list.forceLayout();
            same(list.count, 0);
            same(placeholder.visible, true);
        });
    }

    // Use the real Qt tooltip popup, with plain multiline text rather than the host's single-line tooltip.
    function async_error_tooltip_renders_multiple_lines(done) {
        withPanel([firstSymbol, secondSymbol], done, function (panel, list) {
            panel.symbolErrors = ({
                    [suite.firstSymbol.uid]: {
                        price: {
                            userMessage: "No internet."
                        }
                    },
                    [suite.secondSymbol.uid]: {
                        graph: {
                            userMessage: "Chart unavailable."
                        }
                    }
                });
            let refresh = suite.button(panel, "refresh");
            let tooltip = null;
            for (let child of refresh.data) {
                if (child as Controls.ToolTip) {
                    tooltip = child;
                    break;
                }
            }
            check(tooltip !== null, "the refresh button owns a tooltip");
            let popup = tooltip as Controls.ToolTip;
            popup.open();
            same(popup.visible, true);
            same(popup.text, refresh.tooltipText);
            let text = popup.contentItem as Text;
            check(text !== null);
            same(text.textFormat, Text.PlainText);
            same(text.wrapMode, Text.Wrap);
            check(text.text.split("\n").length === 3, "heading and one line per affected symbol");
            check(text.implicitHeight > text.font.pixelSize * 2, "multiple lines have room to render");
            popup.close();
        });
    }

    // Partial cached data remains visible: a failed price must not hide a chart that already loaded.
    function async_failed_price_preserves_a_previously_loaded_chart(done) {
        withPanel([firstSymbol], done, function (panel, list) {
            panel.graphData = ({
                    [suite.firstSymbol.uid]: [
                        {
                            time: 1700000000,
                            close: 11
                        },
                        {
                            time: 1700003600,
                            close: 12
                        }
                    ]
                });
            panel.symbolErrors = ({
                    [suite.firstSymbol.uid]: {
                        price: {
                            userMessage: "No price available."
                        }
                    }
                });
            let row = list.itemAtIndex(0) as SymbolRow;
            let chart = suite.findItem(row, function (item) {
                return item as PriceChart;
            }) as PriceChart;
            check(chart !== null && chart.visible, "the existing chart remains visible");
            same(chart.dataPoints.length, 2);
            same(row.errorMessage, "No price available.");
            let error = suite.findItem(row, function (item) {
                return "text" in item && item.text === row.errorMessage;
            });
            check(error !== null && error.visible, "the card explains the missing price");
            same(suite.button(row, "refresh").pressable, true);
            same(suite.button(row, "refresh").visible, false, "card actions remain hidden until hovered");
            panel.graphData = ({});
            same(row.hasChart, false);
            same(chart.visible, false, "no placeholder chart obscures a first-fetch error");
        });
    }

    // Warning visibility follows every unresolved pull, even with cached data or a retry in progress.
    function async_header_warning_persists_until_every_failure_recovers(done) {
        withPanel([firstSymbol, secondSymbol], done, function (panel, list) {
            let refresh = suite.button(panel, "refresh");
            same(refresh.visible, false, "healthy header actions start hidden");
            let settings = suite.button(panel, "settings");
            same(settings.visible, false);
            panel.symbolErrors = ({
                    [suite.firstSymbol.uid]: {
                        price: {
                            userMessage: "No internet."
                        },
                        graph: {
                            userMessage: "No internet."
                        }
                    },
                    [suite.secondSymbol.uid]: {
                        change: {
                            userMessage: "Reference failed.",
                            details: "private"
                        }
                    }
                });
            same(refresh.visible, true);
            same(refresh.warning, true);
            same(settings.opacity, 0, "errors alone keep only refresh visible");
            same(settings.enabled, false, "hidden settings do not intercept clicks");
            check(refresh.tooltipText.indexOf("Euro: No internet.") !== -1);
            check(refresh.tooltipText.indexOf("Other Euro: Reference failed.") !== -1);
            check(refresh.tooltipText.indexOf("private") === -1);
            let badge = suite.findItem(refresh, function (item) {
                return "text" in item && item.text === "!";
            });
            check(badge !== null && badge.visible, "failed fetches display an exclamation badge");
            panel.pendingFetches = ({
                    [suite.firstSymbol.uid]: 1
                });
            same(refresh.warning, true, "retrying does not clear the warning");
            same(refresh.pressable, false);
            panel.pendingFetches = ({});
            panel.symbolErrors = ({
                    [suite.secondSymbol.uid]: {
                        change: {
                            userMessage: "Reference failed."
                        }
                    }
                });
            same(refresh.visible, true, "another symbol still has a failed pull");
            check(refresh.tooltipText.indexOf("No internet.") === -1, "recovered errors leave the tooltip");
            panel.symbolErrors = ({});
            same(refresh.warning, false);
            same(refresh.visible, false, "the header auto-hides once all errors recover");
            panel.symbolErrors = ({
                    removed: {
                        price: {
                            userMessage: "Old failure"
                        }
                    }
                });
            same(refresh.visible, false, "removed symbols do not keep warnings alive");
        }, false);
    }

    // Loading blocks repeat refreshes; failed refreshes preserve data and leave recovery actions usable.
    function async_loading_and_errors_keep_the_popup_usable(done) {
        withPanel([firstSymbol], done, function (panel, list) {
            let row = list.itemAtIndex(0) as SymbolRow;
            let refresh = suite.button(row, "refresh");
            let refreshAll = suite.button(panel, "refresh");
            let failure = {
                userMessage: "Could not refresh",
                details: "technical details"
            };
            panel.pendingFetches = ({
                    [suite.firstSymbol.uid]: 1
                });
            same(row.isLoading, true);
            same(refresh.pressable, false);
            same(refreshAll.pressable, false);
            same(refresh.spinning, true);
            let mouseArea = suite.findItem(refresh, function (item) {
                return item as MouseArea;
            }) as MouseArea;
            same(mouseArea.acceptedButtons, Qt.NoButton, "loading blocks clicks while keeping hover tooltips available");
            panel.pendingFetches = ({});
            panel.symbolErrors = ({
                    [suite.firstSymbol.uid]: {
                        price: failure
                    }
                });
            same(row.priceFailed, true);
            same(row.errorMessage, "Could not refresh");
            panel.priceData = ({
                    [suite.firstSymbol.uid]: {
                        close: 12,
                        change: 1,
                        changePercent: 2
                    }
                });
            panel.graphData = ({
                    [suite.firstSymbol.uid]: [
                        {
                            time: 1700000000,
                            close: 11
                        },
                        {
                            time: 1700003600,
                            close: 12
                        }
                    ]
                });
            panel.lastFetchTimes = ({
                    [suite.firstSymbol.uid + "_price"]: 1700003600000
                });
            same(row.price, 12);
            same(row.chartData.length, 2);
            same(row.lastFetchTime, 1700003600000);
            same(row.stale, true, "loaded values survive a failed refresh");
            same(row.priceFailed, false);
            same(refresh.pressable, true);
            same(refreshAll.pressable, true);
            same(suite.button(row, "push_pin").pressable, true);
            same(suite.button(row, "close").pressable, true);
            panel.symbolErrors = ({});
            same(row.stale, false, "successful recovery clears the stale state");
        });
    }

    // Wrapped error text and its icon are centered together within the unused part of the card.
    function async_missing_data_error_is_centered(done) {
        withPanel([firstSymbol], done, function (panel, list) {
            panel.symbolErrors = ({
                    [suite.firstSymbol.uid]: {
                        price: {
                            userMessage: "Can't reach Wise. Check your internet connection."
                        }
                    }
                });
            let row = list.itemAtIndex(0) as SymbolRow;
            let text = suite.findItem(row, function (item) {
                return "text" in item && item.text === row.errorMessage;
            });
            check(text !== null && text.visible);
            let group = text.parent, area = group.parent;
            check(group.height > 0, "wrapped content gives the centered group a real height");
            check(Math.abs(group.x + group.width / 2 - area.width / 2) < 1, "horizontally centered");
            check(Math.abs(group.y + group.height / 2 - area.height / 2) < 1, "vertically centered");
            check(Math.abs(text.mapToItem(row, 0, text.height / 2).y - row.height / 2) < 1, "text aligns with the card center");
        });
    }

    // Find a real action button by the icon it presents to the user.
    function button(parentItem: Item, iconName: string): IconButton {
        let found = findItem(parentItem, function (item) {
            return (item as IconButton) && item.iconName === iconName;
        }) as IconButton;
        check(found !== null, "button exists: " + iconName);
        return found;
    }

    // Search instantiated visual children without exposing private IDs through the production API.
    function findItem(parentItem: Item, predicate): Item {
        if (predicate(parentItem))
            return parentItem;
        for (let child of parentItem.children) {
            let match = findItem(child, predicate);
            if (match)
                return match;
        }
        return null;
    }

    // Wait for delegates and dispose of the window; hidden windows let visibility tests avoid pointer hover.
    function withPanel(symbols, done, action, showWindow) {
        popupWindow = windowType.createObject(null, {
            visible: showWindow !== false
        }) as Window;
        let panel = popupWindow.panel as PopoutPanel;
        panel.symbols = symbols;
        let list = findItem(panel, function (item) {
            return item as ListView;
        }) as ListView;
        list.forceLayout();
        waitUntil(function () {
            return list.count === symbols.length && (!symbols.length || list.itemAtIndex(symbols.length - 1) !== null);
        }, function (problem) {
            try {
                if (problem)
                    throw new Error(problem);
                action(panel, list);
                done("");
            } catch (error) {
                done(error.message);
            } finally {
                suite.popupWindow.destroy();
                suite.popupWindow = null;
            }
        });
    }
}
