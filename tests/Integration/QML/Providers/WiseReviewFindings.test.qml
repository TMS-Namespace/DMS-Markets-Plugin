import QtQml
import "../../../Helpers"
import "../../../../src/QML/Services"
import "../../../../src/QML/Contracts"
import "../../../../src/JS/Helpers/SelectionPolicy.js" as Policy
import "../../../../src/JS/Contracts/ChartSpan.js" as ChartSpan
import "../../../../src/JS/Helpers/SeriesRules.js" as Series
import "../../../../src/JS/Contracts/Resolution.js" as Resolution

TestSuite {
    property Component storageType: Component { DataStorage {} }

    function handlerOf(id) { return ProvidersManager.requireFromId(id) }
    Component.onCompleted: { if (!Array.prototype.at) Array.prototype.at = function(i) { return this[i < 0 ? this.length + i : i] } }
    property Component responseType: Component { ProviderResponse {} }
    function ok(providerId, body, status) { return responseType.createObject(null, { providerId: providerId, ok: true, status: status || 200, body: body }) }
    function notSame(first, second, message) { check(first !== second, message || "values are identical") }
    function values(options) { return options.map(function(option) { return option.value }) }

    function test_wise_review_findings() {
        // Regression tests for the findings of the Wise provider code review. Each section
        // names the finding it locks down and uses data shaped like the live API.

        const wise = handlerOf("wise").properties;
        const HOUR = 3600000, DAY = 86400000;
        const values = (options) => options.map((option) => option.value);

        // ─────────────────────────────────────────────────────────────────────────────
        // Finding 1 - the 1w / 1M price "change" was really a one-day move
        // Wise only has hourly and daily data, so it no longer offers weekly/monthly price
        // resolutions; the change shown is "live vs the last published point of that size".
        // ─────────────────────────────────────────────────────────────────────────────
        equal(values(handlerOf("wise").priceResolutionOptions()), ["1h", "1d"], "no weekly / monthly price resolutions to mislabel");
        for (const resolution of ["1m", "5m", "15m", "1w", "1M"])
            throws(() => handlerOf("wise").priceRequest("BRLPLN", resolution), `price resolution '${resolution}'`, `rejected: ${resolution}`);
        {
            // Shapes observed on the live API: hourly points up to the current hour, then the live rate.
            const hourly = JSON.stringify([
                { value: 0.7718, time: Date.UTC(2026, 9, 15, 10) },
                { value: 0.7714, time: Date.UTC(2026, 9, 15, 11) },
                { value: 0.7723, time: Date.UTC(2026, 9, 15, 12, 3, 1) }          // live
            ]);
            const candle = handlerOf("wise").parsePrice(ok("wise", hourly)).at(-1);
            same(candle.open, 0.7714, "hourly change is measured from the start of the current hour");
            same(candle.close, 0.7723);
            check(Math.abs((candle.close - candle.open) - 0.0009) < 1e-9);
            // Daily points are published at 00:00 UTC; today's is not there yet, so the change is vs the last daily point.
            const daily = JSON.stringify([
                { value: 0.7879, time: Date.UTC(2026, 9, 13) },
                { value: 0.7764, time: Date.UTC(2026, 9, 14) },
                { value: 0.7723, time: Date.UTC(2026, 9, 15, 12, 3, 1) }
            ]);
            const dayCandle = handlerOf("wise").parsePrice(ok("wise", daily)).at(-1);
            same(dayCandle.open, 0.7764, "daily change is measured from the last daily point");
            same(dayCandle.close, 0.7723);
            same(dayCandle.high, 0.7764); same(dayCandle.low, 0.7723, "high/low span the step");
        }
        // The price request asks for exactly what that needs.
        check(handlerOf("wise").priceRequest("BRLPLN", "1h").url.includes("resolution=hourly&unit=day"));
        check(handlerOf("wise").priceRequest("BRLPLN", "1d").url.includes("resolution=daily&unit=day"));
        // Yahoo keeps true weekly/monthly price candles (open = start of the period), so those stay available there.
        const yahooWeekly = JSON.stringify({ chart: { result: [{ timestamp: [1760000000], indicators: { quote: [{
            open: [1.10], high: [1.20], low: [1.05], close: [1.18], volume: [0] }] } }] } });
        same(handlerOf("yahoo").parsePrice(ok("yahoo", yahooWeekly))[0].open, 1.10, "weekly candle opens at the start of the week");
        same(values(handlerOf("yahoo").priceResolutionOptions()).includes("1w"), true);

        // ─────────────────────────────────────────────────────────────────────────────
        // Finding 2 - a "10 Years" chart silently showed only ~5 years
        // A range is only offered if the provider can really serve it, and the request
        // always covers at least the labelled span.
        // ─────────────────────────────────────────────────────────────────────────────
        for (const resolution of Policy.chartResolutions(wise))
            same(Policy.chartSpans(wise, resolution).includes("10Y"), false, `Wise ${resolution} does not declare 10Y`);
        throws(() => handlerOf("wise").chartRequest("BRLPLN", "1d", "10Y"), "'10Y' chart range", "10Y is refused, not clamped");
        throws(() => handlerOf("wise").chartRequest("BRLPLN", "1h", "3M"), "'3M' chart range", "hourly beyond 30 days is refused");
        for (const resolution of Policy.chartResolutions(wise))
            same(values(handlerOf("wise").chartSpanOptions(resolution)).includes("10Y"), false);
        {
            const daysRequested = (url) => {
                const query = new URL(url).searchParams;
                const length = Number(query.get("length"));
                return query.get("unit") === "month" ? length * 30.4375 : length;
            };
            for (const resolution of Policy.chartResolutions(wise))
                for (const span of Policy.chartSpans(wise, resolution)) {
                    const url = handlerOf("wise").chartRequest("BRLPLN", resolution, span).url;
                    check(daysRequested(url) >= ChartSpan.days(span) - 0.5, `${resolution}/${span}: the request covers the labelled span`);
                    check(daysRequested(url) <= Policy.historyLimitDays(wise, resolution) + 1, `${resolution}/${span}: ...and stays within the API window`);
                }
        }
        same(Policy.historyLimitDays(wise, "1d"), 1826, "5 years back is the documented limit");

        // ─────────────────────────────────────────────────────────────────────────────
        // Finding 3 - a stale price selection survived a provider switch, and clamping
        // only happened on save
        // ─────────────────────────────────────────────────────────────────────────────
        {
            const selection = handlerOf("wise").clampSelection({ priceResolution: "5m", chartResolution: "15m", chartRange: "1Y" });
            equal([selection.priceResolution, selection.chartResolution, selection.chartRange], ["1h", "1h", "1W"],
                 "switching to Wise moves every dropdown to a supported value immediately");
            // Symbols already saved with unsupported values are fixed on load, not only when edited and saved.
            const migrated = storageType.createObject(null).migrate([{ id: "BRLPLN", provider: "wise", priceInterval: "5m", graphInterval: "10Y" }]);
            same(migrated.changed, true);
            same(migrated.symbols[0].priceResolution, "1h");
            same(migrated.symbols[0].chartRange, "6M");
        }

        // ─────────────────────────────────────────────────────────────────────────────
        // Findings 4 and 8 - duplicated, hard-coded point limits; request and trimming
        // could disagree
        // ─────────────────────────────────────────────────────────────────────────────
        {
            // Trimming never cuts data the API legitimately returns for any declared range.
            for (const resolution of Policy.chartResolutions(wise))
                for (const span of Policy.chartSpans(wise, resolution)) {
                    const candlesReturned = ChartSpan.days(span) * DAY / Resolution.ms(resolution) + 1;   // incl. the live point
                    check(ChartSpan.pointLimit(resolution, span) >= Math.min(candlesReturned, Policy.historyLimitDays(wise, resolution) * DAY / Resolution.ms(resolution) + 1),
                           `${resolution}/${span}: the limit keeps every returned candle`);
                }
        }

        // ─────────────────────────────────────────────────────────────────────────────
        // Finding 5 - weekly/monthly series were built from epoch-aligned 7/30-day buckets
        // Wise serves no such candles any more, so nothing is bucketed.
        // ─────────────────────────────────────────────────────────────────────────────
        throws(() => handlerOf("wise").chartRequest("BRLPLN", "1w", "1Y"), "chart resolution '1w'", "no weekly candles");
        throws(() => handlerOf("wise").chartRequest("BRLPLN", "1M", "5Y"), "chart resolution '1M'", "no monthly candles");
        {
            const dailyPoints = Array.from({ length: 21 }, (_, i) => ({ value: 1 + i / 100, time: Date.UTC(2026, 0, 1) + i * DAY }));
            const candles = handlerOf("wise").parseChart(ok("wise", JSON.stringify(dailyPoints)));
            same(candles.length, 21, "every daily point is a daily candle (no merging)");
            equal(candles.map((candle) => candle.date).slice(0, 3), ["2026-01-01", "2026-01-02", "2026-01-03"]);
        }

        // ─────────────────────────────────────────────────────────────────────────────
        // Finding 6 - values and times were not coerced, so strings, "", [] or booleans
        // could reach the maths and the sort
        // ─────────────────────────────────────────────────────────────────────────────
        {
            const parse = (rows) => handlerOf("wise").parseChart(ok("wise", JSON.stringify(rows)));
            const utcDate = (dayOfMonth) => Date.UTC(2026, 0, dayOfMonth);
            // Numeric strings are accepted and become real numbers.
            const coerced = parse([{ value: "1.5", time: String(utcDate(2)) }, { value: 2, time: utcDate(1) }]);
            check(coerced.every((candle) => ["open", "high", "low", "close"].every((field) => typeof candle[field] === "number")), "all fields are numbers");
            equal(coerced.map((candle) => candle.close), [2, 1.5], "string times are compared as numbers");
            // Lexical vs numeric ordering: "9" < "10" only when sorted numerically.
            equal(parse([{ value: 3, time: "10000000000" }, { value: 2, time: "9000000000" }]).map((candle) => candle.close), [2, 3], "numeric sort, not string sort");
            // Things Number() would silently accept are rejected.
            for (const junk of ["", "   ", [], [5], {}, true, false, null, undefined, "abc", "1e999", NaN, Infinity, -1, 0, "-3", "0"])
                same(parse([{ value: junk, time: utcDate(1) }]).length, 0, `value ${JSON.stringify(junk)} is dropped`);
            for (const junk of ["", [], [5], true, null, undefined, "x", 0, -5, "0", Infinity])
                same(parse([{ value: 1, time: junk }]).length, 0, `time ${JSON.stringify(junk)} is dropped`);
            same(parse([null, 5, "x", [], {}]).length, 0, "non-object entries are ignored");
            same(parse([{ value: 1, time: utcDate(1) }, { value: "x", time: utcDate(2) }, { value: 3, time: utcDate(3) }]).length, 2, "good rows around a bad one survive");
            // A live (single object) payload goes through the same checks.
            same(handlerOf("wise").parsePrice(ok("wise", JSON.stringify({ value: "", time: utcDate(1) }))).length, 0);
            same(handlerOf("wise").parsePrice(ok("wise", JSON.stringify({ value: "0.75", time: String(utcDate(1)) })))[0].close, 0.75);
            // Candles built from clean numbers are well-formed.
            for (const candle of parse([{ value: 2, time: utcDate(1) }, { value: 1, time: utcDate(2) }, { value: 3, time: utcDate(3) }])) {
                check(candle.high >= candle.open && candle.high >= candle.close && candle.low <= candle.open && candle.low <= candle.close, "OHLC is consistent");
                check(/^\d{4}-\d{2}-\d{2}$/.test(candle.date) && /^\d{2}:\d{2}:\d{2}$/.test(candle.time), "date and time are never NaN");
            }
        }

        //console.log("Wise review-finding regression tests passed");

    }
}
