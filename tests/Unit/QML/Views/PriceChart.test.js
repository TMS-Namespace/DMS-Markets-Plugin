const { assert, same, readSource, loadShared } = require("../../../Helpers/Loader");

const chart = readSource("QML/Views/PriceChart.qml");
const row = readSource("QML/Views/SymbolRow.qml");
const popout = readSource("QML/Views/PopoutPanel.qml");
const widget = readSource("QML/Widget.qml");
const constants = readSource("QML/Helpers/Constants.qml");
const { helpers } = loadShared();

// ── The label: lower-left, like the range label is upper-left ────────────────
const block = /\/\/ ── Provider alias label[\s\S]*?\n    StyledText \{([\s\S]*?)\n    \}/.exec(chart);
assert(block, "provider alias label exists");
const label = block[1];
assert(/anchors\.left:\s+parent\.left/.test(label) && /anchors\.bottom:\s+parent\.bottom/.test(label), "anchored lower-left");
assert(/text:\s+chart\.providerAlias/.test(label), "shows the provider alias, not the long name");
assert(/chart\.showProviderName && chart\.providerAlias !== ""/.test(label), "hidden when disabled or without an alias");
assert(/processor\.closes\.length >= 2/.test(label), "only drawn with a chart, like the range label");
assert(/chartLabelLeftMargin/.test(label) && /chartLabelBottomMargin/.test(label), "uses the shared label margins");
assert(/chartLabelFontSizeDelta/.test(label) && /chartLabelOpacity/.test(label), "same style as the range label");
assert(/chartLabelBottomMargin:\s+\d+/.test(constants), "bottom margin constant defined");
assert(/property bool\s+showProviderName: true/.test(chart), "label defaults to on in the chart");
assert(/property string providerAlias:\s+""/.test(chart));
assert(!/providerName/.test(chart), "the chart never gets the long name");

// The range label is still top-left and independent of the provider label.
assert(/anchors\.top:\s+parent\.top/.test(/Chart range label[\s\S]*?StyledText \{([\s\S]*?)\n    \}/.exec(chart)[1]));

// ── Wiring: plugin data → Widget → PopoutPanel → SymbolRow → PriceChart ──────
assert(/property bool showProviderName:\s+Helpers\.pluginDataBool\(pluginData\.showProviderName\)/.test(widget),
       "Widget reads the setting, defaulting to on");
assert.strictEqual(helpers.pluginDataBool(undefined), true, "unset setting means on");
assert.strictEqual(helpers.pluginDataBool(false), false);
assert.strictEqual(helpers.pluginDataBool("false"), false);
assert(/showProviderName:\s+root\.showProviderName/.test(widget), "Widget passes it to the popout");
assert(/property bool\s+showProviderName:\s+true/.test(popout) && /showProviderName:\s+panel\.showProviderName/.test(popout),
       "PopoutPanel forwards it");
assert(/property bool showProviderName:\s+true/.test(row) && /showProviderName:\s+symbolRow\.showProviderName/.test(row),
       "SymbolRow forwards it");
assert(/providerAlias:\s+ProvidersManager\.aliasOf\(symbolData\.provider \|\| ProvidersManager\.defaultId\)/.test(row),
       "the alias comes from the symbol's provider (default provider for older symbols)");

// ── Rounded corners that follow the theme ────────────────────────────────────
const row2 = readSource("QML/Views/SymbolRow.qml");
assert(/property real\s+cornerRadius:\s+0/.test(chart), "the chart takes a radius (square by default)");
assert(/function _cornerInset\(x\)/.test(chart) && /_cornerInset\(centre\)/.test(chart) && /_cornerInset\(points\[j\]\.x\)/.test(chart), "fill and line are kept inside the corner arcs by the drawing itself (a canvas clip is not reliable; the pixels are checked in PriceChartCorners.test.qml)");
assert(!/\.clip\(\)|destination-out|QtQuick\.Effects/.test(chart), "no clip path, composite trick or effect that a renderer may ignore");
assert(/onCornerRadiusChanged:\s+requestPaint\(\)/.test(chart), "repainted when the radius changes");
assert(/cornerRadius:\s+Math\.max\(0, Theme\.cornerRadius - constants\.chartAreaMargin\)/.test(row2), "the radius is the theme's, concentric with the card");

console.log("PriceChart tests passed");
