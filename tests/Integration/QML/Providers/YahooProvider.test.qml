import QtQml
import "../../../Helpers"
import "../../../../src/QML/Services"
import "../../../../src/QML/Contracts"
import "../../../../src/JS/Helpers/SelectionPolicy.js" as Policy
import "../../../../src/JS/Contracts/ChartSpan.js" as ChartSpan
import "../../../../src/JS/Helpers/SeriesRules.js" as Series
import "../../../../src/JS/Providers/Yahoo/YahooConstants.js" as YahooConstants

TestSuite {
    function handlerOf(id) { return ProvidersManager.requireFromId(id) }
    Component.onCompleted: { if (!Array.prototype.at) Array.prototype.at = function(index) { const array = Array.from(this); return array[index < 0 ? array.length + index : index] } }
    property Component responseType: Component { ProviderResponse {} }
    function ok(providerId, body, status) { return (responseType.createObject(null, { providerId: providerId, ok: true, status: status || 200, body: body }) as ProviderResponse) }
    function notSame(first, second, message) { check(first !== second, message || "values are identical") }
    function values(options) { return options.map(function(option) { return option.value }) }

    function test_yahoo_provider() {

        const values = (options) => options.map((option) => option.value);

        function sampleChartResponse() {
            return JSON.stringify({
                chart: {
                    result: [{
                        meta: { symbol: "EURUSD=X" },
                        timestamp: [1767225600, 1767312000, 1767398400],
                        indicators: {
                            quote: [{
                                open:   [1.10, 1.11, null],
                                high:   [1.12, 1.13, 1.15],
                                low:    [1.09, 1.10, 1.12],
                                close:  [1.11, 1.12, 1.14],
                                volume: [0, 0, 0]
                            }]
                        }
                    }],
                    error: null
                }
            });
        }

        // ── Properties ───────────────────────────────────────────────────────────────
        same(handlerOf("yahoo").symbolPageUrl("EURUSD=X"),
                           "https://finance.yahoo.com/quote/EURUSD%3DX", "Yahoo declares its browser URL");
        equal(Policy.chartSpans(handlerOf("yahoo").properties, "1m"), ["1H", "3H", "6H", "12H", "1D", "1W"],
             "Yahoo 1-minute history reaches a week back");
        equal(values(handlerOf("yahoo").chartSpanOptions("1m")), ["1H", "3H"], "...and the chart rules leave 1 and 3 hours (60 / 180 candles)");
        equal(values(handlerOf("yahoo").chartSpanOptions("5m")), ["1H", "3H", "6H", "12H"]);
        equal(values(handlerOf("yahoo").chartSpanOptions("15m")), ["1H", "3H", "6H", "12H", "1D"]);
        equal(values(handlerOf("yahoo").chartSpanOptions("1h")), ["3H", "6H", "12H", "1D", "1W"]);
        equal(values(handlerOf("yahoo").chartSpanOptions("1d")), ["1W", "1M", "3M", "6M"]);
        equal(values(handlerOf("yahoo").chartSpanOptions("1w")), ["1M", "3M", "6M", "1Y", "2Y"]);
        equal(values(handlerOf("yahoo").chartSpanOptions("1M")), ["3M", "6M", "1Y", "2Y", "5Y", "10Y"]);
        equal(values(handlerOf("yahoo").chartResolutionOptions()), ["1m", "5m", "15m", "1h", "1d", "1w", "1M"],
             "every candle size is available for charts: short ranges make the fine ones usable");
        same(JSON.stringify(values(handlerOf("yahoo").priceResolutionOptions())).includes("1m"), true,
                           "1-minute is still a valid price range");
        same(JSON.stringify(values(handlerOf("yahoo").priceResolutionOptions())),
                           JSON.stringify(["1m", "5m", "15m", "1h", "1d", "1w", "1M"]));

        // ── Every declared combination builds a request ──────────────────────────────
        const yahooProperties = handlerOf("yahoo").properties;
        for (const interval of yahooProperties.priceResolutions)
            check(handlerOf("yahoo").priceRequest("EURUSD=X", interval).url, `price ${interval}`);
        for (const resolution of Policy.chartResolutions(yahooProperties))
            for (const span of Policy.chartSpans(yahooProperties, resolution))
                check(handlerOf("yahoo").chartRequest("EURUSD=X", resolution, span).url, `history ${resolution}/${span}`);

        // ── Limits ───────────────────────────────────────────────────────────────────
        throws(() => handlerOf("yahoo").chartRequest("EURUSD=X", "1m", "1M"), "'1M' chart range",
                   "Yahoo rejects a month of 1-minute candles");
        throws(() => handlerOf("yahoo").chartRequest("EURUSD=X", "5m", "3M"), "'3M' chart range",
                   "Yahoo rejects intraday spans beyond its limit");

        // ── Request building ─────────────────────────────────────────────────────────
        const priceRequest = handlerOf("yahoo").priceRequest("EURUSD=X", "1h");
        check(priceRequest.url.includes("/v8/finance/chart/EURUSD%3DX"),
               "Yahoo price URL should use encoded chart endpoint symbol");
        check(priceRequest.url.includes("interval=1h"), "Yahoo price URL should map hourly interval");
        check(priceRequest.url.includes("range=5d"), "Yahoo hourly price URL should use a valid intraday range");
        same(JSON.stringify(priceRequest.command.slice(0, 4)),
                           JSON.stringify(["bash", "-o", "pipefail", "-c"]),
                           "Provider request should include a shell command for the fetcher");

        const historyRequest = handlerOf("yahoo").chartRequest("BZ=F", "1d", "6M");
        check(historyRequest.url.includes("/v8/finance/chart/BZ%3DF"),
               "Yahoo history URL should use encoded chart endpoint symbol");
        check(historyRequest.url.includes("interval=1d"), "Yahoo daily history URL should use daily candles");
        check(historyRequest.url.includes("range=6mo"), "Yahoo 6M span should use range=6mo");
        same(historyRequest.tailLines, 0, "Yahoo JSON responses must not be tailed");
        same(historyRequest.command[6], historyRequest.url,
                           "Yahoo command should pass the provider URL separately");
        check(handlerOf("yahoo").chartRequest("EURUSD=X", "1w", "10Y").url.includes("interval=1wk&"),
               "Yahoo weekly candles map to 1wk");
        check(handlerOf("yahoo").chartRequest("EURUSD=X", "15m", "1M").url.includes("range=1mo"));

        // ── Parsing ──────────────────────────────────────────────────────────────────
        const parsed = handlerOf("yahoo").parseChart(ok("yahoo", sampleChartResponse()));
        same(parsed.length, 2, "Yahoo parser should skip incomplete candles");
        same(JSON.stringify(parsed[0]), JSON.stringify({
            date: "2026-01-01", time: "00:00:00",
            open: 1.10, high: 1.12, low: 1.09, close: 1.11, volume: 0
        }));
        same(handlerOf("yahoo").parsePrice(ok("yahoo", sampleChartResponse())).at(-1).close, 1.12,
                           "Yahoo price parser should return the latest complete candle");


        // ═════════════════════════════════════════════════════════════════════════════
        // Extended coverage
        // ═════════════════════════════════════════════════════════════════════════════

        // Every declared interval/span must have an API mapping (no silent fallbacks).
        for (const interval of yahooProperties.priceResolutions) {
            check(YahooConstants.YAHOO_RESOLUTION_MAP[interval], `interval map covers ${interval}`);
            check(YahooConstants.YAHOO_PRICE_RANGE_BY_RESOLUTION[interval], `price range map covers ${interval}`);
        }
        for (const resolution of Policy.chartResolutions(yahooProperties)) {
            check(YahooConstants.YAHOO_RESOLUTION_MAP[resolution], `interval map covers chart resolution ${resolution}`);
            for (const span of Policy.chartSpans(yahooProperties, resolution))
                check(handlerOf("yahoo").chartRequest("EURUSD=X", resolution, span).url.includes("range="), `a range exists for ${resolution}/${span}`);
        }

        // Declared spans stay within Yahoo's measured intraday limits (days of history).
        const limitDays = { "1m": 8, "5m": 60, "15m": 60, "1h": 730 };
        for (const [resolution, maxDays] of Object.entries(limitDays))
            for (const span of Policy.chartSpans(yahooProperties, resolution))
                check(ChartSpan.days(span) <= maxDays,
                       `Yahoo ${resolution} must not offer ${span} (limit ${maxDays} days)`);
        same(Policy.chartResolutions(yahooProperties).length, 7, "Yahoo serves all seven candle sizes");

        // Exact URLs.
        same(handlerOf("yahoo").chartRequest("EURUSD=X", "1d", "1Y").url,
            "https://query1.finance.yahoo.com/v8/finance/chart/EURUSD%3DX?range=1y&interval=1d&includePrePost=false&events=history");
        same(handlerOf("yahoo").chartRequest("EURUSD=X", "1M", "10Y").url.includes("interval=1mo&"), true);
        same(handlerOf("yahoo").chartRequest("EURUSD=X", "1m", "1D").url.includes("range=1d&interval=1m"), true);
        same(handlerOf("yahoo").chartRequest("EURUSD=X", "1w", "3M").url.includes("range=3mo"), true);
        check(!handlerOf("yahoo").priceRequest("EURUSD=X", "1m").url.includes("range=1mo"),
               "1-minute price requests must use a short range");

        // Symbols are validated against the declared pattern and then URL-encoded.
        for (const good of ["EURUSD=X", "BZ=F", "DX-Y.NYB", "^GSPC", "BTC-USD", "0700.HK", "M&M.NS", "BRK-B", "A"])
            same(handlerOf("yahoo").validateSymbol(good).valid, true, good);
        check(handlerOf("yahoo").priceRequest("M&M.NS", "1d").url.includes("/chart/M%26M.NS?"), "& is percent-encoded");
        check(handlerOf("yahoo").priceRequest("EURUSD=X", "1d").url.includes("/chart/EURUSD%3DX?"));
        for (const hostile of ["A&range=max#/../x", "A B", "A;B", "A|B", "A$B", "`id`", "A'B", 'A"B', "A\nB", "A/B", "A?B", "A%20B", "A(B)", "../x", "A\\B",
                               "", " ", "x".repeat(25), "-AAPL", ".AAPL"]) {
            same(handlerOf("yahoo").validateSymbol(hostile).valid, false, JSON.stringify(hostile));
            throws(() => handlerOf("yahoo").priceRequest(hostile, "1d"), "invalid symbol", `price rejects ${JSON.stringify(hostile)}`);
            throws(() => handlerOf("yahoo").chartRequest(hostile, "1d", "1M"), "invalid symbol", "history rejects it too");
        }
        same(new URL(handlerOf("yahoo").priceRequest("EURUSD=X", "1d").url).host, "query1.finance.yahoo.com");
        same(handlerOf("yahoo").validateSymbol("x".repeat(24)).valid, true, "24 characters is the limit");
        same(handlerOf("yahoo").validateSymbol("x".repeat(25)).valid, false);
        check(/characters/.test(handlerOf("yahoo").validateSymbol("x".repeat(25)).message), "length violations say so");
        check(/Yahoo Finance symbol/.test(handlerOf("yahoo").validateSymbol("A B").message), "format violations use the provider's message");

        // Pull frequency: Yahoo may be polled as often as every minute.
        handlerOf("yahoo").priceRequest("EURUSD=X", "1m");
        handlerOf("yahoo").chartRequest("EURUSD=X", "1m", "1H");
        same(handlerOf("yahoo").properties.minPullResolution, "1m");

        // Unsupported requests.
        throws(() => handlerOf("yahoo").priceRequest("EURUSD=X", "2h"), "price resolution '2h'", "unknown interval");
        throws(() => handlerOf("yahoo").chartRequest("EURUSD=X", "2h", "1M"), "chart resolution '2h'", "unknown resolution");
        throws(() => handlerOf("yahoo").chartRequest("EURUSD=X", "1d", "20Y"), "'20Y' chart range", "unknown span");
        same(handlerOf("yahoo").chartRangeStatus("1M", "1W").level, "block", "monthly candles on a week chart are blocked by the chart rules");

        // Short ranges: the smallest Yahoo range that covers them is fetched, the fetcher trims.
        const urlFor = (resolution, span) => handlerOf("yahoo").chartRequest("EURUSD=X", resolution, span).url;
        for (const span of ["1H", "3H", "6H", "12H", "1D"]) check(urlFor("5m", span).includes("range=1d&interval=5m"), `5m/${span}`);
        check(urlFor("1m", "1W").includes("range=5d&interval=1m"), "a week → 5d");
        check(urlFor("15m", "1M").includes("range=1mo&interval=15m"));
        check(urlFor("1h", "2Y").includes("range=2y&interval=1h"), "hourly reaches 2 years");
        check(urlFor("1d", "10Y").includes("range=10y"));
        // Range strings are chosen by coverage, never shorter than the span.
        for (const [span, days] of [["1H", 1/24], ["1W", 7], ["1M", 30], ["3M", 91], ["6M", 182], ["1Y", 365], ["2Y", 730], ["5Y", 1826], ["10Y", 3652]]) {
            const range = /range=(\w+)/.exec(urlFor("1M", span) || "")[1];
            const entry = YahooConstants.YAHOO_RANGES.find((candidate) => candidate.range === range);
            check(entry && entry.days >= days, `${span} is covered by ${range}`);
        }

        // Parser robustness.
        throws(() => handlerOf("yahoo").parseChart(ok("yahoo", "not json")), "not valid JSON", "unreadable answers are PARSE errors");
        throws(() => handlerOf("yahoo").parseChart(ok("yahoo", "{}")), "no chart result", "wrong shape");
        throws(() => handlerOf("yahoo").parseChart(ok("yahoo", JSON.stringify({ chart: { result: null, error: { code: "Not Found", description: "No data found, symbol may be delisted" } } }))), "No data found, symbol may be delisted", "the API's own message is carried through");
        equal(handlerOf("yahoo").parseChart(ok("yahoo", JSON.stringify({ chart: { result: [{}] } }))), []);
        const stringy = JSON.stringify({ chart: { result: [{ timestamp: [1767225600], indicators: { quote: [{
            open: ["1.1"], high: ["1.2"], low: ["1.0"], close: ["1.15"], volume: ["12"] }] } }] } });
        const stringyCandle = handlerOf("yahoo").parseChart(ok("yahoo", stringy))[0];
        same(stringyCandle.close, 1.15, "numeric strings are coerced");
        same(stringyCandle.volume, 12);
        const withNaN = JSON.stringify({ chart: { result: [{ timestamp: [1, 2], indicators: { quote: [{
            open: ["NaN", 1], high: [1, 1], low: [1, 1], close: [1, null], volume: [] }] } }] } });
        equal(handlerOf("yahoo").parseChart(ok("yahoo", withNaN)), [], "NaN/null candles are dropped");
        same(handlerOf("yahoo").parseChart(ok("yahoo", sampleChartResponse()))[1].date, "2026-01-02");

        // The shared price/history parsers agree.
        equal(handlerOf("yahoo").parsePrice(ok("yahoo", sampleChartResponse())),
                               handlerOf("yahoo").parseChart(ok("yahoo", sampleChartResponse())));

        // No credential, no cookies, no extra headers beyond the shared UA.
        same(priceRequest.command[4].includes("-c \"$cookie\""), false, "Yahoo must not use a cookie jar");
        same(priceRequest.command[4].includes("-b "), false, "Yahoo must not send cookies");

        // ── Output follows the DataPoint contract ────────────────────────────────────
        {
            const messy = JSON.stringify({ chart: { result: [{ timestamp: [1767225600, 1767312000], indicators: { quote: [{
                open: [1.1, 1.2], high: [1.0, 1.3], low: [1.05, 1.1], close: [1.15, 1.25], volume: [-5, 12] }] } }] } });
            const points = handlerOf("yahoo").parseChart(ok("yahoo", messy));
            doesNotThrow(function() { Series.assertSeries(points) }, "every candle is valid and in order");
            same(points[0].volume, 0, "a nonsensical negative volume becomes 0");
            check(points[0].high >= Math.max(points[0].open, points[0].close) && points[0].low <= Math.min(points[0].open, points[0].close), "an inconsistent candle is widened to enclose open and close");
            same(points[1].volume, 12);
            same(points[0].date, "2026-01-01"); same(points[0].time, "00:00:00");
            // Candles out of time order are refused by the interface rather than drawn wrong.
            const shuffled = JSON.stringify({ chart: { result: [{ timestamp: [1767312000, 1767225600], indicators: { quote: [{
                open: [1, 1], high: [1, 1], low: [1, 1], close: [1, 1], volume: [0, 0] }] } }] } });
            throws(() => handlerOf("yahoo").parseChart(ok("yahoo", shuffled)), "older than the one before", "an out-of-order answer is a PARSE error");
        }

        //console.log("YahooProvider tests passed");

    }
}
