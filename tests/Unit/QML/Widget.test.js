const { assert, same, loadShared, readSource, compileFunction, compileFunctions } = require("../../Helpers/Loader");

const entry = readSource("QML/Widget.qml");
const controller = readSource("QML/Helpers/WidgetController.qml");
const widget = [entry, controller].join("\n").replace(/^\s*\/\/.*$/gm, "");
const { errorMap } = loadShared();

// ── DMS toast wiring ─────────────────────────────────────────────────────────
assert(
    /function _configureErrorHandler\(\) \{[\s\S]*?ErrorHandler\.configure\(\{[\s\S]*?ToastService\.showError\("Markets: " \+ message, details, "", category\)/.test(
        widget
    ),
    "uses DMS's ToastService (message, details, category)"
);
assert(/readonly property bool _errorHandlerReady: _configureErrorHandler\(\)/.test(widget));
assert(
    widget.indexOf("_errorHandlerReady") < widget.indexOf("property var symbols:"),
    "configured before the symbol list is read"
);
assert(
    /Logger\.configure\(\{\s*devMode:\s*constants\.devMode\s*\}\)/.test(widget),
    "dev mode is handed to the Logger once"
);
assert(
    !/credentialErrorCooldown|onCredentialError|credentialError\(/.test(widget),
    "credential toasts now go through ErrorHandler (with its own rate limit)"
);

// ── Per-symbol errors ────────────────────────────────────────────────────────
const record = (code, text) => ({ code, userMessage: text, details: "d" });
function errorState(initial = {}) {
    const setSymbolError = compileFunction(widget, "_setSymbolError", {
        symbolErrors: initial,
        SymbolErrors: errorMap
    });
    return {
        set: (...callArguments) => setSymbolError(...callArguments),
        get: () => setSymbolError.context.symbolErrors
    };
}
{
    const state = errorState();
    state.set("u1", "price", record("network", "Can't reach Wise."));
    same(state.get(), { u1: { price: record("network", "Can't reach Wise.") } });
    state.set("u1", "graph", record("noData", "Wise has no chart data for this symbol."));
    assert.strictEqual(state.get().u1.price.userMessage, "Can't reach Wise.", "the other pull's error is kept");
    assert.strictEqual(state.get().u1.graph.code, "noData");
    state.set("u2", "price", record("notFound", "Nope."));
    assert.deepStrictEqual(Object.keys(state.get()).sort(), ["u1", "u2"]);
    state.set("u1", "price", null);
    assert.strictEqual(state.get().u1.price, undefined, "a success clears that pull's error");
    assert.strictEqual(state.get().u1.graph.code, "noData", "...and only that one");
    state.set("u1", "graph", null);
    assert.strictEqual("u1" in state.get(), false, "no errors left: the symbol is clean again");
    const before = state.get();
    state.set("zz", "price", null);
    assert.strictEqual(state.get(), before, "clearing a non-existent error changes nothing (no needless re-render)");
    // A new object each time, so QML bindings notice the change.
    const snapshot = state.get();
    state.set("u3", "price", record("http", "x"));
    assert.notStrictEqual(state.get(), snapshot);
    assert.strictEqual("u3" in snapshot, false, "previous maps are never mutated");
}
assert(
    /Connections\s*\{(?=[\s\S]*?target: fetcher)[\s\S]*?function onSymbolErrorChanged\(uid, fetchType, record\)\s*\{\s*root\._setSymbolError\(uid, fetchType, record\)/.test(
        widget
    )
);
assert(/symbolErrors:\s+root\.symbolErrors/.test(widget), "passed to the popup");

// ── Reading the saved symbols: the storage's job (see DataStorage.test.js) ───
assert(
    /property var symbols: dataStorage\.readCurrentSymbols\(pluginData\.symbols\)/.test(widget),
    "damaged data is handled by the storage, not here"
);
assert(
    !/_readSymbols|symbolsBackup|catch \(e\) \{\s*return \[\]/.test(widget),
    "no ad-hoc parsing, backup or swallowing in the widget"
);
assert(
    widget.indexOf("_errorHandlerReady") < widget.indexOf("DataStorage {"),
    "errors are configured before the storage can report any"
);

// ── Startup order ────────────────────────────────────────────────────────────
assert(
    /ProvidersManager\.loadErrors[\s\S]*?ErrorHandler\.handle\("providers"/.test(widget),
    "providers that failed to load are reported"
);
assert(
    widget.indexOf("ProvidersManager.loadErrors") <
        widget.lastIndexOf("dataStorage.migrateSavedSymbols(pluginData.symbols)"),
    "load errors are reported first"
);
const startup = /function initialize\(\) \{([\s\S]*?)\n    \}\n/.exec(controller)[1];
assert(!/JSON\.parse/.test(startup) && !/\btry\b/.test(startup), "no ad-hoc parsing or swallowing at startup");

// ── Saved market data: shown first, saved after ──────────────────────────────
assert(
    /_restoreThen\(ready, function\s*\(\) \{\s*fetcher\.startInitialFetches\(ready\);?\s*\}\)/.test(widget),
    "the first fetch waits for the saved data to be shown"
);
assert.strictEqual(
    (widget.match(/fetcher\.startInitialFetches\(/g) || []).length,
    1,
    "there is no other way to start the first fetch"
);
assert(
    /_restoreThen\([\s\S]*?function\s*\(\) \{\s*fetcher\.fetchNewSymbols\(root\.symbols, previousIds\);?\s*\}\)/.test(
        widget
    ),
    "new symbols show their saved data before they are fetched"
);
assert(
    /function onSymbolStored\(uid\) \{\s*cache\.markDirty\(uid\);?\s*\}/.test(widget),
    "new provider data is saved in the background"
);
assert(
    /lastFetchTimes: root\.refreshedTimes/.test(widget),
    "the popup shows when each symbol was last refreshed successfully, not when a fetch started"
);
assert(
    /fetcher\.forget\(symbol\.uid\);?\s*cache\.discard\(symbol\.uid\)\s*fetcher\.forceRefreshSymbol|fetcher\.forget\(symbol\.uid\);?\s*cache\.discard\(symbol\.uid\)[\s\S]*?fetcher\.forceRefreshSymbol/.test(
        widget
    ),
    "changed settings drop the shown and the saved data before the refresh"
);
assert(
    widget.indexOf("MarketCache {") > widget.indexOf("DataStorage {") &&
        !/pluginService|savePluginData/.test(/MarketCache \{[\s\S]*?\n    \}\n/.exec(widget)[0]),
    "the cache is its own service, not plugin data"
);

console.log("Widget tests passed");
