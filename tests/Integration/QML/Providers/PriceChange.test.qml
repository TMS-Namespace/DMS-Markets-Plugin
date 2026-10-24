// The price change shown for a symbol must be the real movement for EVERY provider, never a flat 0.
// Some providers end an intraday answer with a "live" row (open = high = low = close = the current price): taken alone its
// change is 0. Every provider gets an answer in ITS OWN format that has real movement and ends in such a flat row; the
// price pipeline (request size -> provider parser -> PriceRules) must still report the movement. A provider WITHOUT a
// fixture here fails the test: add one when you add a provider.
import QtQml
import "../../../../src/JS/Helpers/PriceRules.js" as PriceRules
import "../../../../src/QML/Services"
import "../../../Helpers"

TestSuite {
    // What each provider's pipeline must report for the fixture above.
    readonly property var expectedChange: ({
            yahoo: 1,
            wise: 1,
            stooq: 1
        })

    // The change reference (the close of the period before the current one) each provider must read from the fixture above.
    // Yahoo's flat live row is no period of its own; Wise's last point is the live rate; Stooq's last row is the current day.
    readonly property var expectedReference: ({
            yahoo: 99,
            wise: 100,
            stooq: 102
        })

    // Per provider id: an answer with candles that move (the previous candle opens at 100 and closes at 102) followed by a
    // flat live row at 101. The expected movement from the previous candle's open to the live price is +1.
    readonly property var fixtures: ({
            yahoo: function () {
                let rows = [[1767225600, 98, 99, 97, 99], [1767229200, 100, 103, 99, 102], [1767232800, 101, 101, 101, 101]];
                function column(index) {
                    return JSON.stringify(rows.map(function (row) {
                        return row[index];
                    }));
                }
                return '{"chart":{"result":[{"timestamp":' + column(0) + ',"indicators":{"quote":[{"open":' + column(1) + ',"high":' + column(2) + ',"low":' + column(3) + ',"close":' + column(4) + ',"volume":[0,0,0]}]}}],"error":null}}';
            },
            stooq: function () {
                return "Date,Open,High,Low,Close,Volume\n2026-01-01,98,99,97,99,0\n2026-01-02,100,103,99,102,0\n2026-01-03,101,101,101,101,0\n";
            },
            // Wise gives one rate per point: a candle's open is the previous rate, so the movement is the last step.
            wise: function () {
                return JSON.stringify([
                    {
                        value: 99,
                        time: 1767225600000
                    },
                    {
                        value: 100,
                        time: 1767229200000
                    },
                    {
                        value: 101,
                        time: 1767232800000
                    }
                ]);
            }
        })

    function handlerOf(type) {
        return ProvidersManager.handlerFor(type);
    }
    function setup() {
        ProvidersManager.reload(ProvidersManager.sources);
    }
    function test_every_enabled_provider_asks_for_enough_candles_for_the_price() {
        ProvidersManager.types.forEach(function (type) {
            let handler = handlerOf(type);
            if (handler.properties.disabled)
                return;
            let resolution = handler.properties.priceResolutions[handler.properties.priceResolutions.length - 1];
            if (!handler.validateSymbol(handler.properties.symbolPlaceholder).valid)
                return;
            let request = handler.priceRequest(handler.properties.symbolPlaceholder, resolution);
            check(request.candles >= 2, handler.properties.providerId + ": a price request needs the newest candle and the one before it (" + request.candles + ")");
        });
    }
    function test_every_provider_declares_and_serves_its_change_resolutions() {
        ProvidersManager.types.forEach(function (type) {
            let handler = handlerOf(type), id = handler.properties.providerId;
            check(handler.properties.changeResolutions.length > 0, id + ": declares change resolutions");
            check(handler.properties.changeResolutions.indexOf("1d") !== -1, id + ": offers the one-day change (what quote pages show)");
            handler.properties.changeResolutions.forEach(function (resolution) {
                if (handler.properties.disabled)
                    return;
                let request = handler.changeRequest(id === "wise" ? "BRLPLN" : "EURUSD=X", resolution);
                check(request.url.length > 0, id + ": a change request for " + resolution);
            });
            let refused = false;
            try {
                handler.changeRequest(id === "wise" ? "BRLPLN" : "EURUSD=X", "7Y");
            } catch (e) {
                refused = true;
            }
            check(refused, id + ": an undeclared resolution is refused");
        });
    }
    function test_every_provider_has_a_fixture() {
        ProvidersManager.types.forEach(function (type) {
            let id = ProvidersManager.idOf(type);
            check(typeof fixtures[id] === "function", id + ": add an answer fixture (with a flat live row) to PriceChange.test.qml");
            check(expectedChange[id] !== undefined, id + ": add its expected change");
        });
    }
    function test_every_provider_reads_the_change_reference() {
        ProvidersManager.types.forEach(function (type) {
            let handler = handlerOf(type), id = handler.properties.providerId;
            check(expectedReference[id] !== undefined, id + ": add its expected change reference to PriceChange.test.qml");
            let response = handler.interpret({
                exitCode: 0,
                stdout: "MARKETS-RESPONSE 0 200\n" + fixtures[id](),
                stderr: ""
            });
            near(handler.parseChange(response), expectedReference[id], 1e-9, id + ": the change reference");
            // The change is measured against it, like the provider's own quote page does.
            let series = handler.parsePrice(response, 2);
            near(PriceRules.priceFrom(series[series.length - 1], series[series.length - 2], handler.parseChange(response)).change, series[series.length - 1].close - expectedReference[id], 1e-9, id + ": change = price - reference");
        });
    }
    function test_the_price_pipeline_reports_the_real_change_for_every_provider() {
        ProvidersManager.types.forEach(function (type) {
            let handler = handlerOf(type), id = handler.properties.providerId;
            let response = handler.interpret({
                exitCode: 0,
                stdout: "MARKETS-RESPONSE 0 200\n" + fixtures[id](),
                stderr: ""
            });
            check(response.ok, id + ": the fixture is a valid answer: " + (response.error && response.error.userMessage));
            // The handler asks for as many candles as the price needs, and its parser delivers them.
            let needed = 2;
            let series = handler.parsePrice(response, needed);
            check(series.length >= 2, id + ": the parser returns the newest candle AND the one before it (" + series.length + ")");
            let price = PriceRules.priceFrom(series[series.length - 1], series[series.length - 2]);
            check(price.change !== 0, id + ": the change is not 0");
            near(price.change, expectedChange[id], 1e-9, id + ": the change is the real movement");
            same(price.close, series[series.length - 1].close, id + ": the price is the newest close");
        });
    }
}
