import QtQml
import "../../../../src/JS/Contracts/ChartSpan.js" as ChartSpan
import "../../../../src/JS/Helpers/SelectionPolicy.js" as Policy
import "../../../../src/JS/Helpers/SeriesRules.js" as Series
import "../../../../src/JS/Providers/Wise/WiseApi.js" as WiseApi
import "../../../../src/JS/Providers/Wise/WiseConstants.js" as WiseConstants
import "../../../../src/QML/Contracts"
import "../../../../src/QML/Services"
import "../../../Helpers"

TestSuite {
    property Component responseType: Component {
        ProviderResponse {
        }
    }

    function handlerOf(id) {
        return ProvidersManager.requireFromId(id);
    }
    function notSame(first, second, message) {
        check(first !== second, message || "values are identical");
    }
    function ok(providerId, body, status) {
        return (responseType.createObject(null, {
                providerId: providerId,
                ok: true,
                status: status || 200,
                body: body
            }) as ProviderResponse);
    }
    function test_wise_provider() {
        const values = options => options.map(option => option.value);

        // ── Properties (limits verified against the live Wise API) ───────────────────
        same(JSON.stringify(values(handlerOf("wise").priceResolutionOptions())), JSON.stringify(["1h", "1d"]), "Wise has no sub-hour, weekly or monthly data");
        same(JSON.stringify(values(handlerOf("wise").chartResolutionOptions())), JSON.stringify(["1h", "1d"]));
        // What the API can serve (declared) vs what the settings offer (also within the candle-count rules).
        equal(Policy.chartSpans(handlerOf("wise").properties, "1h"), ["1H", "3H", "6H", "12H", "1D", "1W", "1M"], "Wise hourly data is limited to 30 days");
        equal(values(handlerOf("wise").chartSpanOptions("1h")), ["3H", "6H", "12H", "1D", "1W"], "short ranges are available; 1H is a single candle and a month of hourly candles (720) is too many");
        same(JSON.stringify(values(handlerOf("wise").chartSpanOptions("1d"))), JSON.stringify(["1W", "1M", "3M", "6M"]), "years of daily candles are too many for the chart");
        same(Policy.chartSpans(handlerOf("wise").properties, "1d").includes("10Y"), false, "Wise must not declare 10Y (API caps at 5 years)");
        same(handlerOf("wise").chartSpanOptions("5m").length, 0);
        same(handlerOf("wise").symbolPageUrl("BRLPLN"), "https://wise.com/gb/currency-converter/brl-to-pln-rate", "Wise declares its browser URL");

        // ── Every declared combination builds a request ──────────────────────────────
        const wiseProperties = handlerOf("wise").properties;
        for (const interval of wiseProperties.priceResolutions)
            check(handlerOf("wise").priceRequest("BRLPLN", interval).url, `price ${interval}`);
        for (const resolution of Policy.chartResolutions(wiseProperties))
            for (const span of Policy.chartSpans(wiseProperties, resolution))
                check(handlerOf("wise").chartRequest("BRLPLN", resolution, span).url, `history ${resolution}/${span}`);

        // ── Unsupported requests throw ───────────────────────────────────────────────
        throws(() => handlerOf("wise").priceRequest("BRLPLN", "5m"), "price resolution '5m'", "sub-hour price");
        throws(() => handlerOf("wise").priceRequest("BRLPLN", "1w"), "price resolution '1w'", "weekly price");
        throws(() => handlerOf("wise").chartRequest("BRLPLN", "1w", "1Y"), "chart resolution '1w'", "weekly chart");
        throws(() => handlerOf("wise").chartRequest("BRLPLN", "1d", "10Y"), "'10Y' chart range", "10Y");
        throws(() => handlerOf("wise").chartRequest("BRLPLN", "1h", "3M"), "'3M' chart range", "hourly beyond 30 days");
        throws(() => handlerOf("wise").priceRequest("EUR", "1d"), "invalid symbol", "malformed symbol");

        // ── Request building ─────────────────────────────────────────────────────────
        const price = handlerOf("wise").priceRequest("BRLPLN", "1h");
        check(price.url.includes("wise.com/rates/history+live"), "Wise price URL should use the history+live endpoint");
        check(price.url.includes("source=BRL&target=PLN"), "Wise price URL should split the pair into source/target");
        check(price.url.includes("length=2&resolution=hourly&unit=day"), "Wise hourly price URL should use hourly resolution");
        check(handlerOf("wise").priceRequest("BRLPLN", "1d").url.includes("resolution=daily"));
        same(price.command[6], price.url, "Wise command should pass the provider URL separately");

        const tail = (resolution, span) => handlerOf("wise").chartRequest("BRL-PLN", resolution, span).url.split("&length=")[1];
        // Ranges shorter than a day still request a whole day; the fetcher trims to the range.
        same(tail("1h", "1H"), "1&resolution=hourly&unit=day");
        same(tail("1h", "3H"), "1&resolution=hourly&unit=day");
        same(tail("1h", "12H"), "1&resolution=hourly&unit=day");
        same(tail("1h", "1D"), "1&resolution=hourly&unit=day");
        same(tail("1h", "1W"), "7&resolution=hourly&unit=day");
        same(tail("1h", "1M"), "30&resolution=hourly&unit=day", "Hourly must stay within the 30-day window the API allows");
        same(tail("1d", "1W"), "7&resolution=daily&unit=day");
        same(tail("1d", "1M"), "30&resolution=daily&unit=day");
        same(tail("1d", "3M"), "3&resolution=daily&unit=month");
        same(tail("1d", "6M"), "6&resolution=daily&unit=month");
        same(tail("1d", "1Y"), "12&resolution=daily&unit=month");
        same(tail("1d", "2Y"), "24&resolution=daily&unit=month");
        same(tail("1d", "5Y"), "60&resolution=daily&unit=month", "5Y must hit, not exceed, the 60-month API cap");

        // ── Parsing ──────────────────────────────────────────────────────────────────
        const live = handlerOf("wise").parsePrice(ok("wise", JSON.stringify({
            source: "BRL",
            target: "PLN",
            value: 0.75,
            time: 1767312000000
        })));
        same(live.length, 1, "Wise live parser should turn the single object into one candle");
        same(live[0].close, 0.75, "Wise live close should be the quoted rate");

        const history = JSON.stringify([
            {
                value: "1.0",
                time: Date.UTC(2026, 0, 1)
            },
            {
                value: 1.1,
                time: String(Date.UTC(2026, 0, 2))
            },
            {
                value: null,
                time: Date.UTC(2026, 0, 3)
            },
            {
                value: "abc",
                time: Date.UTC(2026, 0, 4)
            },
            {
                value: 1.3,
                time: Date.UTC(2026, 0, 9)
            },
            {
                value: 1.2,
                time: Date.UTC(2026, 0, 8)
            }
        ]);
        const candles = handlerOf("wise").parseChart(ok("wise", history));
        same(candles.length, 4, "Wise parser drops non-numeric values and keeps every candle");
        check(candles.every(candle => typeof candle.close === "number" && typeof candle.open === "number"), "Wise parser must coerce numeric strings");
        same(JSON.stringify(candles.map(candle => candle.close)), JSON.stringify([1.0, 1.1, 1.2, 1.3]), "Wise candles are sorted ascending");
        same(candles[2].open, 1.1, "Wise candle open is the previous value");

        // ═════════════════════════════════════════════════════════════════════════════
        // Extended coverage
        // ═════════════════════════════════════════════════════════════════════════════

        // Every declared interval has an API resolution mapping.
        for (const interval of wiseProperties.priceResolutions)
            check(WiseConstants.WISE_API_RESOLUTION[interval], `mapping for ${interval}`);
        for (const resolution of Policy.chartResolutions(wiseProperties))
            check(WiseConstants.WISE_API_RESOLUTION[resolution]);

        // Declared spans never exceed the verified API windows.
        for (const span of Policy.chartSpans(wiseProperties, "1h"))
            check(ChartSpan.days(span) <= WiseConstants.WISE_DAY_UNIT_MAX_LENGTH, `hourly ${span} within 30 days`);
        for (const span of Policy.chartSpans(wiseProperties, "1d"))
            check(Math.round(ChartSpan.days(span) / 30.4375) <= WiseConstants.WISE_MONTH_UNIT_MAX_LENGTH, `daily ${span} within 60 months`);

        // Pair parsing accepts common spellings and rejects anything else.
        for (const spelling of ["BRLPLN", "brlpln", "BRL-PLN", "brl/pln", " BRL PLN "])
            equal(WiseApi.parsePair(spelling), {
                source: "BRL",
                target: "PLN"
            }, spelling);
        for (const bad of ["", "EUR", "EURUSDX", "123456", null, undefined])
            same(WiseApi.parsePair(bad), null, `rejects ${bad}`);

        // The symbol can never change the host or inject parameters.
        const url = handlerOf("wise").priceRequest("BRL-PLN", "1d").url;
        same(url, "https://wise.com/rates/history+live?source=BRL&target=PLN&length=2&resolution=daily&unit=day", "the dashed spelling is accepted and normalised");
        same(url.split("/")[2], "wise.com");
        for (const hostile of ["../../etc", "b&r/l#p?l-n=", "brl&target=USD#/../x?", "BRL PLN", "BRL/PLN", "BRL;PLN", "BRL$PLN", "`id`BRL", "BRL'PLN", "BRL\nPLN", "BRL\0PLN", "BRLPLN ", " BRLPLN", "BRLPLNX", "BRL--PLN", "BR1PLN", "BRLPL", "", "x".repeat(500)]) {
            throws(() => handlerOf("wise").priceRequest(hostile, "1d"), "invalid symbol", `rejects ${JSON.stringify(hostile.slice(0, 20))}`);
            throws(() => handlerOf("wise").chartRequest(hostile, "1d", "1M"), "invalid symbol", "history rejects it too");
            same(handlerOf("wise").validateSymbol(hostile).valid, false);
        }

        // Browser URLs.
        throws(() => handlerOf("wise").symbolPageUrl("not a pair"), "invalid symbol", "a damaged symbol raises INVALID_SYMBOL instead of building a broken URL");
        same(handlerOf("wise").symbolPageUrl("eur-usd"), "https://wise.com/gb/currency-converter/eur-to-usd-rate");

        // No cookies, no credentials.
        check(!price.command[4].includes("-c \"$cookie\"") && !price.command[4].includes("-b "), "Wise must not use cookies");
        same(handlerOf("wise").properties.requiresCredential, false);

        // Parser robustness.
        throws(() => handlerOf("wise").parseChart(ok("wise", "not json")), "not valid JSON", "unreadable answers are PARSE errors, not empty data");
        throws(() => handlerOf("wise").parseChart(ok("wise", "null")), "unexpected answer", "null");
        throws(() => handlerOf("wise").parseChart(ok("wise", "{}")), "no rates", "an object without rates");
        equal(handlerOf("wise").parseChart(ok("wise", "[]")), []);
        equal(handlerOf("wise").parseChart(ok("wise", JSON.stringify([null,
            {},
            {
                value: 1
            },
            {
                time: 1
            }
        ]))), [], "entries missing value or time are dropped");
        const single = handlerOf("wise").parsePrice(ok("wise", JSON.stringify([
            {
                value: 2,
                time: Date.UTC(2026, 5, 1, 13, 5, 9)
            }
        ])))[0];
        same(single.date, "2026-06-01");
        same(single.time, "13:05:09", "timestamps are rendered in UTC");
        same(single.open, single.close, "first candle opens at its own value");
        check(single.high >= single.low);
        const twoPoints = handlerOf("wise").parsePrice(ok("wise", JSON.stringify([
            {
                value: 2,
                time: 1000
            },
            {
                value: 1,
                time: 2000
            }
        ])));
        same(twoPoints[1].open, 2);
        same(twoPoints[1].high, 2);
        same(twoPoints[1].low, 1, "candle high/low span the step");
        // ── Output follows the DataPoint contract ────────────────────────────────────
        {
            const candles = handlerOf("wise").parseChart(ok("wise", JSON.stringify([
                {
                    value: 2,
                    time: 1000
                },
                {
                    value: 1,
                    time: 2000
                },
                {
                    value: 3,
                    time: 3000
                }
            ])));
            doesNotThrow(function () {
                Series.assertSeries(candles);
            }, "every candle is valid and in order");
            check(candles.every(candle => candle.volume === 0 && candle.high >= Math.max(candle.open, candle.close) && candle.low <= Math.min(candle.open, candle.close)), "volume 0; high and low enclose the step");
            doesNotThrow(function () {
                Series.assertSeries(handlerOf("wise").parsePrice(ok("wise", JSON.stringify({
                    value: 2,
                    time: 1000
                }))));
            });
        }

        //console.log("WiseProvider tests passed");

    }
    function values(options) {
        return options.map(function (option) {
            return option.value;
        });
    }

    Component.onCompleted: {
        if (!Array.prototype.at)
            Array.prototype.at = function (index) {
                const array = Array.from(this);
                return array[index < 0 ? array.length + index : index];
            };
    }
}
