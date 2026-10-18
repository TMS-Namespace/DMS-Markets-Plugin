// Test helpers: a minimal emulation of QML's `.import "x.js" as Alias` for plain
// Node. Every module runs in its own vm context and imports resolve (relative to
// the importing file) to the other module's context. Modules are cached per
// registry, so `.pragma library` singletons (ProviderInterface) are shared.

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const repoRoot = path.resolve(__dirname, "..", "..");
const srcRoot = path.join(repoRoot, "src");

function createRegistry() {
    return new Map();
}

// `relativePath` is relative to src/, e.g. "JS/Contracts/Resolution.js".
function loadModule(relativePath, registry) {
    const filePath = path.resolve(srcRoot, relativePath);
    if (registry.has(filePath)) return registry.get(filePath);
    const context = {
        console,
        Object,
        JSON,
        Math,
        Date,
        Array,
        Number,
        String,
        Error,
        parseInt,
        parseFloat,
        isNaN,
        isFinite,
        encodeURIComponent
    };
    vm.createContext(context);
    registry.set(filePath, context);
    const source = fs
        .readFileSync(filePath, "utf8")
        .replace(/^\s*\.pragma\s+library\s*$/gm, "")
        .replace(/^\s*\.import\s+"([^"]+)"\s+as\s+(\w+)\s*$/gm, (_fullMatch, importPath, alias) => {
            const dependency = path.relative(srcRoot, path.resolve(path.dirname(filePath), importPath));
            context[alias] = loadModule(dependency, registry);
            return "";
        });
    vm.runInContext(source, context, { filename: relativePath });
    return context;
}

// Every pure-JS module a test may want, loaded into ONE registry so they share state and identity
// (e.g. a PluginError from PluginError.js is an instance for every module that imports it).
function loadShared() {
    const registry = createRegistry();
    const VALUE_DOMAINS = ["Resolution.js", "ChartSpan.js", "FetchType.js", "PluginError.js", "TimeUnits.js"]; // src/JS/Contracts; the rest is src/JS/Helpers
    const load = (file) => loadModule(`JS/${VALUE_DOMAINS.includes(file) ? "Contracts" : "Helpers"}/${file}`, registry);
    return {
        registry,
        Resolution: load("Resolution.js"),
        ChartSpan: load("ChartSpan.js"),
        FetchType: load("FetchType.js"),
        errors: load("PluginError.js"),
        constants: load("Constants.js"),
        chartRules: load("ChartRules.js"),
        helpers: load("Helpers.js"),
        series: load("SeriesRules.js"),
        price: load("PriceRules.js"),
        interpreter: load("ResponseInterpreter.js"),
        policy: load("SelectionPolicy.js"),
        symbolRules: load("SymbolRules.js"),
        migration: load("SymbolMigration.js"),
        errorMap: load("SymbolErrorMap.js"),
        errorPolicy: load("ErrorPolicy.js"),
        fetchCommand: load("FetchCommand.js"),
        // The provider API modules (pure JS: URL building and parsing per provider).
        yahoo: loadModule("JS/Providers/Yahoo/YahooApi.js", registry),
        wise: loadModule("JS/Providers/Wise/WiseApi.js", registry),
        stooq: loadModule("JS/Providers/Stooq/StooqApi.js", registry),
        yahooConstants: loadModule("JS/Providers/Yahoo/YahooConstants.js", registry),
        wiseConstants: loadModule("JS/Providers/Wise/WiseConstants.js", registry),
        stooqConstants: loadModule("JS/Providers/Stooq/StooqConstants.js", registry)
    };
}

function throwsWith(action, fragment, message) {
    assert.throws(
        action,
        (error) => {
            assert(
                String(error.message).includes(fragment),
                `${message}: expected "${fragment}" in "${error.message}"`
            );
            return true;
        },
        message
    );
}

function readSource(relativePath) {
    return fs.readFileSync(path.join(srcRoot, relativePath), "utf8");
}

// Recursively lists files under `dir` (absolute) whose name matches `pattern`.
function listFiles(dir, pattern) {
    return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) return listFiles(full, pattern);
        return pattern.test(entry.name) ? [full] : [];
    });
}

// Compare by value across vm realms (array/object prototypes differ between contexts).
function same(actual, expected, message) {
    assert.strictEqual(JSON.stringify(actual), JSON.stringify(expected), message);
}

// Returns the source of `function name(...) { ... }` from QML/JS text (brace matched).
function extractFunction(source, name) {
    const start = source.search(new RegExp(`function\\s+${name}\\s*\\(`));
    assert(start !== -1, `function ${name} not found`);
    const open = source.indexOf("{", source.indexOf(")", start));
    let depth = 0;
    for (let i = open; i < source.length; i++) {
        if (source[i] === "{") depth++;
        else if (source[i] === "}" && --depth === 0) return source.slice(start, i + 1);
    }
    throw new Error(`unbalanced braces in ${name}`);
}

// Evaluates an extracted QML function with stubbed globals and returns it.
function compileFunction(source, name, globals) {
    const context = vm.createContext({ console, Date, Math, JSON, Object, Array, isNaN, ...globals });
    vm.runInContext(extractFunction(source, name), context);
    const compiled = context[name];
    compiled.context = context; // lets tests read globals the function assigns (e.g. QML properties)
    return compiled;
}

// Compiles several functions of one QML file into ONE context so they can call each
// other (like members of a QML item). Returns the context; call `context.fn(...)`.
function compileFunctions(source, names, globals) {
    const context = vm.createContext({ console, Date, Math, JSON, Object, Array, isNaN, isFinite, ...globals });
    for (const name of names) vm.runInContext(extractFunction(source, name), context);
    return context;
}

module.exports = {
    compileFunctions,
    extractFunction,
    compileFunction,
    same,
    listFiles,
    assert,
    repoRoot,
    srcRoot,
    createRegistry,
    loadModule,
    loadShared,
    throwsWith,
    readSource
};
