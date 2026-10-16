const { assert, same, readSource, loadShared, extractFunction } = require("../../../Helpers/Loader");
const vm = require("vm");

const view = readSource("QML/Views/ConfiguredSymbol.qml");
const { Resolution, ChartSpan, helpers, yahooConstants, wiseConstants } = loadShared();
// The view asks the QML ProvidersManager singleton for names; a stub with the real names stands in for it.
const aliases = { yahoo: "YHF", wise: "WIS", stooq: "STK" };
const catalog = { defaultId: "yahoo", aliasOf: (id) => aliases[id] || String(id).slice(0, 3).toUpperCase() };

// The settings list shows ONE line per symbol: name | ticker | provider alias | price resolution | chart resolution / range.
// Evaluate the real `text:` binding with the real modules.
const binding = /\/\/ One line:[^\n]*\n\s*StyledText \{\s*text: \{([\s\S]*?)\n                    \}\n/.exec(view);
assert(binding, "details binding found");
function details(symbolData) {
    const context = vm.createContext({ symbolData, ProvidersManager: catalog, Resolution, ChartSpan, Helpers: helpers });
    return vm.runInContext(`(function() {${binding[1]}})()`, context);
}
assert.strictEqual(
    details({ name: "BRL/PLN", ticker: "BRLPLN", provider: "wise", priceResolution: "1h", changeResolution: "1d", chartResolution: "1d", chartRange: "1M" }),
    "BRL/PLN  |  BRLPLN  |  WIS  |  1 hour  |  1 day / 1M");
assert.strictEqual(
    details({ name: "EUR/USD", ticker: "EURUSD=X", provider: "yahoo", priceResolution: "1m", changeResolution: "1d", chartResolution: "15m", chartRange: "1D", invert: true, showChangeWhenPinned: true }),
    "EUR/USD  |  EURUSD=X  |  YHF  |  1 min  |  15 min / 1D", "flags and the change resolution are not part of the line");
assert(details({ ticker: "OLD", priceResolution: "1h", chartResolution: "1d", chartRange: "1M" }).startsWith("OLD  |  OLD  |  YHF  |"), "no name: the ticker; no provider: the default provider's alias");
assert.strictEqual(details({ name: "A", ticker: "B", provider: "wise", priceResolution: "1h", chartResolution: "1d", chartRange: "1Y" }).split("|").length, 5, "five parts");

// One line in one style: a single text item for the whole summary, a little below the small size, never wrapped.
const info = /Symbol info \(name \+ metadata\)([\s\S]*?)Action buttons/.exec(view)[1];
assert.strictEqual((info.match(/StyledText \{/g) || []).length, 1, "one text item, one size and format");
assert(/Theme\.fontSizeSmall \+ constants\.configTextFontSizeDelta/.test(info) && /configTextFontSizeDelta:\s+-1/.test(readSource("QML/Helpers/Constants.qml")), "slightly smaller than small");
assert(/wrapMode:\s+Text\.NoWrap/.test(info) && /elide:\s+Text\.ElideRight/.test(info), "never more than one line");
assert(!/font\.weight/.test(info), "same format for every part");

// Labels, not raw ids, and no range fallbacks.
for (const raw of ['"1M"', '"1h"', '"1d"']) assert(!view.includes(`|| ${raw}`), `no ${raw} fallback`);
assert(/Resolution\.shortLabel\(symbolData\.priceResolution\)/.test(view) && /Resolution\.shortLabel\(symbolData\.chartResolution\)/.test(view));
assert(/ChartSpan\.shortLabel\(symbolData\.chartRange\)/.test(view) && /ProvidersManager\.aliasOf\(/.test(view), "compact forms and the provider alias");
assert(!/ProvidersManager\.nameOf/.test(view), "the long provider name does not fit one line");
assert(/symbolData\.name \|\| symbolData\.ticker/.test(view) && !/symbolData\.id\b/.test(view));

console.log("ConfiguredSymbol tests passed");
