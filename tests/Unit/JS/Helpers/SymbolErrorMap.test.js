const { assert, same, loadShared } = require("../../../Helpers/Loader");

const { errorMap: SymbolErrors, FetchType } = loadShared();
const priceType = FetchType.Values.PRICE,
    graphType = FetchType.Values.GRAPH;
const errorRecord = (code, text, details = "d") => ({ code, userMessage: text, details });

const priceErrors = SymbolErrors.set({}, "u1", priceType, errorRecord("network", "Can't reach Wise."));
same(priceErrors, { u1: { price: errorRecord("network", "Can't reach Wise.") } });
const bothErrors = SymbolErrors.set(
    priceErrors,
    "u1",
    graphType,
    errorRecord("noData", "Wise has no chart data for this symbol.")
);
assert.strictEqual(bothErrors.u1.price.userMessage, "Can't reach Wise.", "the other pull's error is kept");
assert.strictEqual(bothErrors.u1.graph.code, "noData");
const twoSymbolErrors = SymbolErrors.set(bothErrors, "u2", priceType, errorRecord("notFound", "Nope."));
assert.deepStrictEqual(Object.keys(twoSymbolErrors).sort(), ["u1", "u2"]);
const cleared = SymbolErrors.set(twoSymbolErrors, "u1", priceType, null);
assert.strictEqual(cleared.u1.price, undefined, "a success clears that pull's error");
assert.strictEqual(cleared.u1.graph.code, "noData", "…and only that one");
assert.strictEqual(
    "u1" in SymbolErrors.set(cleared, "u1", graphType, null),
    false,
    "nothing left: the symbol is clean again"
);
// Immutability: new objects for changes, the same map for no-ops.
assert.notStrictEqual(bothErrors, priceErrors);
assert.strictEqual("graph" in priceErrors.u1, false, "previous maps are never mutated");
assert.strictEqual(
    SymbolErrors.set(priceErrors, "zz", priceType, null),
    priceErrors,
    "clearing nothing returns the same map (no needless re-render)"
);
assert.strictEqual(SymbolErrors.set(priceErrors, "u1", graphType, null), priceErrors);
same(SymbolErrors.set({}, "u1", priceType, null), {});
assert.strictEqual(
    SymbolErrors.set(undefined, "u1", priceType, errorRecord("x", "m")).u1.price.userMessage,
    "m",
    "no map yet is fine"
);

// Reading
same(SymbolErrors.entry(bothErrors, "u1"), bothErrors.u1);
same(SymbolErrors.entry(bothErrors, "missing"), {});
same(SymbolErrors.entry(undefined, "u1"), {});
same(SymbolErrors.entry(null, "u1"), {});
assert(SymbolErrors.priceFailed(bothErrors.u1) && SymbolErrors.chartFailed(bothErrors.u1));
assert(
    !SymbolErrors.priceFailed({}) &&
        !SymbolErrors.chartFailed({}) &&
        !SymbolErrors.priceFailed(undefined) &&
        !SymbolErrors.chartFailed(null)
);
assert(
    SymbolErrors.chartFailed({ graph: errorRecord("a", "b") }) &&
        !SymbolErrors.priceFailed({ graph: errorRecord("a", "b") })
);
// What a card shows: a failed price wins over a failed chart; nothing when fine.
assert.strictEqual(SymbolErrors.message(bothErrors.u1), "Can't reach Wise.");
assert.strictEqual(SymbolErrors.message({ graph: errorRecord("noData", "No chart.") }), "No chart.");
assert.strictEqual(SymbolErrors.message({}), "");
assert.strictEqual(SymbolErrors.message(undefined), "");
assert.strictEqual(SymbolErrors.details(bothErrors.u1), "d");
assert.strictEqual(SymbolErrors.details({ price: { userMessage: "m" } }), "", "missing details read as empty");
assert.strictEqual(SymbolErrors.details({}), "");

console.log("SymbolErrors tests passed");
