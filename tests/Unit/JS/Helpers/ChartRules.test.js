const { assert, same, loadModule, createRegistry, loadShared } = require("../../../Helpers/Loader");

const registry = createRegistry();
const rules = loadModule("JS/Helpers/ChartRules.js", registry);
const constants = loadModule("JS/Helpers/Constants.js", registry);
const { Resolution, ChartSpan } = loadShared();

// ── Thresholds are constants, in a sane order ────────────────────────────────
const { CHART_CANDLES_BLOCK_MIN: blockMin, CHART_CANDLES_WARN_MIN: warnMin,
        CHART_CANDLES_WARN_MAX: warnMax, CHART_CANDLES_BLOCK_MAX: blockMax } = constants;
same([blockMin, warnMin, warnMax, blockMax], [3, 10, 100, 200], "thresholds: block<3, warn<10, warn>100, block>200");
assert(blockMin < warnMin && warnMin < warnMax && warnMax < blockMax, "ordered thresholds");
const source = require("fs").readFileSync(require("path").join(__dirname, "../../../../src/JS/Helpers/ChartRules.js"), "utf8");
assert(!/[<>]=?\s*(3|10|100|200)\b/.test(source.replace(/\/\/.*$/gm, "")), "thresholds are never compared as literals");

// ── Candle counting ──────────────────────────────────────────────────────────
assert.strictEqual(rules.candleCount("1d", "1M"), 30);
assert.strictEqual(rules.candleCount("1h", "1D"), 24);
assert.strictEqual(rules.candleCount("1w", "1Y"), 365 / 7);
assert.strictEqual(rules.candleCount("zzz", "1M"), 0);

// ── Levels at and around every boundary ──────────────────────────────────────
// candles = days / resolution; pick pairs that land near each threshold.
const level = (resolution, span) => rules.evaluate(resolution, span);
const cases = [
    // [resolution, span, candles, level, reason]
    ["1M", "1M", 1,    "block", "tooBig"],      // 1 candle  (< 3)
    ["1M", "3M", 3.03, "warn",  "tooBig"],      // 3.03: not < 3, so warn (< 10)
    ["1w", "1M", 4.28, "warn",  "tooBig"],
    ["1d", "1W", 7,    "warn",  "tooBig"],      // 7 < 10
    ["1w", "3M", 13,   "ok",    ""],
    ["1d", "1M", 30,   "ok",    ""],
    ["1d", "3M", 91,   "ok",    ""],
    ["15m", "1D", 96,  "ok",    ""],
    ["1d", "6M", 182,  "warn",  "tooSmall"],    // > 100
    ["1h", "1W", 168,  "warn",  "tooSmall"],
    ["1d", "1Y", 365,  "block", "tooSmall"],    // > 200
    ["1h", "1M", 720,  "block", "tooSmall"],
    ["1m", "1D", 1440, "block", "tooSmall"]
];
for (const [resolution, span, candles, expectedLevel, reason] of cases) {
    const result = level(resolution, span);
    assert.strictEqual(result.level, expectedLevel, `${resolution}/${span} (${candles} candles) → ${expectedLevel}`);
    assert.strictEqual(result.reason, reason, `${resolution}/${span} reason`);
    assert(Math.abs(result.candles - candles) < 0.1, `${resolution}/${span} candles ≈ ${candles}, got ${result.candles}`);
}

// Exact edges, using a stub-free search over the real enum pairs: values equal to
// a threshold are NOT beyond it.
for (const resolution of Resolution.ORDER)
    for (const span of ChartSpan.ORDER) {
        const { candles, level: evaluated } = level(resolution, span);
        if (candles < blockMin || candles > blockMax) assert.strictEqual(evaluated, "block", `${resolution}/${span}`);
        else if (candles < warnMin || candles > warnMax) assert.strictEqual(evaluated, "warn", `${resolution}/${span}`);
        else assert.strictEqual(evaluated, "ok", `${resolution}/${span}`);
    }

// ── Messages ─────────────────────────────────────────────────────────────────
assert.strictEqual(level("1d", "1M").message, "", "ok has no message");
assert(/too small for the current chart range.*prefer a bigger one/.test(level("1d", "6M").message),
       "too many candles: resolution too small → prefer a bigger one");
assert(/too big for the current chart range.*prefer a smaller one/.test(level("1d", "1W").message),
       "too few candles: resolution too big → prefer a smaller one");
assert(/^Note that/.test(level("1d", "6M").message), "warnings are phrased as notes");
assert(/cannot be used/.test(level("1d", "1Y").message) && /cannot be used/.test(level("1M", "1M").message), "blocks say so");
assert(level("1d", "1W").message.includes("7 candles"), "message includes the candle count");

// ── isAllowed ────────────────────────────────────────────────────────────────
assert.strictEqual(rules.isAllowed("1d", "6M"), true, "warn is allowed");
assert.strictEqual(rules.isAllowed("1d", "1Y"), false, "block is not");

// ── The user's example: a 1-year range ───────────────────────────────────────
assert.strictEqual(level("1M", "1Y").level, "ok", "1M candles on a 1Y chart are fine (12)");
assert.strictEqual(level("1w", "1Y").level, "ok", "1w candles on a 1Y chart (52)");
assert.strictEqual(level("1d", "1Y").level, "block", "daily on a 1Y chart is too much (365)");
assert.strictEqual(level("1M", "1M").level, "block", "a resolution as big as the range is blocked");

// ── Fine candles over short ranges (what the short ranges are for) ───────────
assert.strictEqual(level("1m", "1H").level, "ok", "1m over 1 hour: 60 candles");
assert.strictEqual(level("1m", "3H").level, "warn", "1m over 3 hours: 180 candles is a lot");
assert.strictEqual(level("1m", "6H").level, "block", "1m over 6 hours: 360 candles");
assert.strictEqual(level("5m", "1H").level, "ok", "12 candles");
assert.strictEqual(level("5m", "12H").level, "warn", "144 candles");
assert.strictEqual(level("15m", "1H").level, "warn", "4 candles: resolution a bit big");
assert.strictEqual(level("1h", "1H").level, "block", "one candle");
assert.strictEqual(level("1h", "3H").level, "warn", "exactly the block minimum (3) is not blocked");
assert(level("1h", "3H").candles === 3);

console.log("ChartRules tests passed");
