// FetchType.js — value domain: the kinds of pull the plugin makes for a symbol.
//
//   FetchType.Values.PRICE   "price"   the live price and its change (refreshed every price resolution)
//   FetchType.Values.GRAPH   "graph"   the chart history (refreshed every chart resolution)
//   FetchType.Values.CHANGE  "change"  the close the price is compared with (refreshed with the change resolution, at most an hour apart)

.pragma library


var Values = Object.freeze({
    PRICE: "price",
    GRAPH: "graph",
    CHANGE: "change"
})

var ORDER = Object.freeze([Values.PRICE, Values.GRAPH, Values.CHANGE])

function isValid(value) { return ORDER.indexOf(value) !== -1 }

// Key of a pull in the "last fetched" map: one entry per symbol and kind of pull.
function timeKey(uid, fetchType) { return uid + "_" + fetchType }
