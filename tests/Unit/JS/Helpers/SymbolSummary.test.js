// Verify decline percentages use tracked IDs and valid displayed changes, without needing new API requests.
const { assert, createRegistry, loadModule } = require("../../../Helpers/Loader");
const summary = loadModule("JS/Helpers/SymbolSummary.js", createRegistry());
const symbols = Array.from({ length: 9 }, (_, index) => ({ uid: String(index), ticker: "SAME" }));
assert.strictEqual(summary.detailsText([], {}), "Add symbols in Settings");
assert.strictEqual(summary.detailsText(symbols, {}), "9 symbols tracked");
const prices = {
    0: { close: 10, change: -1, changePercent: -8 },
    1: { close: 10, change: -0.00001, changePercent: -5 },
    2: { close: 10, change: 1, changePercent: 2 },
    3: { close: 10, change: 0 },
    4: { close: 10, change: -0 },
    removed: { close: 10, change: -1, changePercent: -99 }
};
assert.strictEqual(summary.detailsText(symbols, prices), "9 symbols tracked (22% of them down, -11% in total)");
assert.strictEqual(summary.detailsText([symbols[0]], prices), "1 symbol tracked (100% of them down, -8% in total)");
assert.strictEqual(summary.detailsText([symbols[2]], prices), "1 symbol tracked (0% of them down, +2% in total)");
for (const price of [
    null,
    {},
    { close: 0, change: -1 },
    { close: Infinity, change: -1 },
    { close: 10, change: NaN },
    { close: 10, change: -Infinity },
    { close: 10, change: "-1" }
]) {
    assert.strictEqual(summary.detailsText([symbols[0]], { 0: price }), "1 symbol tracked");
}
// Add percentages rather than averaging or compounding them, and keep small totals readable.
for (const [changes, total] of [
    [[0.1, 0.2], "+0.3"],
    [[-1.234, 0.001], "-1.23"],
    [[-0.001, 0], "0"],
    [[NaN, Infinity], "0"]
]) {
    assert.strictEqual(
        summary.detailsText(symbols.slice(0, 2), {
            0: { close: 10, change: 0, changePercent: changes[0] },
            1: { close: 10, change: 0, changePercent: changes[1] }
        }),
        "2 symbols tracked (0% of them down, " + total + "% in total)"
    );
}
console.log("Symbol summary tests passed");
