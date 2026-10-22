// Load QML JavaScript libraries under Node for development checks and tests, preserving shared module identities.
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const srcRoot = path.resolve(__dirname, "../src");

// Reuse imported base-class identities across modules, matching QML library imports.
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

module.exports = { createRegistry, loadModule };
