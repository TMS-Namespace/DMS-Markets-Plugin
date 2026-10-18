const { assert, loadModule, same, throwsWith } = require("../../../Helpers/Loader");
const registry = new Map();
const Series = loadModule("JS/Helpers/SeriesRules.js", registry);
const Price = loadModule("JS/Helpers/PriceRules.js", registry);
const Draft = loadModule("JS/Helpers/SymbolDraft.js", registry);
const Fetch = loadModule("JS/Helpers/FetchCommand.js", registry);
const ResponseInterpreter = loadModule("JS/Helpers/ResponseInterpreter.js", registry);
const Rules = loadModule("JS/Helpers/ProviderRules.js", registry);

// Series
const candle = Series.candle({ date: "2026-01-02", time: "10:00:00", open: 2, high: 1, low: 3, close: 4 });
same([candle.high, candle.low, candle.volume], [4, 2, 0], "high/low widened, volume defaults");
throwsWith(() => Series.candle({ date: "2026/01/02", open: 1, high: 1, low: 1, close: 1 }), "date", "bad date");
throwsWith(() => Series.candle({ date: "2026-01-02", open: NaN, high: 1, low: 1, close: 1 }), "open", "NaN");
throwsWith(
    () => Series.candle({ date: "2026-01-02", open: 1, high: 1, low: 1, close: 1, volume: -1 }),
    "volume",
    "volume"
);
const inverted = Series.transform(candle, (value) => 1 / value);
assert(inverted.low <= inverted.open && inverted.high >= inverted.close, "inversion keeps extremes");
const earlier = Series.candle({ date: "2026-01-01", open: 1, high: 1, low: 1, close: 1 });
const later = Series.candle({ date: "2026-01-02", open: 1, high: 1, low: 1, close: 1 });
Series.assertSeries([earlier, later]);
throwsWith(() => Series.assertSeries([later, earlier]), "older", "ordering");
throwsWith(() => Series.assertSeries("x"), "array", "not array");
throwsWith(
    () => Series.assertSeries([{ date: "2026-01-01", open: 1, high: 0, low: 1, close: 1 }]),
    "enclose",
    "unwidened"
);

// Price
const price = Price.priceFrom(Series.candle({ date: "2026-01-02", open: 2, high: 3, low: 1, close: 3 }));
same([price.change, price.changePercent], [1, 50]);
assert.strictEqual(
    Price.priceFrom(Series.candle({ date: "2026-01-02", open: 0, high: 1, low: 0, close: 1 })).changePercent,
    0
);

// A live snapshot row (open = high = low = close) is merged into the candle before it, so the change is not always 0
{
    const hourly = Series.candle({
        date: "2026-01-02",
        time: "22:00:00",
        open: 1.1221,
        high: 1.1224,
        low: 1.1215,
        close: 1.1217
    });
    const snapshot = Series.candle({
        date: "2026-01-02",
        time: "22:41:29",
        open: 1.1218,
        high: 1.1218,
        low: 1.1218,
        close: 1.1218
    });
    const merged = Price.priceFrom(snapshot, hourly);
    same(
        [merged.open, merged.high, merged.low, merged.close, merged.time],
        [1.1221, 1.1224, 1.1215, 1.1218, "22:41:29"]
    );
    assert(
        Math.abs(merged.change - (1.1218 - 1.1221)) < 1e-12 && merged.change < 0,
        "the change is from the previous candle's open"
    );
    assert(Math.abs(merged.changePercent - ((1.1218 - 1.1221) / 1.1221) * 100) < 1e-9);
    assert.strictEqual(Price.priceFrom(snapshot).change, 0, "with no previous candle a snapshot has no change");
    assert.strictEqual(
        Price.priceFrom(hourly, snapshot).change,
        hourly.close - hourly.open,
        "a real candle is never merged with the one before it"
    );
    assert(Price.isSnapshot(snapshot) && !Price.isSnapshot(hourly));
}

// Fetch command
const argv = Fetch.build("https://x.test/a?b=1", 5);
assert.strictEqual(argv[argv.length - 1], "https://x.test/a?b=1");
assert(argv[argv.length - 3].includes("tail -n 5"), "tail applied");
assert(Fetch.build("https://x.test", 0)[Fetch.build("https://x.test", 0).length - 3].includes('cat "$body_file"'));
same(Fetch.build("https://x.test", 0, "custom").slice(-3, -2), ["custom"]);
throwsWith(() => Fetch.build("http://x.test", 0), "https", "https only");
throwsWith(() => Fetch.build("https://x.test", -1), "tailLines", "tail");

// Response interpretation
const ok = ResponseInterpreter.fromProcess("y", "Y", {
    exitCode: 0,
    stdout: "MARKETS-RESPONSE 0 200\nhello",
    stderr: ""
});
same([ok.ok, ok.status, ok.body, ok.error], [true, 200, "hello", null]);
const e404 = ResponseInterpreter.fromProcess("y", "Y", {
    exitCode: 0,
    stdout: "MARKETS-RESPONSE 0 404\n{}",
    stderr: ""
});
assert(!e404.ok && e404.error.code === "notFound");
assert(ResponseInterpreter.fromProcess("y", "Y", { exitCode: 0, stdout: "MARKETS-RESPONSE 28 000\n" }).error.retryable);
assert.strictEqual(ResponseInterpreter.fromProcess("y", "Y", { exitCode: 127, stdout: "" }).error.code, "process");
throwsWith(() => ResponseInterpreter.assertOk(ResponseInterpreter.failure("y", new Error("x"))), "", "assertOk throws");
throwsWith(() => ResponseInterpreter.assertOk(null), "", "assertOk needs a response");

// Credentials
assert(Rules.isValidCredential({ requiresCredential: false }, ""));
assert(!Rules.isValidCredential({ requiresCredential: true, credentialMinLength: 3 }, "ab"));
assert(!Rules.isValidCredential({ disabled: true }, "x"));
// Form draft
const draft = Draft.fromSymbol(
    {
        ticker: "BRLPLN",
        name: "Real",
        provider: "wise",
        priceResolution: "1h",
        chartResolution: "1d",
        chartRange: "1M",
        showChangeWhenPinned: "true",
        invert: undefined
    },
    "yahoo"
);
same(draft, {
    ticker: "BRLPLN",
    name: "Real",
    provider: "wise",
    priceResolution: "1h",
    chartResolution: "1d",
    chartRange: "1M",
    showChange: true,
    invert: false
});
assert.strictEqual(Draft.fromSymbol({}, "yahoo").provider, "yahoo", "a missing provider is the default one");
same(Draft.empty("yahoo", { priceResolution: "1h", chartResolution: "1d", chartRange: "1M" }), {
    ticker: "",
    name: "",
    provider: "yahoo",
    priceResolution: "1h",
    chartResolution: "1d",
    chartRange: "1M",
    showChange: false,
    invert: false
});

console.log("Shared logic tests passed");
