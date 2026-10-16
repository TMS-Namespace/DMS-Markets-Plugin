const { assert, same, readSource, loadShared } = require("../../../Helpers/Loader");

const chart = readSource("QML/Views/PriceChart.qml");
const row = readSource("QML/Views/SymbolRow.qml");
const popout = readSource("QML/Views/PopoutPanel.qml");
const widget = readSource("QML/Widget.qml");
const constants = readSource("QML/Helpers/Constants.qml");
const { helpers } = loadShared();

// ── The label: lower-left, like the range label is upper-left ────────────────
const block = /\/\/ ── Provider name label[\s\S]*?\n    StyledText \{([\s\S]*?)\n    \}/.exec(chart);
assert(block, "provider name label exists");
const label = block[1];
assert(/anchors\.left:\s+parent\.left/.test(label) && /anchors\.bottom:\s+parent\.bottom/.test(label), "anchored lower-left");
assert(/text:\s+chart\.providerName/.test(label), "shows the provider name");
assert(/chart\.showProviderName && chart\.providerName !== ""/.test(label), "hidden when disabled or unnamed");
assert(/processor\.closes\.length >= 2/.test(label), "only drawn with a chart, like the range label");
assert(/chartLabelLeftMargin/.test(label) && /chartLabelBottomMargin/.test(label), "uses the shared label margins");
assert(/chartLabelFontSizeDelta/.test(label) && /chartLabelOpacity/.test(label), "same style as the range label");
assert(/chartLabelBottomMargin:\s+\d+/.test(constants), "bottom margin constant defined");
assert(/property bool\s+showProviderName: true/.test(chart), "label defaults to on in the chart");
assert(/property string providerName:\s+""/.test(chart));

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
assert(/providerName:\s+ProvidersManager\.nameOf\(symbolData\.provider \|\| ProvidersManager\.defaultId\)/.test(row),
       "the name comes from the symbol's provider (default provider for older symbols)");

console.log("PriceChart tests passed");
