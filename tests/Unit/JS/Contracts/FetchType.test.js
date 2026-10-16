const { assert, same, loadShared } = require("../../../Helpers/Loader");

const { FetchType } = loadShared();

same(FetchType.Values, { PRICE: "price", GRAPH: "graph", CHANGE: "change" });
same(FetchType.ORDER, ["price", "graph", "change"]);
assert(Object.isFrozen(FetchType.Values) && Object.isFrozen(FetchType.ORDER));
assert(FetchType.isValid("price") && FetchType.isValid("graph") && FetchType.isValid("change"));
for (const bad of ["Price", "chart", "", undefined, null, 1]) assert.strictEqual(FetchType.isValid(bad), false, String(bad));
assert.strictEqual(FetchType.timeKey("u1", FetchType.Values.PRICE), "u1_price", "key of a pull in the last-fetched map");
assert.strictEqual(FetchType.timeKey("u1", FetchType.Values.GRAPH), "u1_graph");

console.log("FetchType tests passed");
