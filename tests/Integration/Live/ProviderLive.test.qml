// Opt-in network test (node tests/RunAll.js --live): every price resolution and (resolution, span) a
// provider DECLARES must really return data from the live API, through the REAL path the plugin uses:
// the provider's ProviderHandler builds the request, runs bash + curl (retrying transient failures),
// interprets and parses the answer. A few undeclared requests must be refused by our code before any
// request is made. Talks to query1.finance.yahoo.com and wise.com.
import QtQuick
import "../../../src/JS/Helpers/SelectionPolicy.js" as Policy
import "../../../src/QML/Contracts"
import "../../../src/QML/Services"
import "../../Helpers"

TestSuite {
    id: suite

    property Component contextType: Component {
        FetchContext {
        }
    }
    property Timer pace: Timer {
        interval: 300

        onTriggered: suite.paceCallback()
    }   // be gentle with the APIs

    property var paceCallback: null
    readonly property var symbols: ({
            yahoo: "EURUSD=X",
            wise: "BRLPLN"
        })

    function async_every_declared_request_returns_data(done) {
        let items = workItems(), index = 0;
        function onFinished(fetchContext, response, series) {
            let item = items[parseInt(fetchContext.uid)];
            try {
                check(response.ok, item.id + " " + item.label + ": " + (response.error && response.error.userMessage));
                same(response.status, 200, item.id + " " + item.label + ": HTTP status is reported");
                check(series.length >= 1, item.id + " " + item.label + ": no candles parsed");
                check(series.every(function (candle) {
                    return isFinite(candle.open) && isFinite(candle.high) && isFinite(candle.low) && isFinite(candle.close);
                }), item.id + " " + item.label + ": bad candle");
                console.warn("ok   " + item.id + " " + item.label + " (" + series.length + " candles)");
            } catch (error) {
                done(error.message);
                return;
            }
            index++;
            if (index < items.length)
                pace.restart();
            else
                done("");
        }
        Object.keys(symbols).forEach(function (id) {
            handlerOf(id).finished.connect(onFinished);
        });
        paceCallback = function () {
            items[index].run(context(items[index].id, index, items[index].type));
        };
        paceCallback();
    }
    function async_real_failure_answers_become_friendly_typed_errors(done) {
        let seen = {};
        ["yahoo", "wise"].forEach(function (id) {
            handlerOf(id).maxRetries = 0;
            handlerOf(id).finished.connect(function (fetchContext, response) {
                if (fetchContext.uid.indexOf("x") !== 0)
                    return;
                seen[fetchContext.providerId] = response;
                if (Object.keys(seen).length < 2)
                    return;
                try {
                    let yahooResponse = seen.yahoo, wiseResponse = seen.wise;
                    check(!yahooResponse.ok, "an unknown Yahoo symbol fails");
                    same(yahooResponse.status, 404);
                    same(yahooResponse.error.code, "notFound");
                    check(/^Yahoo Finance: /.test(yahooResponse.error.userMessage), yahooResponse.error.userMessage);
                    check(!yahooResponse.error.retryable);
                    check(!wiseResponse.ok, "an unknown currency pair fails");
                    check(wiseResponse.status >= 400 && wiseResponse.status < 500, "HTTP " + wiseResponse.status);
                    check(!wiseResponse.error.retryable);
                    done("");
                } catch (error) {
                    done(error.message);
                }
            });
        });
        handlerOf("yahoo").fetchPrice("ZZZZNOTASYMBOL9", "1d", (contextType.createObject(null, {
                uid: "xy",
                ticker: "ZZZZNOTASYMBOL9",
                providerId: "yahoo",
                fetchType: "price",
                chartRange: "1M",
                chartResolution: "1d"
            }) as FetchContext));
        handlerOf("wise").fetchPrice("XXXYYY", "1d", (contextType.createObject(null, {
                uid: "xw",
                ticker: "XXXYYY",
                providerId: "wise",
                fetchType: "price",
                chartRange: "1M",
                chartResolution: "1d"
            }) as FetchContext));
    }
    function context(id, index, type) {
        return (contextType.createObject(null, {
                uid: String(index),
                ticker: symbols[id],
                providerId: id,
                fetchType: type,
                chartRange: "1M",
                chartResolution: "1d"
            }) as FetchContext);
    }
    function handlerOf(id) {
        return ProvidersManager.requireFromId(id);
    }
    function test_undeclared_requests_are_refused_before_any_request() {
        throws(function () {
            handlerOf("wise").chartRequest("BRLPLN", "1d", "10Y");
        }, "can't show", "Wise 10Y");
        throws(function () {
            handlerOf("yahoo").chartRequest("EURUSD=X", "1m", "1M");
        }, "can't show", "Yahoo 1m/1M");
    }

    // One work item per declared request: { label, id, run(context) }.
    function workItems() {
        let items = [];
        Object.keys(symbols).forEach(function (id) {
            let handler = handlerOf(id), properties = handler.properties;
            Policy.priceResolutions(properties).forEach(function (resolution) {
                items.push({
                    label: "price " + resolution,
                    id: id,
                    type: "price",
                    run: function (fetchContext) {
                        return handler.fetchPrice(symbols[id], resolution, fetchContext);
                    }
                });
            });
            Policy.chartResolutions(properties).forEach(function (resolution) {
                Policy.chartSpans(properties, resolution).forEach(function (span) {
                    items.push({
                        label: "chart " + resolution + "/" + span,
                        id: id,
                        type: "graph",
                        run: function (fetchContext) {
                            return handler.fetchChart(symbols[id], resolution, span, fetchContext);
                        }
                    });
                });
            });
        });
        return items;
    }
}
