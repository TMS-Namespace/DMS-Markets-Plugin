const { assert, same, loadShared } = require("../../../Helpers/Loader");

const { Resolution, ChartSpan } = loadShared();

// ── The enum ─────────────────────────────────────────────────────────────────
same(ChartSpan.ORDER, Object.values(ChartSpan.Values), "ORDER lists every span, shortest first");
same(ChartSpan.ORDER.slice(0, 5), ["1H", "3H", "6H", "12H", "1D"], "the ladder starts with hours");
for (let i = 1; i < ChartSpan.ORDER.length; i++)
    assert(ChartSpan.days(ChartSpan.ORDER[i]) > ChartSpan.days(ChartSpan.ORDER[i - 1]), "spans ascend");
assert(Object.isFrozen(ChartSpan.Values) && Object.isFrozen(ChartSpan.ORDER) && Object.isFrozen(ChartSpan.INFO), "read-only");
for (const value of ["1W", "1M", "3M", "6M", "1Y", "2Y", "5Y", "10Y"]) assert(ChartSpan.isValid(value), `ChartSpan ${value}`);
assert(ChartSpan.isValid("1D") && ChartSpan.isValid("1H"));
for (const bad of ["2D", "", undefined, null, "1h", "1m", 5, "toString", "__proto__"]) assert.strictEqual(ChartSpan.isValid(bad), false, String(bad));
// Persisted ids never collide between the two enums in a way that confuses lookups.
assert.strictEqual(Resolution.isValid("1H"), false, "1H (range) is not a resolution");
assert.strictEqual(ChartSpan.isValid("1h"), false, "1h (candle) is not a range");

// ── Labels and durations ─────────────────────────────────────────────────────
assert.strictEqual(ChartSpan.label("10Y"), "10 Years");
assert.strictEqual(ChartSpan.label("1H"), "1 Hour");
assert.strictEqual(ChartSpan.label("3H"), "3 Hours");
assert.strictEqual(ChartSpan.label("1M"), "1 Month");
for (const span of ChartSpan.ORDER) assert(/^\d+ (Hour|Hours|Day|Week|Month|Months|Year|Years)$/.test(ChartSpan.label(span)), span);
assert.strictEqual(ChartSpan.days("1H"), 1 / 24);
assert.strictEqual(ChartSpan.days("12H"), 0.5);
assert.strictEqual(ChartSpan.days("1M"), 30);
assert.strictEqual(ChartSpan.days("zzz"), 0);
// The compact form for the chart corner.
const compact = { "1H": "1H", "3H": "3H", "6H": "6H", "12H": "12H", "1D": "1D", "1W": "1W", "1M": "1M", "3M": "3M", "6M": "6M", "1Y": "1Y", "2Y": "2Y", "5Y": "5Y", "10Y": "10Y" };
for (const span of ChartSpan.ORDER) {
    assert.strictEqual(ChartSpan.shortLabel(span), compact[span], span);
    assert(/^\d+[HDWMY]$/.test(ChartSpan.shortLabel(span)), `${span} is a number and one letter`);
    assert(ChartSpan.shortLabel(span).length <= 3 && ChartSpan.shortLabel(span).length < ChartSpan.label(span).length, `${span} is shorter than its label`);
}
assert.strictEqual(ChartSpan.shortLabel(undefined), ""); assert.strictEqual(ChartSpan.shortLabel("zzz"), "zzz");
assert.strictEqual(ChartSpan.label(undefined), "");
assert.strictEqual(ChartSpan.label("zzz"), "zzz");
assert.strictEqual(ChartSpan.refreshMs, undefined, "refresh follows the resolution, not the range");

// ── pointLimit: the most candles a chart can hold ────────────────────────────
assert.strictEqual(ChartSpan.pointLimit("1d", "1M"), 32);
assert.strictEqual(ChartSpan.pointLimit("1h", "1D"), 26);
assert.strictEqual(ChartSpan.pointLimit("1d", "1Y"), 367);
assert.strictEqual(ChartSpan.pointLimit("1m", "1H"), 62, "60 one-minute candles in an hour, plus slack");
assert.strictEqual(ChartSpan.pointLimit("5m", "12H"), 146);
assert.strictEqual(ChartSpan.pointLimit("1h", "6H"), 8);
assert.strictEqual(ChartSpan.pointLimit("zzz", "1M"), 0, "unknown resolution yields no limit");
assert(ChartSpan.pointLimit("1h", "1W") < ChartSpan.pointLimit("1m", "1W"), "finer candles hold more points");

// ── A value domain only: legacy formats are SymbolMigration's business ───────
const source = require("fs").readFileSync(require("path").join(__dirname, "../../../../src/JS/Contracts/ChartSpan.js"), "utf8");
assert(!/LEGACY_/.test(source), "ChartSpan holds no legacy tables");

console.log("ChartSpan tests passed");
