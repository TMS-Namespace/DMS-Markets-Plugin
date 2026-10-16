// The settings page the way DMS loads it: a Loader creates the page FIRST, and only afterwards sets its pluginService
// (onLoaded). The real DMS controls save on every value change, even before the service exists, and the plugin data
// can change later (the widget migrates the saved symbols). Nothing of that may produce an error toast, and the list of
// configured symbols must fill in once the service arrives and follow later data changes.
import QtQuick
import qs.Services
import "../../Helpers"
import "../../../src/QML/Services"

TestSuite {
    id: suite

    // Like DMS's PluginService: saving changes the data and announces it.
    property Component serviceType: Component {
        QtObject {
            id: service
            property var data: ({})
            signal pluginDataChanged(string pluginId)
            property var availablePlugins: ({})
            function loadPluginData(id, key, fallback) { return key in data ? data[key] : fallback }
            function savePluginData(id, key, value) { var copy = Object.assign({}, data); copy[key] = value; data = copy; pluginDataChanged(id) }
            function getPluginVariants(id) { return [] }
        }
    }
    property Component loaderType: Component {
        Loader {
            width: 600; height: 800
            asynchronous: false
            property var service: null
            onLoaded: { item.pluginService = service }      // after loading, as DMS does
        }
    }
    property var loader: null
    property var service: null
    property var pollCondition: null
    property var pollDone: null
    property int pollsLeft: 0
    property Timer poller: Timer {
        interval: 50; repeat: true
        onTriggered: {
            if (suite.pollCondition()) { stop(); suite.pollDone("") }
            else if (--suite.pollsLeft <= 0) { stop(); suite.pollDone("timed out: list " + (suite.loader.item ? suite.loader.item.symbolsList.length : -1) + ", toasts " + JSON.stringify(ToastService.errors)) }
        }
    }
    function waitFor(condition, done) { pollCondition = condition; pollDone = done; pollsLeft = 60; poller.start() }

    function setup() {
        if (loader) { loader.destroy(); loader = null }
        ToastService.errors = []; ToastService.infos = []
        ErrorHandler.reset(); Logger.configure({ devMode: false })
        ProvidersManager.reload(ProvidersManager.sources)
    }
    function open(data) {
        service = serviceType.createObject(null, { data: data })
        loader = loaderType.createObject(null, { service: service, source: "file://" + repoRoot + "/src/QML/Settings.qml" })
        check(loader.status === Loader.Ready, "the page loads: " + loader.status)
        return loader.item
    }
    readonly property var older: [{ id: "EURUSD=X", name: "EUR", provider: "yahoo", priceInterval: "1h", graphInterval: "1M", showChangeWhenPinned: false, invert: false, pinned: false },
                                  { id: "DX-Y.NYB", name: "USDX", provider: "yahoo", priceInterval: "1h", graphInterval: "1M", showChangeWhenPinned: false, invert: false, pinned: true },
                                  { id: "BRLPLN", name: "BRL/PLN", provider: "wise", priceInterval: "1h", graphInterval: "1M", showChangeWhenPinned: false, invert: false, pinned: false }]
    readonly property var current: [{ uid: "11111111-1111-4111-8111-111111111111", ticker: "EURUSD=X", name: "EUR", provider: "yahoo", priceResolution: "1h", chartResolution: "1d", chartRange: "1M", showChangeWhenPinned: false, invert: false, pinned: false }]

    function async_symbols_saved_by_an_older_version_are_listed_once_the_service_arrives(done) {
        var page = open({ symbols: JSON.stringify(older) })
        waitFor(function() { return page.symbolsList.length === 3 }, function(problem) {
            if (problem) { done(problem); return }
            try {
                check(page.symbolsList.every(function(symbol) { return symbol.uid && symbol.ticker }), "migrated")
                equal(ToastService.errors, [], "no error toast")
                done("")
            } catch (e) { done(e.message) }
        })
    }
    function async_symbols_in_the_current_format_are_listed(done) {
        var page = open({ symbols: JSON.stringify(current) })
        waitFor(function() { return page.symbolsList.length === 1 }, function(problem) {
            try { if (problem) { done(problem); return } equal(ToastService.errors, [], "no error toast"); done("") } catch (e) { done(e.message) }
        })
    }
    function async_the_list_follows_plugin_data_that_changes_later(done) {
        var page = open({})
        service.data = { symbols: JSON.stringify(current) }      // e.g. the widget saved, or DMS delivered the data late
        service.pluginDataChanged("markets")
        waitFor(function() { return page.symbolsList.length === 1 }, function(problem) {
            try { if (problem) { done(problem); return } equal(ToastService.errors, [], "no error toast"); done("") } catch (e) { done(e.message) }
        })
    }
    function test_nothing_is_reported_while_the_service_is_not_attached_yet() {
        var component = Qt.createComponent("file://" + repoRoot + "/src/QML/Settings.qml")
        check(component.status === Component.Ready, component.errorString())
        var page = component.createObject(null, { pluginId: "markets" })      // no service, like the moment after the Loader created it
        check(page !== null)
        same(page.saveValue("_addProvider", "yahoo"), false, "a control saving before the service exists saves nothing...")
        equal(ToastService.errors, [], "the controls saving their defaults before the service exists is not an error")
        page.destroy()
    }

    // What was typed or chosen in the "add a symbol" form last time is not brought back when the page is expanded again.
    function async_the_add_form_always_starts_from_its_defaults(done) {
        var left = { _addTicker: "EURUSD=X", _addName: "Old", _addProvider: "wise", _addPriceResolution: "1d", _addChartRange: "1Y", _addShowChange: true, _addInvert: true }
        var page = open(Object.assign({ symbols: JSON.stringify(current) }, left))
        waitFor(function() { return page._formReset && page.tickerText === "" && page.nameText === "" }, function(problem) {
            if (problem) { done(problem); return }
            // give the deferred reset and DMS's own loads time to settle, then look again
            waitFor(function() { return false }, function() {
                try {
                    same(page.tickerText, "", "no ticker"); same(page.nameText, "", "no name")
                    same(page.selectedProviderId, "yahoo", "the default provider")
                    same(service.data._addShowChange, false); same(service.data._addInvert, false)
                    same(service.data._addTicker, "", "the saved draft was reset too"); same(service.data._addName, "")
                    same(service.data._addProvider, "yahoo")
                    equal(ToastService.errors, [], "no error")
                    done("")
                } catch (e) { done(e.message) }
            })
        })
    }

    // The popup height set before a restart is what the slider shows once the page has its service (not its default).
    function async_the_popup_height_slider_shows_the_saved_value(done) {
        var page = open({ symbols: JSON.stringify(current), popoutRows: 10 })
        waitFor(function() { return page.popoutRowsValue === 10 }, function(problem) {
            if (problem) { done(problem + " (shows " + page.popoutRowsValue + ")"); return }
            waitFor(function() { return false }, function() {
                try {
                    same(page.popoutRowsValue, 10, "still the saved value after everything settled")
                    same(service.data.popoutRows, 10, "and it was not overwritten by the default")
                    done("")
                } catch (e) { done(e.message) }
            })
        })
    }

    // ── Picking a configured symbol fills EVERY field of the form from it ────
    readonly property var twoSymbols: [
        { uid: "11111111-1111-4111-8111-111111111111", ticker: "EURUSD=X", name: "EUR", provider: "yahoo", priceResolution: "5m", changeResolution: "1w", chartResolution: "1h", chartRange: "1W", showChangeWhenPinned: true, invert: true, pinned: false },
        { uid: "22222222-2222-4222-8222-222222222222", ticker: "BRLPLN", name: "BRL/PLN", provider: "wise", priceResolution: "1d", changeResolution: "1h", chartResolution: "1d", chartRange: "3M", showChangeWhenPinned: false, invert: false, pinned: true }]
    function fieldsOf(symbol) {
        return { ticker: symbol.ticker, name: symbol.name, provider: symbol.provider, priceResolution: symbol.priceResolution, changeResolution: symbol.changeResolution,
                 chartResolution: symbol.chartResolution, chartRange: symbol.chartRange, showChange: symbol.showChangeWhenPinned, invert: symbol.invert }
    }
    function settled(page, done, action) {
        // The controls load their values from the saved draft when plugin data changes: let everything settle, then look.
        waitFor(function() { return false }, function() { try { action(); done("") } catch (e) { done(e.message) } })
    }
    function async_picking_a_configured_symbol_sets_every_field_even_after_the_form_was_changed(done) {
        var page = open({ symbols: JSON.stringify(twoSymbols) })
        waitFor(function() { return page.symbolsList.length === 2 && page._formReset }, function(problem) {
            if (problem) { done(problem); return }
            settled(page, done, function() {
                // The user plays with the form (what the controls do: save their draft key)…
                service.savePluginData("markets", "_addChartRange", "1M"); service.savePluginData("markets", "_addPriceResolution", "1h")
                service.savePluginData("markets", "_addInvert", true)
                // …then picks the first symbol, then the second, then the first again.
                page.editSymbol(0); equal(page.formState, fieldsOf(twoSymbols[0]), "first symbol")
                page.editSymbol(1); equal(page.formState, fieldsOf(twoSymbols[1]), "second symbol")
                page.editSymbol(0); equal(page.formState, fieldsOf(twoSymbols[0]), "first symbol again")
            })
        })
    }
    function async_every_field_is_set_from_the_symbol_after_changing_each_dropdown_in_turn(done) {
        var page = open({ symbols: JSON.stringify(twoSymbols) })
        waitFor(function() { return page.symbolsList.length === 2 && page._formReset }, function(problem) {
            if (problem) { done(problem); return }
            settled(page, done, function() {
                ;["_addProvider", "_addPriceResolution", "_addChangeResolution", "_addChartResolution", "_addChartRange", "_addShowChange", "_addInvert"].forEach(function(key) {
                    service.savePluginData("markets", key, key === "_addProvider" ? "wise" : (key === "_addShowChange" || key === "_addInvert" ? true : "1d"))
                    page.editSymbol(0)
                    equal(page.formState, fieldsOf(twoSymbols[0]), "after changing " + key)
                    page.cancelEdit()
                })
            })
        })
    }

    // ── The symbol's own settings are locked until there is a valid ticker and name ──
    function async_the_symbol_settings_unlock_with_a_valid_ticker_and_name_and_for_a_picked_symbol(done) {
        var page = open({ symbols: JSON.stringify(twoSymbols) })
        waitFor(function() { return page.symbolsList.length === 2 && page._formReset }, function(problem) {
            if (problem) { done(problem); return }
            settled(page, done, function() {
                same(page.formUnlocked, false, "an empty form is locked")
                var base = { provider: "yahoo", priceResolution: "1h", changeResolution: "1d", chartResolution: "1d", chartRange: "1M", showChange: false, invert: false }
                page.setDraft(Object.assign({ ticker: "EURUSD=X", name: "" }, base));  same(page.formUnlocked, false, "a ticker without a name stays locked")
                page.setDraft(Object.assign({ ticker: "", name: "EUR" }, base));        same(page.formUnlocked, false, "a name without a ticker stays locked")
                page.setDraft(Object.assign({ ticker: "NOT A TICKER", name: "EUR" }, base)); same(page.formUnlocked, false, "an invalid ticker stays locked")
                page.setDraft(Object.assign({ ticker: "EURUSD=X", name: "a;b" }, base)); same(page.formUnlocked, false, "an invalid name stays locked")
                page.setDraft(Object.assign({ ticker: "EURUSD=X", name: "EUR USD" }, base)); same(page.formUnlocked, true, "a valid ticker and name unlock it")
                page.clearForm();                                                       same(page.formUnlocked, false, "clearing locks it again")
                page.editSymbol(1);                                                     same(page.formUnlocked, true, "a picked symbol has both: unlocked")
                page.cancelEdit();                                                      same(page.formUnlocked, false, "deselecting locks it again")
                // The ticker is validated against the provider, so the provider stays choosable while locked.
                page.setDraft(Object.assign({ ticker: "BRLPLN", name: "BRL" }, base, { provider: "wise" })); same(page.formUnlocked, true)
            })
        })
    }
}
