const { assert, loadModule, same } = require("../../../Helpers/Loader");
const Migration = loadModule("JS/Helpers/SymbolMigration.js", new Map());

const validUid = "11111111-1111-4111-8111-111111111111";
const full = {
    uid: validUid,
    ticker: "BRLPLN",
    name: "Real",
    provider: "wise",
    priceResolution: "1h",
    changeResolution: "1d",
    chartResolution: "1d",
    chartRange: "1M",
    showChangeWhenPinned: false,
    invert: false,
    pinned: false
};
const sorted = (object) =>
    Object.fromEntries(Object.entries(object).sort(([firstKey], [secondKey]) => (firstKey < secondKey ? -1 : 1)));

// ── upgrade: format only ─────────────────────────────────────────────────────
const old = {
    id: "BRLPLN",
    name: "Real",
    provider: "wise",
    priceInterval: "5m",
    graphResolution: "1d",
    graphInterval: "1Y",
    pinned: true,
    custom: "kept"
};
const upgraded = Migration.upgrade(old, "yahoo");
assert.strictEqual(upgraded.changed, true);
same(
    sorted(upgraded.symbol),
    sorted({
        ticker: "BRLPLN",
        name: "Real",
        provider: "wise",
        priceResolution: "5m",
        chartResolution: "1d",
        chartRange: "1Y",
        pinned: true,
        custom: "kept",
        uid: upgraded.symbol.uid,
        showChangeWhenPinned: false,
        invert: false
    })
);
assert(old.id === "BRLPLN" && "priceInterval" in old, "input is not modified");
assert.strictEqual(Migration.upgrade(full, "yahoo").symbol, full, "current format comes back untouched");
assert.strictEqual(Migration.upgrade(full, "yahoo").changed, false);
assert.strictEqual(
    Migration.upgrade({ ...full, uid: "bad" }, "x").symbol.uid === "bad",
    false,
    "malformed uid replaced"
);
assert.strictEqual(Migration.upgrade({ ...full, provider: undefined }, "yahoo").symbol.provider, "yahoo");
assert.strictEqual(Migration.upgrade({ ...full, provider: undefined }).symbol.provider, undefined);
assert.strictEqual(Migration.upgrade({ ...full, name: undefined }, "x").symbol.name, "BRLPLN");
assert.strictEqual(Migration.upgrade({ ...full, invert: "true", pinned: undefined }, "x").symbol.invert, true);
assert.strictEqual(
    Migration.upgrade({ ...full, id: "OLD" }, "x").symbol.ticker,
    "BRLPLN",
    "current field wins over legacy"
);
assert.notStrictEqual(
    Migration.upgrade({}, "x", 0).symbol.uid,
    Migration.upgrade({}, "x", 1).symbol.uid,
    "uids differ by position (the same ticker twice gets two handles)"
);
assert.strictEqual(
    Migration.upgrade({ id: "A" }, "x", 3).symbol.uid,
    Migration.upgrade({ id: "A" }, "x", 3).symbol.uid,
    "...and are the same every time, so every migrator agrees"
);
assert.notStrictEqual(
    Migration.upgrade({ id: "A", provider: "yahoo" }, "x", 0).symbol.uid,
    Migration.upgrade({ id: "A", provider: "wise" }, "x", 0).symbol.uid,
    "the provider is part of it"
);

// Legacy ranges: a range that was a candle size, and symbols without chart resolution.
same(
    [Migration.upgrade({ ...full, chartResolution: undefined, chartRange: "1w" }, "x").symbol].map((symbol) => [
        symbol.chartRange,
        symbol.chartResolution
    ])[0],
    ["3M", "1d"]
);
same(
    [Migration.upgrade({ ...full, chartResolution: undefined, chartRange: "10Y" }, "x").symbol].map((symbol) => [
        symbol.chartRange,
        symbol.chartResolution
    ])[0],
    ["10Y", "1M"]
);
same(
    [Migration.upgrade({ ...full, chartResolution: "1h", chartRange: "1d" }, "x").symbol].map((symbol) => [
        symbol.chartRange,
        symbol.chartResolution
    ])[0],
    ["1M", "1h"]
);

// ── migrate: also moves ranges to what the provider serves ───────────────────
const wise = {
    name: "Wise",
    minPullResolution: "1h",
    priceResolutions: ["1h", "1d"],
    changeResolutions: ["1h", "1d"],
    chartLimits: [
        { resolution: "1h", maxHistoryDays: 30 },
        { resolution: "1d", maxHistoryDays: 0 }
    ]
};
const rulesOf = (id) => (id === "wise" ? wise : null);
const list = [
    { id: "BRLPLN", provider: "wise", priceInterval: "5m", graphInterval: "10Y" },
    { id: "GHOST", provider: "gone", priceInterval: "5m", graphInterval: "1M", graphResolution: "1d" },
    { ...full }
];
const snapshot = JSON.stringify(list);
const result = Migration.migrate(list, "wise", rulesOf);
assert.strictEqual(JSON.stringify(list), snapshot, "list not modified");
assert.strictEqual(result.changed, true);
assert.strictEqual(result.symbols[0].priceResolution, "1h");
assert.strictEqual(result.symbols[0].changeResolution, "1d", "symbols saved before the setting existed get one day");
const keptHour = Migration.migrate([{ ...full, changeResolution: "1h" }], "wise", rulesOf);
assert.strictEqual(keptHour.symbols[0].changeResolution, "1h", "a chosen change resolution is kept");
assert.strictEqual(keptHour.changed, false);
const withoutChange = Migration.migrate([{ ...full, changeResolution: undefined }], "wise", rulesOf);
assert(
    withoutChange.changed && withoutChange.symbols[0].changeResolution === "1d",
    "a symbol lacking it is migrated and flagged for saving"
);
assert.strictEqual(result.symbols[0].ticker, "BRLPLN");
assert.strictEqual(result.symbols[1].priceResolution, "5m", "unknown provider keeps its values");
assert.strictEqual(result.symbols[2], list[2], "untouched entry is the same object");
const again = Migration.migrate(result.symbols, "wise", rulesOf);
assert.strictEqual(again.changed, false, "idempotent");
assert.strictEqual(Migration.migrate(undefined, "wise", rulesOf).changed, false);
console.log("SymbolMigration tests passed");

// Old XOR-hex credentials and the original plain-text format remain readable.
const credentialMigration = Migration;
assert.strictEqual(credentialMigration.deobfuscate("091617414109"), "abc123");
assert.strictEqual(credentialMigration.deobfuscate(""), "");
assert.strictEqual(credentialMigration.deobfuscate("legacy plain text!"), "legacy plain text!");
