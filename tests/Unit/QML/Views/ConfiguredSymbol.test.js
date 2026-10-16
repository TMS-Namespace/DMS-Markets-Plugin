const { assert, same, readSource, loadShared, extractFunction } = require("../../../Helpers/Loader");
const vm = require("vm");

const view = readSource("QML/Views/ConfiguredSymbol.qml");
const { Resolution, ChartSpan, helpers, yahooConstants, wiseConstants } = loadShared();
// The view asks the QML ProvidersManager singleton for names; a stub with the real names stands in for it.
const names = { yahoo: yahooConstants.YAHOO_NAME, wise: wiseConstants.WISE_NAME };
const catalog = { defaultId: "yahoo", nameOf: (id) => names[id] || id };

// The settings list shows everything: ticker, provider, price resolution, chart resolution and range.
// Evaluate the real `text:` binding with the real modules.
const binding = /StyledText \{\s*text: \{([\s\S]*?)\n                    \}\n/.exec(view);
assert(binding, "details binding found");
function details(symbolData) {
    const context = vm.createContext({ symbolData, ProvidersManager: catalog, Resolution, ChartSpan, Helpers: helpers });
    return vm.runInContext(`(function() {${binding[1]}})()`, context);
}
assert.strictEqual(
    details({ ticker: "BRLPLN", provider: "wise", priceResolution: "1h", changeResolution: "1d", chartResolution: "1d", chartRange: "1M" }),
    "BRLPLN  |  Wise  |  price 1 Hour  |  change 1 Day  |  chart 1 Day over 1 Month");
assert.strictEqual(
    details({ ticker: "EURUSD=X", provider: "yahoo", priceResolution: "1m", changeResolution: "1d", chartResolution: "15m", chartRange: "1D", invert: true, showChangeWhenPinned: true }),
    "EURUSD=X  |  Yahoo Finance  |  price 1 Minute  |  change 1 Day  |  chart 15 Minutes over 1 Day  |  1/x  |  Δ on bar");
assert(details({ ticker: "OLD" }).startsWith(`OLD  |  ${catalog.nameOf(catalog.defaultId)}  |`), "a symbol without a provider shows the default provider");

// Labels, not raw ids, and no range fallbacks.
for (const raw of ['"1M"', '"1h"', '"1d"']) assert(!view.includes(`|| ${raw}`), `no ${raw} fallback`);
assert(/Resolution\.label\(symbolData\.priceResolution\)/.test(view));
assert(/Resolution\.label\(symbolData\.changeResolution\)/.test(view), "the change resolution is shown");
assert(/Resolution\.label\(symbolData\.chartResolution\)/.test(view), "the chart resolution is shown in the settings list");
assert(/ChartSpan\.label\(symbolData\.chartRange\)/.test(view));
assert(/symbolData\.name \|\| symbolData\.ticker/.test(view) && !/symbolData\.id\b/.test(view));
assert(!/@/.test(binding[1]), "the old raw '@ 1d' form is gone");

console.log("ConfiguredSymbol tests passed");
