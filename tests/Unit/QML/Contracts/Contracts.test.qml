import QtQml
import "../../../Helpers"
import "../../../../src/QML/Contracts"

TestSuite {
    id: suite
    property Component symbolComponent: Component { SavedSymbol {} }
    property Component pointComponent: Component { DataPoint {} }
    property Component selectionComponent: Component { Selection {} }
    property Component statusComponent: Component { ChartStatus {} }
    property Component providerLoadErrorComponent: Component { ProviderLoadError {} }
    property Component priceComponent: Component { PriceInfo {} }
    property Component requestComponent: Component { ProviderRequest {} }
    property Component responseComponent: Component { ProviderResponse {} }
    property Component contextComponent: Component { FetchContext {} }
    property Component callComponent: Component { FetchCall {} }
    property Component recordComponent: Component { ErrorRecord {} }
    property Component guardComponent: Component { GuardResult {} }

    function test_saved_symbol_holds_data_and_checks_each_field() {
        var symbol = symbolComponent.createObject(null, { uid: "11111111-1111-4111-8111-111111111111", ticker: "BRLPLN", name: "Real",
            provider: "wise", priceResolution: "1h", changeResolution: "1d", chartResolution: "1d", chartRange: "1M" })
        check(symbol.valid)
        equal(Object.keys(symbol.toJson()), ["uid", "ticker", "name", "provider", "priceResolution", "changeResolution", "chartResolution", "chartRange",
                                        "showChangeWhenPinned", "invert", "pinned"])
        symbol.chartRange = "7Y"
        check(!symbol.chartRangeValid && !symbol.valid && symbol.priceResolutionValid, "a bad field only fails its own flag")
        symbol.chartRange = "1M"; symbol.uid = "nope"
        check(!symbol.uidValid && !symbol.valid)
        symbol.destroy()
    }
    function test_new_symbol_is_invalid_until_filled() {
        var symbol = symbolComponent.createObject(null)
        check(!symbol.valid && !symbol.uidValid && !symbol.tickerValid && !symbol.providerValid)
        symbol.destroy()
    }
    function test_data_point_field_checks() {
        var point = pointComponent.createObject(null, { date: "2026-01-02", time: "10:00:00", open: 1, high: 2, low: 0.5, close: 1.5 })
        check(point.dateValid && point.timeValid); same(point.volume, 0)
        point.time = ""; check(point.timeValid)
        point.date = "2026/01/02"; check(!point.dateValid)
    }
    function test_selection_field_checks() {
        var selection = selectionComponent.createObject(null, { priceResolution: "1h", changeResolution: "1d", chartResolution: "1d", chartRange: "7Y" })
        check(selection.priceResolutionValid && selection.chartResolutionValid && !selection.chartRangeValid)
    }
    function test_chart_status_flags() {
        var chartStatus = statusComponent.createObject(null, { level: "block" }); check(chartStatus.blocked && !chartStatus.warned)
        chartStatus.level = "warn"; check(chartStatus.warned && !chartStatus.blocked)
        chartStatus.destroy()
    }
    function test_provider_load_error_builds_message() {
        var loadError = providerLoadErrorComponent.createObject(null, { id: "x", name: "X", error: { userMessage: "It broke." } })
        same(loadError.userMessage, "X couldn't be loaded and is unavailable. It broke.")
        loadError.destroy()
    }
    function test_plain_holders_have_defaults() {
        same(priceComponent.createObject(null).changePercent, 0)
        same(requestComponent.createObject(null).tailLines, 0)
        same(responseComponent.createObject(null).ok, false)
        same(responseComponent.createObject(null).error, null)
        same(contextComponent.createObject(null).fetchTypeValid, false)
        same(callComponent.createObject(null).context, null)
        same(recordComponent.createObject(null).retryable, false)
        same(guardComponent.createObject(null).ok, false)
    }
    function test_holders_keep_what_they_are_given() {
        var response = responseComponent.createObject(null, { providerId: "y", ok: true, status: 200, body: "hi" })
        same(response.body, "hi"); same(response.status, 200)
        var fetchContext = contextComponent.createObject(null, { uid: "u", fetchType: "price" })
        check(fetchContext.fetchTypeValid)
    }
}
