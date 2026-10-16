// Every provider's declared properties (plain data) pass the declaration check together with its API module,
// and declare what was measured against the real services.
const { assert, same, loadModule, loadShared, throwsWith } = require("../../../Helpers/Loader");

const shared = loadShared();
const rules = loadModule("JS/Helpers/ProviderRules.js", shared.registry);
const providers = {
    yahoo: { properties: loadModule("JS/Providers/Yahoo/YahooProperties.js", shared.registry), api: shared.yahoo },
    wise: { properties: loadModule("JS/Providers/Wise/WiseProperties.js", shared.registry), api: shared.wise },
    stooq: { properties: loadModule("JS/Providers/Stooq/StooqProperties.js", shared.registry), api: shared.stooq }
};
const limitsOf = (declared) => Object.fromEntries(Array.from(declared.chartLimits).map((limit) => [limit.resolution, limit.maxHistoryDays || 0]));

for (const [id, { properties, api }] of Object.entries(providers)) {
    const declared = properties.create();
    rules.assertDeclaration(id, declared, api);
    assert.strictEqual(declared.providerId, id);
    assert(Array.from(declared.priceResolutions).every((resolution) => shared.Resolution.isValid(resolution)), `${id}: price resolutions are valid`);
    assert(new RegExp(declared.symbolPattern).test(declared.symbolPlaceholder), `${id}: the placeholder is an accepted symbol`);
    throwsWith(() => rules.assertDeclaration(id, Object.assign({}, declared, { providerId: "other" }), api), "declares providerId", `${id}: the id must match`);
}

// Every provider has a three-letter capital alias (what charts show), and no two share one.
const expectedAliases = { yahoo: "YHF", wise: "WIS", stooq: "STK" };
const aliases = Object.entries(providers).map(([id, { properties }]) => properties.create().alias);
for (const [id, { properties, api }] of Object.entries(providers)) {
    const declared = properties.create();
    assert.strictEqual(declared.alias, expectedAliases[id], `${id}: alias`);
    assert(/^[A-Z]{3}$/.test(declared.alias), `${id}: exactly three capital letters`);
    for (const bad of [undefined, "", "yhf", "YH", "YHFX", "Y1F", "YH ", 5, null])
        throwsWith(() => rules.assertDeclaration(id, Object.assign({}, declared, { alias: bad }), api), "alias", `${id}: alias ${String(bad)} is refused`);
}
assert.strictEqual(new Set(aliases).size, aliases.length, "aliases are unique");

// Yahoo: limits measured against the live chart API; polled as often as every minute.
const yahoo = providers.yahoo.properties.create();
same(yahoo.minPullResolution, "1m");
same(Array.from(yahoo.priceResolutions), ["1m", "5m", "15m", "1h", "1d", "1w", "1M"]);
same(limitsOf(yahoo), { "1m": 7, "5m": 60, "15m": 60, "1h": 730, "1d": 0, "1w": 0, "1M": 0 });
assert(!yahoo.requiresCredential && !yahoo.disabled);

// Wise: only hourly and daily rates exist.
const wise = providers.wise.properties.create();
same(Array.from(wise.priceResolutions), ["1h", "1d"]);
same(wise.minPullResolution, "1h");
same(limitsOf(wise), { "1h": 30, "1d": 1826 });

// Stooq: disabled, needs a credential.
const stooq = providers.stooq.properties.create();
assert(stooq.disabled && stooq.requiresCredential && stooq.credentialSettingKey);

console.log("Provider properties tests passed");

// Enabled declarations must be internally usable before a handler is created.
{
    const declared = providers.wise.properties.create();
    for (const changed of [
        { priceResolutions: ["1h", "1h"] },
        { changeResolutions: ["1d", "1d"] },
        { minPullResolution: "1d" },
        { chartLimits: [{ resolution: "1h", maxHistoryDays: Infinity }] },
        { chartLimits: [{ resolution: "1m", maxHistoryDays: 1 }] }
    ]) assert.throws(() => rules.assertDeclaration("wise", Object.assign({}, declared, changed), providers.wise.api),
                     (error) => error.code === "providerConfig", JSON.stringify(changed));
}
