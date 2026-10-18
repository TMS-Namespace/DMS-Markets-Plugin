// The ProviderHandler facade: everything the plugin asks of a provider goes through it.
import QtQml
import "../../../Helpers"
import "../../../../src/QML/Contracts"
import "../../../../src/QML/Services"
import "../../../../src/JS/Contracts/ChartSpan.js" as ChartSpan

TestSuite {
    property Component contextType: Component { FetchContext {} }
    function setup() { ProvidersManager.reload(ProvidersManager.sources) }
    function handlerOf(type) { return ProvidersManager.handlerFor(type) }
    readonly property string envelope: "MARKETS-RESPONSE 0 200\n"

    function test_it_exposes_its_type_and_what_the_provider_declares() {
        same(handlerOf(ProviderType.Wise).type, ProviderType.Wise)
        same(handlerOf(ProviderType.Wise).properties.name, "Wise"); same(handlerOf(ProviderType.Yahoo).properties.minPullResolution, "1m")
        check(handlerOf(ProviderType.Stooq).properties.disabled && !handlerOf(ProviderType.Yahoo).properties.disabled)
    }
    function test_symbol_validation_uses_the_providers_rules() {
        check(handlerOf(ProviderType.Wise).validateSymbol("BRLPLN").valid); check(!handlerOf(ProviderType.Wise).validateSymbol("BRL").valid)
        check(handlerOf(ProviderType.Yahoo).validateSymbol("EURUSD=X").valid); check(!handlerOf(ProviderType.Yahoo).validateSymbol("A;B").valid)
    }
    function test_dropdown_options_follow_the_providers_limits() {
        equal(handlerOf(ProviderType.Wise).priceResolutionOptions().map(function(option) { return option.value }), ["1h", "1d"])
        check(handlerOf(ProviderType.Wise).chartSpanOptions("1h").length > 0)
        equal(handlerOf(ProviderType.Wise).chartSpanOptions("5m"), [])
        same(handlerOf(ProviderType.Yahoo).priceResolutionOptions().length, 7)
        check(handlerOf(ProviderType.Yahoo).chartResolutionOptions().length > 0)
    }
    function test_selection_helpers_return_selections() {
        same(handlerOf(ProviderType.Wise).defaultSelection().priceResolution, "1h")
        let clamped = handlerOf(ProviderType.Wise).clampSelection({ priceResolution: "5m", chartResolution: "5m", chartRange: "10Y" })
        same(clamped.priceResolution, "1h"); check(clamped.chartResolutionValid && clamped.chartRangeValid)
        same(handlerOf(ProviderType.Yahoo).chartRangeStatus("1m", "1Y").level, "block")
    }
    function test_a_price_request_is_checked_then_built() {
        let request = handlerOf(ProviderType.Wise).priceRequest("BRLPLN", "1d")
        check(request.url.indexOf("https://wise.com/rates/history+live") === 0)
        same(request.command[request.command.length - 1], request.url); same(request.tailLines, 0)
        throws(function() { handlerOf(ProviderType.Wise).priceRequest("BRLPLN", "5m") }, "price resolution")
        throws(function() { handlerOf(ProviderType.Yahoo).priceRequest("bad;sym", "1d") }, "")
    }
    function test_chart_requests_enforce_limits_and_the_pull_rate() {
        check(handlerOf(ProviderType.Yahoo).chartRequest("EURUSD=X", "1d", "1M").url.indexOf("query1.finance.yahoo.com") !== -1)
        throws(function() { handlerOf(ProviderType.Wise).chartRequest("BRLPLN", "1h", "1Y") }, "can't show")
        throws(function() { handlerOf(ProviderType.Wise).priceRequest("BRLPLN", "1m") }, "")
    }
    function test_requests_say_how_many_candles_are_needed() {
        same(handlerOf(ProviderType.Yahoo).priceRequest("EURUSD=X", "1m").candles, 2, "the price needs the newest candle and the one before it")
        same(handlerOf(ProviderType.Yahoo).chartRequest("EURUSD=X", "1d", "1M").candles, ChartSpan.pointLimit("1d", "1M"))
        same(handlerOf(ProviderType.Wise).chartRequest("BRLPLN", "1h", "1D").tailLines, 0, "only providers whose script tails the answer get tailLines")
    }
    function test_responses_are_interpreted_and_parsed_keeping_only_the_newest_candles() {
        let body = JSON.stringify([1, 2, 3, 4].map(function(value) { return { value: value, time: value * 1000 } }))
        let wise = handlerOf(ProviderType.Wise)
        let response = wise.interpret({ exitCode: 0, stdout: envelope + body, stderr: "" })
        check(response.ok); same(response.status, 200)
        equal(wise.parseChart(response, 2).map(function(candle) { return candle.close }), [3, 4])
        same(wise.parsePrice(response, 1).length, 1); same(wise.parseChart(response, 0).length, 4)
        same(wise.parseChart(response, 99).length, 4, "a limit above what exists returns everything")
        let bad = wise.interpret({ exitCode: 0, stdout: "MARKETS-RESPONSE 0 404\n{}", stderr: "" })
        check(!bad.ok); same(bad.error.code, "notFound")
        throws(function() { wise.parsePrice(bad, 1) }, "")
        let yahooBody = JSON.stringify({ chart: { result: [{ timestamp: [1767225600, 1767229200, 1767232800], indicators: { quote: [{
            open: [1, 2, 3], high: [1, 2, 3], low: [1, 2, 3], close: [1, 2, null], volume: [0, 0, 0] }] } }] } })
        let yahooResponse = handlerOf(ProviderType.Yahoo).interpret({ exitCode: 0, stdout: envelope + yahooBody, stderr: "" })
        equal(handlerOf(ProviderType.Yahoo).parsePrice(yahooResponse, 1).map(function(candle) { return candle.close }), [2], "rows without data are skipped, then the newest is taken")
    }
    function test_credentials_live_in_the_handler_and_a_disabled_provider_is_never_usable() {
        let stooq = handlerOf(ProviderType.Stooq)
        check(stooq.properties.requiresCredential && !handlerOf(ProviderType.Yahoo).properties.requiresCredential)
        check(!stooq.isValidCredential("abc"), "a disabled provider's credential is never valid")
        check(handlerOf(ProviderType.Yahoo).isValidCredential("") && handlerOf(ProviderType.Yahoo).hasRequiredCredential())
        stooq.setCredential("k"); same(stooq.properties.credential, "k")
        let error = throws(function() { stooq.priceRequest("eurusd", "1d") }, "disabled")
        same(error.code, "unsupported"); same(error.userMessage, "Stooq is currently disabled.")
    }
    function test_a_missing_credential_is_reported_with_what_to_do() {
        let handler = handlerOf(ProviderType.Yahoo)
        handler.properties.requiresCredential = true; handler.properties.credentialMinLength = 3; handler.properties.credentialLabel = "API key"
        let error = throws(function() { handler.priceRequest("EURUSD=X", "1d") }, "")
        same(error.code, "credential"); check(/Add your API key in the settings/.test(error.userMessage))
        handler.setCredential("abcd")
        check(handler.priceRequest("EURUSD=X", "1d").url.length > 0)
    }
    function test_fetch_calls_report_unusable_requests_by_throwing_before_anything_runs() {
        let handler = handlerOf(ProviderType.Wise)
        let context = (contextType.createObject(null, { uid: "u", ticker: "X", providerId: "wise", fetchType: "price", chartRange: "1M", chartResolution: "1d" }) as FetchContext)
        throws(function() { handler.fetchPrice("EUR", "1d", context) }, "invalid symbol")
        throws(function() { handler.fetchChart("BRLPLN", "1d", "10Y", context) }, "can't show")
        equal(handler.pending, {}, "nothing was queued")
    }
}
