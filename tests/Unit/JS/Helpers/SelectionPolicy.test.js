const { assert, loadModule, same, throwsWith } = require("../../../Helpers/Loader");
const registry = new Map();
const Policy = loadModule("JS/Helpers/SelectionPolicy.js", registry);
const Rules = loadModule("JS/Helpers/SymbolRules.js", registry);

// Plain-data provider descriptor: the policy needs no class.
const wise = {
    name: "Wise", minPullResolution: "1h",
    priceResolutions: ["1h", "1d"],
    changeResolutions: ["1h", "1d"],
    chartLimits: [{ resolution: "1h", maxHistoryDays: 30 }, { resolution: "1d", maxHistoryDays: 0 }],
    symbolPattern: "^[A-Z]{6}$", symbolMinLength: 6, symbolMaxLength: 6, symbolFormatMessage: "Use 6 capital letters."
};

same(Policy.priceResolutions(wise), ["1h", "1d"], "price resolutions");
same(Policy.changeResolutions(wise), ["1h", "1d"], "change resolutions");
assert.strictEqual(Policy.defaultChangeResolution(wise), "1d", "the change defaults to one day");
assert.strictEqual(Policy.defaultChangeResolution({ ...wise, changeResolutions: ["1h"] }), "1h", "…or the nearest one the provider declares");
Policy.assertChange(wise, "1d");
throwsWith(() => Policy.assertChange(wise, "1w"), "can't measure", "unsupported change resolution");
assert.strictEqual(Policy.changeRefreshMs("1d"), 3600000, "a daily change is re-read hourly, not daily");
assert.strictEqual(Policy.changeRefreshMs("1m"), 60000);
same(Policy.chartResolutions(wise), ["1h", "1d"], "chart resolutions");
assert(Policy.chartSpans(wise, "1h").indexOf("1M") !== -1 && Policy.chartSpans(wise, "1h").indexOf("3M") === -1, "1h limited to 30 days");
same(Policy.chartSpans(wise, "5m"), [], "unsupported resolution has no spans");
assert(Policy.allowedChartSpans(wise, "1d").length > 0, "allowed spans");

throwsWith(() => Policy.assertPrice(wise, "5m"), "5 Minute", "unsupported price");
throwsWith(() => Policy.assertChart(wise, "1h", "1Y"), "can't show", "span beyond limit");
throwsWith(() => Policy.assertPull(wise, "1m"), "refreshed", "too fast");
Policy.assertPull(wise, "1h");

const defaults = Policy.defaultSelection(wise);
assert.strictEqual(defaults.priceResolution, "1h");
assert.strictEqual(defaults.changeResolution, "1d");
assert(Policy.supportsChart(wise, defaults.chartResolution, defaults.chartRange), "default selection is servable");

const clamped = Policy.clamp(wise, { priceResolution: "5m", chartResolution: "5m", chartRange: "1Y" });
assert.strictEqual(clamped.priceResolution, "1h");
assert.strictEqual(clamped.changeResolution, "1d", "a missing change resolution gets the default");
assert.strictEqual(Policy.clamp(wise, { changeResolution: "1M" }).changeResolution, "1d", "an unserved one moves to the nearest")
assert(Policy.supportsChart(wise, clamped.chartResolution, clamped.chartRange), "clamped selection is servable");
const clampedDaily = Policy.clamp(wise, { priceResolution: "1d", chartResolution: "1d", chartRange: "1M" });
assert.strictEqual(clampedDaily.chartResolution, "1d");

// Symbol rules
assert(Rules.validate(wise, "BRLPLN").valid);
assert(!Rules.validate(wise, "BRL").valid && Rules.validate(wise, "BRL").message.includes("6"));
assert(!Rules.validate(wise, "").valid);
throwsWith(() => Rules.assertValid(wise, "brlpln"), "6 capital", "bad symbol");
assert.strictEqual(Rules.patternProblem("^[A-Z]{6}$"), "");
assert(Rules.patternProblem("^.+$") !== "", "dot admits metacharacters");
assert(Rules.patternProblem("[A-Z]") !== "", "must be anchored");
console.log("SelectionPolicy/SymbolRules tests passed");
