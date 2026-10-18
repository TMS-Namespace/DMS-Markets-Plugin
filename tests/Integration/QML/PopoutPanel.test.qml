// Exercise the real popup in a headless window: list updates, action routing, and loading/error recovery.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import "../../Helpers"
import "../../../src/QML/Views"

TestSuite {
    id: suite

    readonly property var firstSymbol: ({ uid: "11111111-1111-4111-8111-111111111111", ticker: "EURUSD=X", name: "Euro", provider: "yahoo", priceResolution: "1h", chartRange: "1M", pinned: false })
    // A duplicate ticker makes accidental routing by ticker instead of saved-symbol ID detectable.
    readonly property var secondSymbol: Object.assign({}, firstSymbol, { uid: "22222222-2222-4222-8222-222222222222", name: "Other Euro", pinned: true })
    property Window popupWindow: null
    property Component windowType: Component {
        Window {
            width: 600; height: 360; visible: true
            property alias panel: popupPanel
            PopoutPanel {
                id: popupPanel
                anchors.fill: parent
                anchors.topMargin: 60
                headerOffset: 60
                upColor: "green"; downColor: "red"
            }
        }
    }

    // Search instantiated visual children without exposing private IDs through the production API.
    function findItem(parentItem: Item, predicate): Item {
        if (predicate(parentItem)) return parentItem
        for (let child of parentItem.children) {
            let match = findItem(child, predicate)
            if (match) return match
        }
        return null
    }

    // Find a real action button by the icon it presents to the user.
    function button(parentItem: Item, iconName: string): IconButton {
        let found = findItem(parentItem, function(item) { return (item as IconButton) && item.iconName === iconName }) as IconButton
        check(found !== null, "button exists: " + iconName)
        return found
    }

    // Wait for ListView delegates, then run assertions and always dispose of the window.
    function withPanel(symbols, done, action) {
        popupWindow = windowType.createObject(null) as Window
        let panel = popupWindow.panel as PopoutPanel
        panel.symbols = symbols
        let list = findItem(panel, function(item) { return item as ListView }) as ListView
        list.forceLayout()
        waitUntil(function() { return list.count === symbols.length && (!symbols.length || list.itemAtIndex(symbols.length - 1) !== null) }, function(problem) {
            try {
                if (problem) throw new Error(problem)
                action(panel, list)
                done("")
            } catch (error) { done(error.message) }
            finally { suite.popupWindow.destroy(); suite.popupWindow = null }
        })
    }

    // The placeholder must follow model changes, including removal of the final symbol.
    function async_empty_state_follows_the_symbol_list(done) {
        withPanel([], done, function(panel, list) {
            let placeholder = findItem(panel, function(item) { return "text" in item && item.text === "No symbols added" })
            check(placeholder !== null && placeholder.visible, "empty popup explains how to get started")
            panel.symbols = [suite.firstSymbol]
            list.forceLayout()
            same(list.count, 1)
            same(placeholder.visible, false)
            panel.symbols = []
            list.forceLayout()
            same(list.count, 0)
            same(placeholder.visible, true)
        })
    }

    // Activate actual button signals and verify the panel forwards the selected row's stable ID.
    function async_actions_target_the_selected_symbol(done) {
        withPanel([firstSymbol, secondSymbol], done, function(panel, list) {
            let events = []
            panel.togglePin.connect(function(uid) { events.push(["pin", uid]) })
            panel.removeSymbol.connect(function(uid) { events.push(["remove", uid]) })
            panel.refreshSymbol.connect(function(uid) { events.push(["refresh", uid]) })
            panel.refreshAll.connect(function() { events.push(["all"]) })
            panel.closePopout.connect(function() { events.push(["close"]) })
            let row = list.itemAtIndex(1) as SymbolRow
            same(row.isPinned, true)
            suite.button(row, "push_pin").clicked()
            suite.button(row, "close").clicked()
            suite.button(row, "refresh").clicked()
            suite.button(panel, "refresh").clicked()
            suite.button(panel, "close").clicked()
            suite.equal(events, [["pin", suite.secondSymbol.uid], ["remove", suite.secondSymbol.uid],
                ["refresh", suite.secondSymbol.uid], ["all"], ["close"]])
        })
    }

    // Loading blocks repeat refreshes; failed refreshes preserve data and leave recovery actions usable.
    function async_loading_and_errors_keep_the_popup_usable(done) {
        withPanel([firstSymbol], done, function(panel, list) {
            let row = list.itemAtIndex(0) as SymbolRow
            let refresh = suite.button(row, "refresh")
            let refreshAll = suite.button(panel, "refresh")
            let failure = { userMessage: "Could not refresh", details: "technical details" }
            panel.pendingFetches = ({ [suite.firstSymbol.uid]: 1 })
            same(row.isLoading, true)
            same(refresh.pressable, false)
            same(refreshAll.pressable, false)
            same(refresh.spinning, true)
            let mouseArea = suite.findItem(refresh, function(item) { return item as MouseArea }) as MouseArea
            same(mouseArea.enabled, false, "disabled refresh also disables its input handler")
            panel.pendingFetches = ({})
            panel.symbolErrors = ({ [suite.firstSymbol.uid]: { price: failure } })
            same(row.priceFailed, true)
            same(row.errorMessage, "Could not refresh")
            panel.priceData = ({ [suite.firstSymbol.uid]: { close: 12, change: 1, changePercent: 2 } })
            panel.graphData = ({ [suite.firstSymbol.uid]: [{ time: 1700000000, close: 11 }, { time: 1700003600, close: 12 }] })
            panel.lastFetchTimes = ({ [suite.firstSymbol.uid + "_price"]: 1700003600000 })
            same(row.price, 12)
            same(row.chartData.length, 2)
            same(row.lastFetchTime, 1700003600000)
            same(row.stale, true, "loaded values survive a failed refresh")
            same(row.priceFailed, false)
            same(refresh.pressable, true)
            same(refreshAll.pressable, true)
            same(suite.button(row, "push_pin").pressable, true)
            same(suite.button(row, "close").pressable, true)
            panel.symbolErrors = ({})
            same(row.stale, false, "successful recovery clears the stale state")
        })
    }
}
