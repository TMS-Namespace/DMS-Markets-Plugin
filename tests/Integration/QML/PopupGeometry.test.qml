// PopupGeometry.test.qml - measure card margins and height through the real widget content and Dux's outer inset.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import "../../../src/QML/Views"
import "../../Helpers"
import qs.Common

TestSuite {
    id: suite

    property Window popupWindow: null
    property var widget: null
    property Component windowType: Component {
        Window {
            id: hostWindow

            property alias content: contentLoader.item
            property Component popupContent: null

            height: contentLoader.item ? contentLoader.item.implicitHeight + 2 * PopoutMetrics.contentPadding : 1
            visible: true
            width: 600

            // Mirror PluginPopout's Loader geometry, including its fixed host padding.
            Loader {
                id: contentLoader

                sourceComponent: hostWindow.popupContent
                width: hostWindow.width - 2 * PopoutMetrics.contentPadding
                x: PopoutMetrics.contentPadding
                y: PopoutMetrics.contentPadding
            }
        }
    }

    // Extra requested rows must not reserve empty space below a shorter symbol list.
    function async_fewer_symbols_than_the_row_limit_have_no_extra_chin(done) {
        let list = openPopup(2, 10);
        waitUntil(function () {
            return list.itemAtIndex(1) !== null;
        }, function (problem) {
            try {
                check(!problem, problem);
                checkInsets(list, 1, true);
                let height = popupWindow.height;
                widget.popoutRows = 50;
                same(popupWindow.height, height, "unused rows do not change the popup height");
                done("");
            } catch (error) {
                done(error.message);
            }
        });
    }

    // A scrolling list keeps equal card insets, including its last card after scrolling to the end.
    function async_scrollbar_uses_the_gutter_and_last_card_reaches_the_bottom(done) {
        let list = openPopup(8, 3);
        checkInsets(list, 0, false);
        list.positionViewAtEnd();
        list.forceLayout();
        waitUntil(function () {
            return list.itemAtIndex(7) !== null;
        }, function (problem) {
            try {
                check(!problem, problem);
                checkInsets(list, 7, true);
                done("");
            } catch (error) {
                done(error.message);
            }
        });
    }

    // Changing the setting on an open popup must grow by real card heights and gaps, without accumulated slack.
    function async_visible_row_counts_keep_the_same_bottom_gap(done) {
        let list = openPopup(10, 1);
        waitUntil(function () {
            let row = list.itemAtIndex(0) as SymbolRow;
            return row !== null && popupWindow.height - row.mapToItem(popupWindow.contentItem, 0, row.height).y === Theme.spacingS;
        }, function (problem) {
            if (problem) {
                done(problem);
                return;
            }
            let row = list.itemAtIndex(0) as SymbolRow;
            suite.same(list.height, row.height, "one row has exactly one card's height");
            suite.checkRowCount(list, [1, 3, 10], 0, suite.popupWindow.height, row.height, done);
        });
    }

    // Check actual card borders in window coordinates, including any compensated host padding.
    function checkInsets(list, index, bottom) {
        let row = list.itemAtIndex(index) as SymbolRow;
        check(row !== null, "visible card exists");
        let position = row.mapToItem(popupWindow.contentItem, 0, 0);
        same(position.x, Theme.spacingS, "left inset");
        same(popupWindow.width - position.x - row.width, Theme.spacingS, "right inset");
        if (bottom)
            same(popupWindow.height - position.y - row.height, Theme.spacingS, "bottom inset");
    }

    // Wait for the host's Column to reposition children after each live setting change.
    function checkRowCount(list, counts, index, firstHeight, rowHeight, done) {
        if (index === counts.length) {
            done("");
            return;
        }
        let count = counts[index];
        widget.popoutRows = count;
        list.forceLayout();
        let expectedHeight = firstHeight + (count - 1) * (rowHeight + list.spacing);
        waitUntil(function () {
            return popupWindow.height === expectedHeight && list.itemAtIndex(count - 1) !== null;
        }, function (problem) {
            try {
                check(!problem, problem);
                same(list.height, count * rowHeight + (count - 1) * list.spacing, "list fits visible cards");
                checkInsets(list, 0, false);
                checkInsets(list, count - 1, true);
                checkRowCount(list, counts, index + 1, firstHeight, rowHeight, done);
            } catch (error) {
                done(error.message);
            }
        }, 2000, function () {
            return "height " + popupWindow.height + ", expected " + expectedHeight;
        });
    }

    // Traverse real visual children without adding test-only properties to production views.
    function findList(parentItem): ListView {
        if (parentItem as ListView)
            return parentItem;
        for (let child of parentItem.children) {
            let found = findList(child);
            if (found)
                return found;
        }
        return null;
    }

    // Start with no saved symbols; layout-only symbols have no uid, so no network work is scheduled.
    function openPopup(count, visibleRows): ListView {
        popupWindow = windowType.createObject(null) as Window;
        let component = Qt.createComponent("file://" + repoRoot + "/src/QML/Widget.qml");
        check(component.status === Component.Ready, component.errorString());
        widget = component.createObject(popupWindow, {
            cacheDirectory: freshDirectory("popup-geometry")
        });
        check(widget !== null);
        let symbols = [];
        for (let i = 0; i < count; i++)
            symbols.push({
                uid: "",
                ticker: "EURUSD=X",
                name: "Symbol " + i,
                provider: "yahoo",
                priceResolution: "1h",
                chartRange: "1M"
            });
        widget.symbols = symbols;
        widget.popoutRows = visibleRows;
        popupWindow.popupContent = widget.popoutContent;
        check(popupWindow.content !== null, "the widget popup loads");
        let list = findList(popupWindow.content);
        check(list !== null);
        list.forceLayout();
        return list;
    }

    // Destroy the widget with its host window before the next case starts.
    function teardown() {
        if (popupWindow)
            popupWindow.destroy();
        popupWindow = null;
        widget = null;
    }

    // The empty placeholder sizes itself independently of the configured number of visible cards.
    function test_empty_popup_does_not_reserve_fifty_cards() {
        let list = openPopup(0, 1);
        let height = popupWindow.height;
        widget.popoutRows = 50;
        same(popupWindow.height, height);
        same(list.count, 0);
        check(height > 0 && height < 300, "empty state stays compact and visible");
    }
}
