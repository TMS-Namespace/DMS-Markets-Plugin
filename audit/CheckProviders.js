// Check inherited provider contracts during development without starting QML or contacting external services.
const fs = require("fs");
const path = require("path");
const { createRegistry, loadModule } = require("./QmlJavaScript");
const sourceRoot = path.resolve(__dirname, "../src");

// Read the typed QML surface so properties cannot drift between the JavaScript base and QML.
function propertySchema() {
    const source = fs.readFileSync(path.join(sourceRoot, "QML/Contracts/ProviderProperties.qml"), "utf8");
    return Object.fromEntries([...source.matchAll(/^\s+property (\w+) (\w+):/gm)].map((match) => [match[2], match[1]]));
}

// Reject incomplete subclasses, incompatible method signatures, and properties QML would otherwise coerce.
function assertProvider(name, api, properties, registry = createRegistry()) {
    const apiContract = loadModule("JS/Contracts/ProviderApi.js", registry);
    const propertiesContract = loadModule("JS/Contracts/ProviderProperties.js", registry);
    const fail = (detail) => {
        throw new Error(`${name}: ${detail}`);
    };
    if (!(api instanceof apiContract.ProviderApi)) fail("API must extend ProviderApi");
    if (!(properties instanceof propertiesContract.ProviderProperties))
        fail("properties must extend ProviderProperties");
    for (const method of apiContract.RequiredMethods) {
        const baseMethod = apiContract.ProviderApi.prototype[method];
        if (typeof api[method] !== "function" || api[method] === baseMethod) fail(`API must override ${method}`);
        // Anonymous providers may omit the final credential parameter from URL methods.
        const minimum = method.endsWith("Url") && method !== "pageUrl" ? baseMethod.length - 1 : baseMethod.length;
        if (api[method].length < minimum || api[method].length > baseMethod.length)
            fail(`${method} has ${api[method].length} parameters; expected ${minimum}..${baseMethod.length}`);
    }
    for (const method of apiContract.OptionalMethods)
        if (
            typeof api[method] !== "function" ||
            api[method].length !== apiContract.ProviderApi.prototype[method].length
        )
            fail(`optional hook ${method} has an incompatible signature`);
    const schema = propertySchema();
    const defaults = new propertiesContract.ProviderProperties();
    if (JSON.stringify(Object.keys(defaults).sort()) !== JSON.stringify(Object.keys(schema).sort()))
        fail("ProviderProperties base fields do not match the QML contract");
    for (const field of Object.keys(properties)) {
        const type = schema[field],
            value = properties[field];
        if (!type) fail(`unknown property '${field}'`);
        const valid =
            type === "string"
                ? typeof value === "string"
                : type === "bool"
                  ? typeof value === "boolean"
                  : type === "int"
                    ? Number.isInteger(value)
                    : type === "var" && Array.isArray(defaults[field]) && Array.isArray(value);
        if (!valid) fail(`property '${field}' must be ${type === "var" ? "an array" : type}`);
    }
    for (const field of Object.keys(schema))
        if (!Object.prototype.hasOwnProperty.call(properties, field)) fail(`missing property '${field}'`);
    loadModule("JS/Helpers/ProviderRules.js", registry).assertDeclaration(properties.providerId, properties, api);
}

// Discover every provider folder, including new contributors' providers before they are registered in QML.
function checkProviders() {
    const directory = path.join(sourceRoot, "JS/Providers"),
        registry = createRegistry();
    const names = fs
        .readdirSync(directory, { withFileTypes: true })
        .filter((entry) => entry.isDirectory())
        .map((entry) => entry.name)
        .sort();
    for (const name of names) {
        const api = loadModule(`JS/Providers/${name}/${name}Api.js`, registry).create();
        const properties = loadModule(`JS/Providers/${name}/${name}Properties.js`, registry).create();
        assertProvider(name, api, properties, registry);
    }
    return names;
}

module.exports = { assertProvider, checkProviders };
if (require.main === module) {
    try {
        console.log(`Provider contracts: ${checkProviders().join(", ")}; all implementations conform.`);
    } catch (error) {
        console.error(error.message);
        process.exitCode = 1;
    }
}
