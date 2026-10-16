// Unit tests of the Yahoo Finance API module: request URLs, answers, API error messages. Plain Node, no network.
const { assert, same, loadShared, throwsWith } = require("../../../../Helpers/Loader");

const { yahoo, yahooConstants: constants, Resolution, ChartSpan } = loadShared();
const answer = (rows, extra = {}) => JSON.stringify({ chart: { result: [Object.assign({
    timestamp: rows.map((row) => row.time),
    indicators: { quote: [{ open: rows.map((row) => row.open), high: rows.map((row) => row.high), low: rows.map((row) => row.low),
                            close: rows.map((row) => row.close), volume: rows.map((row) => row.volume) }] }
}, extra)], error: null } });
const row = (time, close, volume = 0) => ({ time, open: close, high: close, low: close, close, volume });
const DAY_SECONDS = 86400;

// ── Request URLs ─────────────────────────────────────────────────────────────
{
    const url = yahoo.priceUrl("EURUSD=X", "1m");
    assert(url.startsWith(constants.YAHOO_CHART_BASE_URL + "EURUSD%3DX?"), "the symbol is encoded into the path");
    assert(url.includes("range=1d") && url.includes("interval=1m"), "a 1m price needs the last day at 1m");
    assert(url.includes("includePrePost=false") && url.includes("events=history"), "fixed parameters");
    same([yahoo.priceUrl("X", "1d").includes("range=1mo"), yahoo.priceUrl("X", "1h").includes("interval=1h"), yahoo.priceUrl("X", "1w").includes("interval=1wk"),
          yahoo.priceUrl("X", "1M").includes("interval=1mo")], [true, true, true, true], "each resolution has its own interval name");
}
{
    // A chart range uses the smallest Yahoo range that covers it.
    const rangeOf = (resolution, span) => /range=([^&]+)/.exec(yahoo.historyUrl("X", resolution, span))[1];
    same(["1H", "3H", "12H", "1D"].map((span) => rangeOf("1m", span)), ["1d", "1d", "1d", "1d"], "up to a day: 1d");
    same(["1W", "1M", "3M", "6M", "1Y", "2Y", "5Y", "10Y"].map((span) => rangeOf("1d", span)),
         ["5d", "1mo", "3mo", "6mo", "1y", "2y", "5y", "10y"]);
    // The range always covers the span.
    for (const span of ChartSpan.ORDER) {
        const range = constants.YAHOO_RANGES.find((entry) => entry.range === rangeOf("1d", span));
        assert(range.days >= ChartSpan.days(span), `${span} is covered by ${range.range}`);
    }
}
{
    // Symbols with URL metacharacters never leak into the query.
    const url = yahoo.priceUrl("A&b=c#d", "1d");
    assert(!/[#]/.test(url) && url.split("?")[0].endsWith("A%26b%3Dc%23d"), "the symbol cannot add parameters");
    same(yahoo.pageUrl("^GSPC"), "https://finance.yahoo.com/quote/%5EGSPC");
}
throwsWith(() => yahoo.priceUrl("X", "2h"), "no price range", "unknown price resolution");
throwsWith(() => yahoo.historyUrl("X", "2h", "1M"), "unsupported resolution", "unknown chart resolution");
{
    const error = (() => { try { yahoo.priceUrl("X", "2h"); } catch (thrown) { return thrown; } })();
    same([error.code, error.userMessage], ["unsupported", "Yahoo Finance can't serve this chart setting."]);
}

// ── Answers ──────────────────────────────────────────────────────────────────
{
    const candles = yahoo.parseHistory(answer([row(1767225600, 1.1, 5), row(1767312000, 1.2), row(1767398400, 1.3, 7)]));
    same(candles.map((candle) => candle.close), [1.1, 1.2, 1.3]);
    same(candles.map((candle) => candle.volume), [5, 0, 7]);
    same([candles[0].date, candles[0].time], ["2026-01-01", "00:00:00"], "UTC date and time of the timestamp");
    same(yahoo.parsePrice(answer([row(1767225600, 1.1)])).length, 1, "price and history read the same answer");
}
{
    // Rows without every price are skipped; a volume that is not a number is 0 and never negative.
    const rows = [row(1767225600, 1.1), { time: 1767312000, open: null, high: 1, low: 1, close: 1, volume: 0 },
                  { time: 1767398400, open: 1, high: 1, low: 1, close: "NaN", volume: 0 }, { time: 1767484800, open: 1, high: 1, low: 1, close: 1, volume: -4 },
                  { time: 1767571200, open: "1.5", high: "1.5", low: "1.5", close: "1.5", volume: null }];
    const candles = yahoo.parseHistory(answer(rows));
    same(candles.map((candle) => candle.close), [1.1, 1, 1.5], "incomplete rows are dropped, numeric strings accepted");
    same(candles.map((candle) => candle.volume), [0, 0, 0]);
}
{
    // Only the newest `limit` valid candles are built.
    const rows = [1, 2, 3, 4, 5].map((close, index) => row(1767225600 + index * DAY_SECONDS, close));
    rows[4].close = null;                                                    // the newest row has no data
    const text = answer(rows);
    same(yahoo.parseHistory(text, 2).map((candle) => candle.close), [3, 4], "the newest two WITH data, oldest first");
    same(yahoo.parsePrice(text, 1).map((candle) => candle.close), [4]);
    same(yahoo.parseHistory(text, 0).length, 4, "0 = all");
    same(yahoo.parseHistory(text, 99).length, 4, "a limit above what exists returns everything");
}
{
    // A candle's high and low enclose its open and close.
    const odd = yahoo.parseHistory(answer([{ time: 1767225600, open: 1, high: 0.5, low: 2, close: 1.5, volume: 0 }]))[0];
    assert(odd.high >= Math.max(odd.open, odd.close) && odd.low <= Math.min(odd.open, odd.close), JSON.stringify(odd));
}
{
    // Valid answers without candles are "no data" (an empty list); anything else is a PARSE error.
    same(yahoo.parseHistory(JSON.stringify({ chart: { result: [{ meta: {} }], error: null } })), []);
    same(yahoo.parseHistory(answer([])), []);
    for (const broken of ["not json", "[]", "{}", '{"chart":{"result":[]}}', '{"chart":null}', ""]) {
        const error = (() => { try { yahoo.parseHistory(broken); } catch (thrown) { return thrown; } })();
        assert(error && error.code === "parse", `${JSON.stringify(broken)} is a PARSE error`);
        same(error.userMessage, "Yahoo Finance sent an answer that couldn't be understood.");
    }
}
{
    // The API's own error inside an answer becomes an HTTP error carrying its message.
    const text = JSON.stringify({ chart: { result: null, error: { code: "Not Found", description: "No data found, symbol may be delisted" } } });
    const error = (() => { try { yahoo.parseHistory(text); } catch (thrown) { return thrown; } })();
    same([error.code, error.userMessage], ["http", "Yahoo Finance: No data found, symbol may be delisted"]);
}

// ── The API's own error message ──────────────────────────────────────────────
same(yahoo.extractApiError(404, JSON.stringify({ chart: { error: { code: "Not Found", description: "No data found" } } })), "No data found");
same(yahoo.extractApiError(400, JSON.stringify({ chart: { error: { code: "Bad Request" } } })), "Bad Request", "the code when there is no description");
same(yahoo.extractApiError(400, JSON.stringify({ chart: { error: {} } })), "unknown error");
for (const none of [JSON.stringify({ chart: { result: [], error: null } }), "not json", "", "{}", "null"])
    same(yahoo.extractApiError(200, none), "", `${JSON.stringify(none)} carries no API error`);

// ── The module offers the API every provider must ────────────────────────────
for (const name of ["priceUrl", "historyUrl", "parsePrice", "parseHistory", "pageUrl", "extractApiError"])
    assert.strictEqual(typeof yahoo[name], "function", name);
assert(Resolution.ORDER.every((resolution) => constants.YAHOO_RESOLUTION_MAP[resolution]), "every resolution has a Yahoo interval name");

console.log("YahooApi tests passed");
