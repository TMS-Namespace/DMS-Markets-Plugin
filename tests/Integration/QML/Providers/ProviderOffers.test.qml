// What the bundled providers offer through the settings must always be servable and readable.
import QtQml
import "../../../Helpers"
import "../../../../src/QML/Services"
import "../../../../src/JS/Helpers/SelectionPolicy.js" as Policy
import "../../../../src/JS/Helpers/ChartRules.js" as Rules

TestSuite {
    function handlerOf(id) { return ProvidersManager.requireFromId(id) }
    function each(action) { ProvidersManager.types.forEach(function(type) { var id = ProvidersManager.idOf(type); action(id, handlerOf(id).properties) }) }

    function test_every_offered_span_is_allowed_and_every_filtered_one_is_blocked() {
        each(function(id, properties) {
            Policy.allowedChartResolutions(properties).forEach(function(resolution) {
                let spans = Policy.allowedChartSpans(properties, resolution)
                check(spans.length > 0, id + " " + resolution + " offers spans")
                spans.forEach(function(span) { check(Rules.isAllowed(resolution, span), id + " " + resolution + "/" + span) })
                Policy.chartSpans(properties, resolution).filter(function(candidateSpan) { return spans.indexOf(candidateSpan) === -1 }).forEach(function(span) {
                    check(!Rules.isAllowed(resolution, span), id + " " + resolution + "/" + span + " was filtered because it is blocked")
                })
            })
            Policy.chartResolutions(properties).forEach(function(resolution) {
                same(Policy.allowedChartResolutions(properties).indexOf(resolution) !== -1, Policy.allowedChartSpans(properties, resolution).length > 0, id + " " + resolution)
            })
        })
    }
    function test_defaults_are_servable_and_clean() {
        each(function(id, properties) {
            let defaults = Policy.defaultSelection(properties)
            check(Policy.supportsPrice(properties, defaults.priceResolution), id)
            check(Policy.supportsChart(properties, defaults.chartResolution, defaults.chartRange), id)
            same(Rules.evaluate(defaults.chartResolution, defaults.chartRange).level, "ok", id + " default selection is clean")
        })
    }
    function test_clamping_always_yields_an_allowed_servable_selection() {
        each(function(id, properties) {
            ;["", "1m", "1h", "1w"].forEach(function(price) {
                ;["", "1m", "1h", "1w", "1M"].forEach(function(resolution) {
                    ;["", "1D", "1W", "1M", "1Y", "10Y", "15m"].forEach(function(span) {
                        let selection = Policy.clamp(properties, { priceResolution: price, chartResolution: resolution, chartRange: span })
                        check(Policy.supportsPrice(properties, selection.priceResolution), id + " price")
                        check(Policy.supportsChart(properties, selection.chartResolution, selection.chartRange), id + " chart")
                        check(Rules.isAllowed(selection.chartResolution, selection.chartRange), id + " clamp(" + price + "|" + resolution + "|" + span + ") allowed")
                    })
                })
            })
        })
    }
    function test_there_is_one_clamp_and_it_moves_unreadable_charts() {
        let wise = handlerOf("wise").properties
        equal(Policy.clamp(wise, { priceResolution: "1d", changeResolution: "1d", chartResolution: "1d", chartRange: "1Y" }),
              { priceResolution: "1d", changeResolution: "1d", chartResolution: "1d", chartRange: "6M" }, "365 daily candles is moved to an allowed range")
        equal(Policy.clamp(wise, { priceResolution: "1d", changeResolution: "1d", chartResolution: "1d", chartRange: "3M" }),
              { priceResolution: "1d", changeResolution: "1d", chartResolution: "1d", chartRange: "3M" }, "a servable, readable choice is left alone")
    }
}
