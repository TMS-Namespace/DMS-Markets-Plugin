// Behaviour of Settings.qml's own functions, run on the real runtime against the real ProvidersManager
// and DataStorage; only the DMS controls (dropdowns, toggles, toasts) are stubs.
import QtQuick
import "../../Helpers"
import "../../../src/QML/Helpers"
import "../../../src/QML/Services"
import "../../../src/JS/Helpers/Helpers.js" as Helpers
import "../../../src/JS/Helpers/SymbolDraft.js" as SymbolDraft

TestSuite {
    id: suite

    property Component storageType: Component { DataStorage {} }
    property Component serviceType: Component {
        QtObject {
            property var data: ({})
            property var failWith: null
            function loadPluginData(id, key, fallback) { return key in data ? data[key] : fallback }
            function savePluginData(id, key, value) { if (failWith) throw failWith; data[key] = value }
        }
    }
    property var toasts: []
    property var errors: []
    property var infos: []
    property var saved: ({})

    function setup() {
        ErrorHandler.reset(); toasts = []; errors = []; infos = []; saved = ({})
        ErrorHandler.configure({ notify: function(message, details, category) { toasts.push({ message: message, details: details, category: category }) } })
    }

    function control(value) { return { value: value } }
    function service(initial, failWith) { return serviceType.createObject(null, { data: initial || ({}), failWith: failWith || null }) }
    function scopeFor(pluginService) {
        var scope = {
            ProvidersManager: ProvidersManager, SymbolDraft: SymbolDraft, ErrorHandler: ErrorHandler, Logger: Logger, Helpers: Helpers, selectedProviderId: "yahoo",
            storage: pluginService ? storageType.createObject(null, { pluginId: "markets", pluginService: pluginService }) : null,
            priceResolutionSelect: control("1m"), changeResolutionSelect: control("1d"), chartResolutionSelect: control("1m"), chartRangeSelect: control("1D"),
            providerSelect: control("yahoo"), tickerInput: control(""), nameInput: control(""),
            showChangeToggle: control(false), invertToggle: control(false),
            symbolsList: [], editIndex: -1,
            root: { saveValue: function(key, value) { saved[key] = value } },
            ToastService: { showError: function(title, message) { errors.push(message) }, showInfo: function(title, message) { infos.push(message) } },
            Qt: { callLater: function(action) { action() } }
        }
        // Settings reads the selected provider's handler from the manager; it follows the selected id.
        Object.defineProperty(scope, "selectedHandler", { get: function() { return ProvidersManager.handlerFromId(scope.selectedProviderId) } })
        scope.clearForm = function() { scope.cleared = true }
        scope.refreshSymbolsList = function() { scope.refreshed = true }
        return scope
    }
    function settingsFunction(name, scope) { return loadFunction("src/QML/Settings.qml", name, scope) }
    function triple(scope) { return [scope.priceResolutionSelect.value, scope.chartResolutionSelect.value, scope.chartRangeSelect.value] }

    // ── syncSelections ───────────────────────────────────────────────────────
    function test_switching_to_wise_snaps_choices_to_what_wise_serves() {
        var scope = scopeFor(null); scope.selectedProviderId = "wise"
        scope.priceResolutionSelect.value = "5m"; scope.chartResolutionSelect.value = "15m"; scope.chartRangeSelect.value = "1Y"
        settingsFunction("syncSelections", scope)()
        equal(triple(scope), ["1h", "1h", "1W"], "no 5m/15m at Wise; a year of hourly candles is not allowed")
    }
    function test_a_valid_choice_is_left_alone() {
        var scope = scopeFor(null)
        scope.priceResolutionSelect.value = "15m"; scope.chartResolutionSelect.value = "1d"; scope.chartRangeSelect.value = "3M"
        settingsFunction("syncSelections", scope)()
        equal(triple(scope), ["15m", "1d", "3M"])
    }
    function test_changing_the_resolution_refilters_the_span() {
        var scope = scopeFor(null)
        scope.priceResolutionSelect.value = "1h"; scope.chartResolutionSelect.value = "1m"; scope.chartRangeSelect.value = "1Y"
        settingsFunction("syncSelections", scope)()
        equal([scope.chartResolutionSelect.value, scope.chartRangeSelect.value], ["1m", "3H"])
    }
    function test_empty_first_run_values_resolve_to_a_servable_default() {
        var scope = scopeFor(null); scope.selectedProviderId = "wise"
        scope.priceResolutionSelect.value = ""; scope.chartResolutionSelect.value = ""; scope.chartRangeSelect.value = ""
        settingsFunction("syncSelections", scope)()
        var wise = ProvidersManager.handlerFromId("wise")
        check(wise.priceResolutionOptions().some(function(option) { return option.value === scope.priceResolutionSelect.value }))
        check(wise.chartSpanOptions(scope.chartResolutionSelect.value).some(function(option) { return option.value === scope.chartRangeSelect.value }))
    }

    // ── setDraft / clearForm / editSymbol ────────────────────────────────────
    function test_a_draft_is_clamped_shown_and_saved_by_the_storage() {
        var pluginService = service(), scope = scopeFor(pluginService)
        settingsFunction("setDraft", scope)({ ticker: "BRLPLN", name: "Real", provider: "wise", priceResolution: "5m", changeResolution: "1d", chartResolution: "", chartRange: "10Y", showChange: true, invert: false })
        equal(triple(scope), ["1h", "1d", "6M"])
        same(scope.providerSelect.value, "wise"); same(scope.showChangeToggle.value, true); same(scope.invertToggle.value, false)
        equal([pluginService.data._addPriceResolution, pluginService.data._addChartResolution, pluginService.data._addChartRange], ["1h", "1d", "6M"], "clamped values are what gets persisted")
        same(pluginService.data._addProvider, "wise"); same(pluginService.data._addTicker, "BRLPLN"); same(pluginService.data._addShowChange, true)
    }
    function test_clear_form_starts_at_the_provider_default() {
        var scope = scopeFor(null), draft = null
        scope.editIndex = 5; scope.setDraft = function(value) { draft = value }
        settingsFunction("clearForm", scope)()
        equal(draft, { ticker: "", name: "", provider: "yahoo", priceResolution: "1h", changeResolution: "1d", chartResolution: "1d", chartRange: "1M", showChange: false, invert: false }, "1h price, 1 day candles over 1 month")
        same(scope.editIndex, -1)
    }
    function test_editing_loads_the_ticker_and_all_three_ranges() {
        var scope = scopeFor(null), draft = null
        scope.symbolsList = [{ uid: "u", ticker: "BRLPLN", name: "Real", provider: "wise", priceResolution: "1h", changeResolution: "1d", chartResolution: "1d", chartRange: "1M", showChangeWhenPinned: true, invert: false }]
        scope.setDraft = function(value) { draft = value }; scope.cancelEdit = function() {}
        settingsFunction("editSymbol", scope)(0)
        equal(draft, { ticker: "BRLPLN", name: "Real", provider: "wise", priceResolution: "1h", changeResolution: "1d", chartResolution: "1d", chartRange: "1M", showChange: true, invert: false })
    }

    // ── addOrUpdateSymbol ────────────────────────────────────────────────────
    function add(ticker, provider, existing, editIndex) {
        var scope = scopeFor(null), submitted = []
        scope.tickerInput.value = ticker; scope.nameInput.value = "Name"; scope.providerSelect.value = provider
        scope.symbolsList = existing || []; scope.editIndex = editIndex === undefined ? -1 : editIndex
        scope.doSaveSymbol = function(tickerText, displayName) { submitted.push([tickerText, displayName]) }
        settingsFunction("addOrUpdateSymbol", scope)()
        return submitted
    }
    function test_symbols_are_validated_against_the_providers_rules() {
        equal(add("BRLPLN", "wise"), [["BRLPLN", "Name"]])
        same(add("EURUSD=X", "wise").length, 0, "a Yahoo symbol is not saved for Wise"); check(/currency codes/.test(errors[0]), "the user is told the format")
        ;["BRL PLN", "BRL;PLN", "$(id)", "BRL\nPLN", "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"].forEach(function(bad) { same(add(bad, "wise").length, 0, JSON.stringify(bad)) })
        equal(add("  BRLPLN  ", "wise"), [["BRLPLN", "Name"]], "surrounding whitespace is trimmed, not rejected")
        same(add("BRLPLN", "wise", [{ ticker: "BRLPLN", uid: "x" }]).length, 0, "duplicates are refused"); check(/already added/.test(errors[errors.length - 1]))
        same(add("BRLPLN", "wise", [{ ticker: "BRLPLN", uid: "x" }], 0).length, 1, "...except the symbol being edited")
    }

    // ── doSaveSymbol ─────────────────────────────────────────────────────────
    function test_a_blocked_chart_is_refused_a_warned_one_is_saved() {
        var pluginService = service(), scope = scopeFor(pluginService)
        scope.providerSelect.value = "wise"; scope.priceResolutionSelect.value = "1h"
        scope.chartResolutionSelect.value = "1d"; scope.chartRangeSelect.value = "1Y"            // 365 candles → blocked
        settingsFunction("doSaveSymbol", scope)("BRLPLN", "Real")
        same(errors.length, 1); check(/cannot be used/.test(errors[0])); same(pluginService.data.symbols, undefined, "nothing is saved")
        scope.chartRangeSelect.value = "6M"                                                    // 182 candles → warn
        settingsFunction("doSaveSymbol", scope)("BRLPLN", "Real")
        same(JSON.parse(pluginService.data.symbols).length, 1, "a warned combination is still saved")
    }
    function save(list, editIndex, overrides) {
        var pluginService = service(), scope = scopeFor(pluginService)
        scope.providerSelect.value = "wise"; scope.priceResolutionSelect.value = "1h"; scope.chartResolutionSelect.value = "1d"; scope.chartRangeSelect.value = "1M"
        scope.showChangeToggle.value = true; scope.symbolsList = list; scope.editIndex = editIndex
        for (var field in overrides) scope[field] = overrides[field]
        settingsFunction("doSaveSymbol", scope)("BRLPLN", "Real")
        return pluginService.data.symbols ? JSON.parse(pluginService.data.symbols) : null
    }
    function test_new_symbols_get_a_uid_and_the_ticker_field() {
        var added = save([], -1)[0]
        same(added.ticker, "BRLPLN"); check(!("id" in added)); check(Helpers.isUuid(added.uid))
        equal([added.priceResolution, added.chartResolution, added.chartRange, added.provider], ["1h", "1d", "1M", "wise"])
        same(added.pinned, false); check(added.uid !== save([], -1)[0].uid, "every new symbol gets its own uid")
    }
    function test_editing_keeps_the_uid_and_pin() {
        var existing = [{ uid: "11111111-1111-4111-8111-111111111111", ticker: "BRLPLN", pinned: true }]
        var edited = save(existing, 0, { chartRangeSelect: control("3M") })[0]
        same(edited.uid, "11111111-1111-4111-8111-111111111111"); same(edited.pinned, true); same(edited.chartRange, "3M")
        var appended = save(existing, -1)
        same(appended.length, 2); check(appended[1].uid !== appended[0].uid)
        check(Helpers.isUuid(save([{ ticker: "OLD", pinned: false }], 0)[0].uid), "an old symbol without a uid gets one")
    }

    // ── Reading, announcing ──────────────────────────────────────────────────
    function test_corrupt_saved_symbols_are_reported_and_backed_up() {
        var pluginService = service({ symbols: "{this is not json" }), scope = scopeFor(pluginService)
        scope.symbolsList = ["stale"]
        settingsFunction("refreshSymbolsList", scope)()
        equal(scope.symbolsList, []); same(pluginService.data.symbolsBackup, "{this is not json"); same(pluginService.data.symbols, "{this is not json")
        same(toasts.length, 1); same(toasts[0].message, "Your saved symbols couldn't be read."); same(toasts[0].category, "markets-storage")
    }
    function test_a_healthy_legacy_list_is_shown_migrated_and_persisted_once() {
        var pluginService = service({ symbols: JSON.stringify([{ id: "BRLPLN", provider: "wise", priceInterval: "5m", graphInterval: "1Y" }]) }), scope = scopeFor(pluginService)
        settingsFunction("refreshSymbolsList", scope)()
        same(scope.symbolsList[0].ticker, "BRLPLN"); same(scope.symbolsList[0].chartRange, "6M")
        same(JSON.parse(pluginService.data.symbols)[0].uid, scope.symbolsList[0].uid); same(toasts.length, 0)
    }
    function announce(name, extra, call, failing) {
        setup()
        var pluginService = service({}, failing ? new Error("disk full") : null), scope = scopeFor(pluginService)
        scope.providerSelect.value = "wise"; scope.priceResolutionSelect.value = "1h"; scope.chartResolutionSelect.value = "1d"; scope.chartRangeSelect.value = "1M"
        for (var field in extra) scope[field] = extra[field]
        call(settingsFunction(name, scope))
        return { scope: scope, pluginService: pluginService }
    }
    function test_success_is_only_announced_when_the_save_worked() {
        ;[false, true].forEach(function(failing) {
            var label = failing ? "failed" : "saved"
            var added = announce("doSaveSymbol", {}, function(callback) { callback("BRLPLN", "Real") }, failing)
            same(infos.length, failing ? 0 : 1, "add: " + label); same(!!added.scope.cleared, !failing, "form cleared only when saved (" + label + ")")
            same(toasts.length, failing ? 1 : 0, "a failed save is reported once (" + label + ")")
            if (failing) same(toasts[0].message, "Your changes couldn't be saved.")

            var list = [{ uid: "a", ticker: "A", name: "A" }, { uid: "b", ticker: "B", name: "B" }]
            var removed = announce("removeSymbolAt", { symbolsList: list }, function(callback) { callback(0) }, failing)
            same(infos.length, failing ? 0 : 1, "remove: " + label); same(!!removed.scope.refreshed, !failing)
            if (!failing) equal(JSON.parse(removed.pluginService.data.symbols).map(function(symbol) { return symbol.uid }), ["b"])

            var moved = announce("moveSymbol", { symbolsList: list, editIndex: 0 }, function(callback) { callback(0, 1) }, failing)
            same(moved.scope.editIndex, failing ? 0 : 1, "moving keeps the edit position consistent (" + label + ")")
            if (!failing) equal(JSON.parse(moved.pluginService.data.symbols).map(function(symbol) { return symbol.uid }), ["b", "a"])

            var flags = announce("saveEditedSymbolFlags", { symbolsList: [{ uid: "a", ticker: "A" }], editIndex: 0, showChangeToggle: control(true), invertToggle: control(true) }, function(callback) { callback() }, failing)
            same(!!flags.scope.refreshed, !failing, "flag changes refresh only after saving (" + label + ")")
            if (!failing) same(JSON.parse(flags.pluginService.data.symbols)[0].invert, true)
        })
    }
    function test_save_value_and_load_value_delegate_to_the_storage() {
        var calls = []
        var storage = { save: function(key, value) { calls.push([key, value]); return key !== "fail" }, load: function(key, fallback) { return key + ":" + fallback } }
        same(settingsFunction("saveValue", { storage: storage })("a", 1), true); same(settingsFunction("saveValue", { storage: storage })("fail", 1), false)
        same(settingsFunction("loadValue", { storage: storage })("k", "dflt"), "k:dflt")
    }
}
