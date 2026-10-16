const { assert, same, loadShared } = require("../../../Helpers/Loader");

const { Resolution, ChartSpan } = loadShared();

// ── The enum ─────────────────────────────────────────────────────────────────
same(Resolution.ORDER, Object.values(Resolution.Values), "ORDER lists every resolution, finest first");
for (let i = 1; i < Resolution.ORDER.length; i++)
    assert(Resolution.ms(Resolution.ORDER[i]) > Resolution.ms(Resolution.ORDER[i - 1]), "resolutions ascend");
assert(Object.isFrozen(Resolution.Values) && Object.isFrozen(Resolution.ORDER) && Object.isFrozen(Resolution.INFO), "read-only");
// Persisted values from older versions must stay valid.
for (const value of ["1m", "5m", "15m", "1h", "1d", "1w", "1M"]) assert(Resolution.isValid(value), `Resolution ${value}`);
for (const bad of ["2h", "", undefined, null, "1H", "d", 5, "toString", "__proto__", "hasOwnProperty"]) assert.strictEqual(Resolution.isValid(bad), false, String(bad));

// ── Labels and durations ─────────────────────────────────────────────────────
assert.strictEqual(Resolution.label("1M"), "1 Month");
assert.strictEqual(Resolution.label("1h"), "1 Hour");
assert.strictEqual(Resolution.shortLabel("1h"), "1 hour");
assert.strictEqual(Resolution.shortLabel("15m"), "15 min");
for (const resolution of Resolution.ORDER) {
    assert(Resolution.label(resolution).length > 0 && Resolution.shortLabel(resolution).length > 0 && Resolution.ms(resolution) > 0, resolution);
    assert(/^\d+ (Minutes?|Hour|Day|Week|Month)$/.test(Resolution.label(resolution)), Resolution.label(resolution));
}
assert.strictEqual(Resolution.ms("1m"), 60000);
assert.strictEqual(Resolution.ms("1h"), 3600000);
assert.strictEqual(Resolution.ms("1d"), 86400000);
assert.strictEqual(Resolution.ms("1w"), 7 * 86400000);
assert.strictEqual(Resolution.ms("1M"), 30 * 86400000);
assert.strictEqual(Resolution.ms("zzz"), 0);
assert.strictEqual(Resolution.label("zzz"), "zzz", "unknown values are echoed");
assert.strictEqual(Resolution.label(undefined), "", "missing values give an empty label");
assert.strictEqual(Resolution.label(""), "");
assert.strictEqual(Resolution.shortLabel(""), "");

// ── mapOf builds resolution-keyed tables ─────────────────────────────────────
const table = Resolution.mapOf([[Resolution.Values.H1, "hourly"], [Resolution.Values.D1, "daily"]]);
same(table, { "1h": "hourly", "1d": "daily" });
assert(Object.isFrozen(table));
same(Resolution.mapOf([]), {});

// Built on the shared time units: nothing is spelled out twice.
const source = require("fs").readFileSync(require("path").join(__dirname, "../../../../src/JS/Contracts/Resolution.js"), "utf8");
assert(/import "TimeUnits\.js" as TimeUnits/.test(source) && !/\b(60000|3600000|86400000)\b/.test(source.replace(/\/\/.*$/gm, "")));

console.log("Resolution tests passed");
