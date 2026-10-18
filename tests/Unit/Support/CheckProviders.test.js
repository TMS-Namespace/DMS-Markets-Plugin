// Provider contract checks must reject broken contributions before any QML runtime or network work starts.
const { assert, createRegistry, loadModule } = require("../../Helpers/Loader");
const { assertProvider, checkProviders } = require("../../../support/CheckProviders");

// Each fixture has fresh class identities and instances, just like an isolated contributor check.
function fixture() {
    const registry = createRegistry();
    return {
        registry,
        api: loadModule("JS/Providers/Wise/WiseApi.js", registry).create(),
        properties: loadModule("JS/Providers/Wise/WiseProperties.js", registry).create()
    };
}

// Mutate an actual inherited provider to make sure the checker diagnoses the concrete contract violation.
function rejects(change, expected) {
    const current = fixture();
    change(current);
    assert.throws(() => assertProvider("Wise", current.api, current.properties, current.registry), expected);
}

assert.deepStrictEqual(checkProviders(), ["Stooq", "Wise", "Yahoo"]);
rejects((current) => {
    current.api = {};
}, /must extend ProviderApi/);
rejects((current) => {
    current.properties = { ...current.properties };
}, /must extend ProviderProperties/);
rejects((current) => {
    current.api.priceUrl = undefined;
}, /must override priceUrl/);
rejects((current) => {
    current.api = new (loadModule("JS/Contracts/ProviderApi.js", current.registry).ProviderApi)();
}, /must override priceUrl/);
rejects((current) => {
    current.api.historyUrl = function (symbol) {
        return symbol;
    };
}, /historyUrl.*parameters/);
rejects((current) => {
    current.api.fetchScript = 1;
}, /optional hook fetchScript/);
rejects((current) => {
    current.properties.symbolPatern = "typo";
}, /unknown property 'symbolPatern'/);
rejects((current) => {
    current.properties.disabled = "false";
}, /'disabled' must be bool/);
rejects((current) => {
    current.properties.symbolMaxLength = 2.5;
}, /'symbolMaxLength' must be int/);
rejects((current) => {
    current.properties.priceResolutions = "1h";
}, /'priceResolutions' must be an array/);
rejects((current) => {
    delete current.properties.symbolPattern;
}, /missing property 'symbolPattern'/);
rejects((current) => {
    current.properties.symbolPattern = "^.+$";
}, /must not allow/);
rejects((current) => {
    current.properties.chartLimits = [{ resolution: "1h", maxHistoryDays: Infinity }];
}, /must be a number/);

const current = fixture();
assert.strictEqual(current.api.fetchScript(10), "", "anonymous providers inherit the common fetch path");
assert.notStrictEqual(
    current.api.priceUrl,
    loadModule("JS/Contracts/ProviderApi.js", current.registry).ProviderApi.prototype.priceUrl
);
console.log("Provider development checks passed");
