const { assert, same, loadProviders, readSource, compileFunction } = require("../../../Helpers/Loader");

const manager = readSource("QML/Helpers/SymbolManager.qml");
const widget = readSource("QML/Widget.qml");

// The manager names the actions; persistence is DataStorage's job.
assert(/property var\s+storage:\s+null/.test(manager), "it is given the widget's DataStorage");
assert(!/pluginService|savePluginData|pluginId/.test(manager), "it never touches plugin data itself");
assert(!/JSON\./.test(manager), "...nor serialises anything");
assert(!/Providers|ErrorHandler|PluginError/.test(manager.replace(/\/\/.*$/gm, "").replace(/Logger\.debug\([^\n]*\)/g, "")), "no provider or error handling concerns either (only dev-mode log lines)");
assert(!/console\./.test(manager), "dev-mode messages go through Logger.debug");

// togglePin / removeSymbol hand the CURRENT list and the uid to the storage and return its result.
{
    const calls = [];
    const symbols = [{ uid: "a", ticker: "SAME" }, { uid: "b", ticker: "SAME" }];
    const storage = {
        togglePin: (list, uid) => { calls.push(["pin", list, uid]); return true; },
        removeSymbol: (list, uid) => { calls.push(["remove", list, uid]); return false; }
    };
    const toggle = compileFunction(manager, "togglePin", { storage, symbols, constants: { devMode: false }, Logger: { debug: () => {} }, console });
    assert.strictEqual(toggle("b"), true);
    const remove = compileFunction(manager, "removeSymbol", { storage, symbols, constants: { devMode: false }, Logger: { debug: () => {} }, console });
    assert.strictEqual(remove("a"), false, "the storage's verdict is passed on");
    same(calls.map((call) => [call[0], call[2]]), [["pin", "b"], ["remove", "a"]], "by uid (the ticker is not unique)");
    assert(calls.every((call) => call[1] === symbols), "the live list is what gets edited");
}
// The bar text reads prices by uid.
assert(manager.includes("priceData[symbol.uid]"), "bar text reads prices by uid");
assert(!/\.id\b/.test(manager.replace(/\/\/.*$/gm, "")), "no ticker-keyed lookups remain");
assert(/storage:\s+storage/.test(widget), "the widget gives it the storage");

// ── Widget wiring around the storage ─────────────────────────────────────────
assert(/DataStorage \{\s*id: storage\s*pluginId:\s+root\.pluginId\s*pluginService:\s+root\.pluginService/.test(widget));
assert(/property var symbols: storage\.readCurrentSymbols\(pluginData\.symbols\)/.test(widget), "saved symbols are read (and damaged data handled) by the storage");
assert(/property var providerCredentials: storage\.readCredentials\(pluginData\)/.test(widget), "credentials come from the storage");
assert(/storage\.migrateSavedSymbols\(pluginData\.symbols\)/.test(widget), "migration is the storage's");
assert(/storage\.migrateSettings\(pluginData\)/.test(widget));
assert(widget.indexOf("storage.migrateSavedSymbols(pluginData.symbols)") < widget.indexOf("fetcher.startInitialFetches(ready)"), "migration happens before the first fetches");
assert(/symbols\.filter\(function\(symbol\) \{ return !!symbol\.uid \}\)/.test(widget) && !/migrationPending/.test(widget), "startup never waits for the migrated list to arrive: it starts the symbols that already have a uid (the behaviour is tested in Integration/QML/Widget.test.qml)");
assert(/\.uid\b/.test(widget) && !/symbol\.id\b|\bsym\.id\b|\.map\(function\(s\) \{ return s\.id \}\)/.test(widget), "widget tracks symbols by uid");
assert(/showPriceChange:\s+storage\.readShowPriceChange\(pluginData\)/.test(widget) && !/showPriceRange/.test(widget), "the old showPriceRange value is the storage's business");
assert(!/savePluginData|JSON\.parse/.test(widget), "the widget no longer touches storage directly");

console.log("SymbolManager tests passed");
