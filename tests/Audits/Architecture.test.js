// Static audit of the architecture rules:
//   QML defines what exists, how things are connected and how they react; JavaScript calculates and
//   decides (reusable .js); contracts are QML data holders; legacy formats live in ONE module.
const fs = require("fs");
const path = require("path");
const { assert, srcRoot, listFiles } = require("../Helpers/Loader");

const relativePath = (file) => path.relative(srcRoot, file);
const strip = (text) =>
    text
        .replace(/\/\*[\s\S]*?\*\//g, "")
        .replace(/^\s*\/\/.*$/gm, "")
        .replace(/\s\/\/.*$/gm, "");
const read = (file) => fs.readFileSync(file, "utf8");
const qmlFiles = listFiles(srcRoot, /\.qml$/);
const jsFiles = listFiles(srcRoot, /\.js$/);

// ── 1. Contracts are QML data holders ────────────────────────────────────────
const contractFiles = listFiles(path.join(srcRoot, "QML/Contracts"), /\.qml$/);
assert(contractFiles.length >= 8, "the contracts exist as QML types");
// JS/Contracts holds only value domains (frozen enums with isValid/label) and the exception type; the data holders are QML.
const jsContracts = fs.readdirSync(path.join(srcRoot, "JS/Contracts")).sort();
assert.deepStrictEqual(
    jsContracts,
    ["ChartSpan.js", "FetchType.js", "PluginError.js", "Resolution.js", "TimeUnits.js"],
    "JS/Contracts holds only value domains"
);
assert(!fs.existsSync(path.join(srcRoot, "JS/Shared")), "JS/Shared is split into JS/Contracts and JS/Helpers");
const ALLOWED_CONTRACT_IMPORTS = ["Resolution.js", "ChartSpan.js", "FetchType.js", "Helpers.js"]; // shallow per-field checks only
for (const file of contractFiles) {
    const text = read(file);
    const code = strip(text);
    assert(/^import QtQml\s*$/m.test(code), `${relativePath(file)}: a plain QtObject`);
    assert(/\nQtObject \{/.test(`\n${code}`), `${relativePath(file)}: root is a QtObject`);
    assert.strictEqual((code.match(/^QtObject \{/gm) || []).length, 1, `${relativePath(file)}: one contract per file`);
    for (const match of code.matchAll(/import "([^"]+\.js)"/g))
        assert(
            ALLOWED_CONTRACT_IMPORTS.some((allowedImport) => match[1].endsWith("/" + allowedImport)),
            `${relativePath(file)}: contracts only use value-domain checks, not ${match[1]}`
        );
    const functions = [...code.matchAll(/function\s+(\w+)/g)].map((match) => match[1]);
    assert(
        functions.length === 0,
        `${relativePath(file)}: contracts hold data; no logic functions (${functions.join(", ")})`
    );
    assert(
        !/\b(for|while)\s*\(|JSON\.|\.parse\(|\.map\(|\.filter\(|\.reduce\(|\.split\(/.test(code),
        `${relativePath(file)}: no parsing or cross-field logic in a contract`
    );
    assert(
        !/readonly property bool valid\s*:/.test(code),
        `${relativePath(file)}: aggregate validity belongs in a logic module`
    );
    // Validity flags are per field: each reads exactly one property.
    for (const match of code.matchAll(/readonly property bool (\w+Valid):\s*([^\n]+)/g))
        assert(!/&&|\|\|/.test(match[2]), `${relativePath(file)}: ${match[1]} must check a single field`);
}

// ── 2. Legacy formats are SymbolMigration's business, nowhere else ───────────
const LEGACY =
    /priceInterval|graphInterval|graphResolution|LEGACY_RANGES|LEGACY_RESOLUTION|LEGACY_FIELDS|\bsymbol\.id\b/;
for (const file of [...jsFiles, ...qmlFiles]) {
    const code = strip(read(file));
    if (relativePath(file) === "JS/Helpers/SymbolMigration.js") continue;
    assert(
        !LEGACY.test(code),
        `${relativePath(file)}: legacy saved-symbol formats may only appear in SymbolMigration.js`
    );
}
// The renamed setting is legacy data too, handled in the storage layer only.
for (const file of [...jsFiles, ...qmlFiles]) {
    const code = strip(read(file));
    if (/STORAGE_LEGACY_SHOW_PRICE_RANGE_KEY|showPriceRange/.test(code))
        assert(
            ["JS/Helpers/Constants.js", "JS/Helpers/SymbolMigration.js"].includes(relativePath(file)),
            `${relativePath(file)}: legacy settings are handled by DataStorage only`
        );
}

// ── 3. Providers: two JS modules in their own folder; nothing else ──────────
//    <Name>Properties.js (declared data), <Name>Api.js (requests and answers), <Name>Constants.js.
const providerDirs = fs
    .readdirSync(path.join(srcRoot, "JS/Providers"), { withFileTypes: true })
    .filter((directoryEntry) => directoryEntry.isDirectory())
    .map((directoryEntry) => directoryEntry.name);
assert(providerDirs.length >= 3, "providers found");
const providerFiles = [];
for (const name of providerDirs) {
    for (const suffix of ["Properties", "Api", "Constants"]) {
        const file = path.join(srcRoot, "JS/Providers", name, `${name}${suffix}.js`);
        assert(fs.existsSync(file), `${name}: ${name}${suffix}.js exists in the provider's folder`);
        providerFiles.push(file);
    }
    const props = strip(read(path.join(srcRoot, "JS/Providers", name, `${name}Properties.js`)));
    assert(
        /function create\(\)/.test(props) &&
            /providerId:/.test(props) &&
            /priceResolutions:/.test(props) &&
            /chartLimits:/.test(props),
        `${name}Properties.js declares the provider as plain data`
    );
    assert(!/\bfunction\s+(?!create\b)\w+/.test(props), `${name}Properties.js holds data only (no logic)`);
    const api = read(path.join(srcRoot, "JS/Providers", name, `${name}Api.js`));
    for (const functionName of ["priceUrl", "historyUrl", "parsePrice", "parseHistory", "pageUrl"])
        assert(new RegExp(`function ${functionName}\\(`).test(api), `${name}Api.js provides ${functionName}`);
}
assert(
    !fs.existsSync(path.join(srcRoot, "QML/Providers")) &&
        !fs
            .readdirSync(path.join(srcRoot, "QML/Services"))
            .some((fileName) => /^(Yahoo|Wise|Stooq)Provider\.qml$|ProviderBase/.test(fileName)),
    "no QML wrapper types per provider: the manager uses the JS modules directly"
);
for (const file of providerFiles) {
    const code = strip(read(file));
    for (const forbidden of [
        "SymbolMigration",
        "SelectionPolicy",
        "DataStorage",
        "ProvidersManager",
        "ProviderHandler",
        "ErrorHandler",
        "SymbolRules",
        "pluginService",
        "ToastService"
    ])
        assert(!code.includes(forbidden), `${relativePath(file)}: a provider must not know ${forbidden}`);
}

// ── 3b. All queries to a provider's JS go through its ProviderHandler ────────
//    Only ProvidersManager imports the provider modules (to start them); only ProviderHandler calls their API.
for (const file of qmlFiles) {
    const code = strip(read(file));
    if (relativePath(file) !== "QML/Services/ProvidersManager.qml")
        assert(
            !/JS\/Providers\//.test(code),
            `${relativePath(file)}: provider JS modules are imported by ProvidersManager only`
        );
    if (relativePath(file) !== "QML/Services/ProviderHandler.qml")
        assert(
            !/\bapi\.(priceUrl|historyUrl|parsePrice|parseHistory|pageUrl|extractApiError|fetchScript)\b|Api\.\w+\(/.test(
                code
            ),
            `${relativePath(file)}: provider APIs are called by ProviderHandler only`
        );
}
for (const jsFile of jsFiles.filter((jsFile) => !/JS\/Providers\//.test(jsFile.replace(/\\/g, "/"))))
    assert(
        !/Providers\/\w+\/\w+(Api|Properties)\.js/.test(strip(read(jsFile))),
        `${relativePath(jsFile)}: logic modules never import a provider`
    );
// The supported providers are one enum; the manager maps each to its modules and hands out handlers.
const providerType = read(path.join(srcRoot, "QML/Contracts/ProviderType.qml"));
assert(
    /enum Type \{[^}]*\bYahoo\b[^}]*\bWise\b[^}]*\}/.test(providerType),
    "ProviderType lists the supported providers"
);
const manager = strip(read(path.join(srcRoot, "QML/Services/ProvidersManager.qml")));
assert(
    !/SymbolMigration|migrateSymbols/.test(manager),
    "saved-format migration belongs to storage, not the provider manager"
);
for (const name of providerDirs)
    assert(
        new RegExp(`ProviderType\\.${name}\\b`).test(manager),
        `ProvidersManager starts ${name} by its ProviderType`
    );
assert(!/Catalog/.test(qmlFiles.map(read).join("")), "the old ProviderCatalog is gone");

// ── 4. The logic layer is pure: plain data in, plain data out ────────────────
for (const file of jsFiles) {
    const code = strip(read(file));
    assert(
        !/\bQt\.|Quickshell|ToastService|import QtQuick|\.qml"/.test(code),
        `${relativePath(file)}: JS modules do not touch QML or the UI`
    );
    // UI is QML only: no widgets, layout, colours or fonts in JavaScript (shell script text inside a string is not code).
    assert(
        !/\b(Theme|StyledText|DankIcon|Rectangle|MouseArea|Canvas|Column|Row)\b|\banchors\b|\bpixelSize\b|\bQt\.rgba|\bfont\.\w+/.test(
            code.replace(/"(?:[^"\\]|\\.)*"/g, '""')
        ),
        `${relativePath(file)}: UI belongs in QML, not JavaScript`
    );
    // PluginError is the one JS class left: an exception type has to be a JS Error to be thrown.
    if (relativePath(file) === "JS/Contracts/PluginError.js") continue;
    assert(
        !/\bNAME\s*=\s*"|\bfunction is[A-Z]\w+\(value\)\s*\{\s*return !!value && value instanceof/.test(code),
        `${relativePath(file)}: JS contract objects are gone (contracts are QML types)`
    );
}

// ── 5. Singletons are QML (shared state), the rest connects and reacts ───────
for (const [dir, name] of [
    ["QML/Services", "ProvidersManager"],
    ["QML/Services", "ErrorHandler"]
]) {
    const qmldir = read(path.join(srcRoot, dir, "qmldir"));
    assert(
        new RegExp(`^singleton ${name} 1\\.0 ${name}\\.qml$`, "m").test(qmldir),
        `${name} is a registered singleton`
    );
    assert(
        /^pragma Singleton$/m.test(read(path.join(srcRoot, dir, `${name}.qml`))),
        `${name}.qml declares pragma Singleton`
    );
}
assert(
    !fs.existsSync(path.join(srcRoot, "JS/Helpers/ProviderInterface.js")) &&
        !fs.existsSync(path.join(srcRoot, "JS/Helpers/ErrorHandler.js")),
    "the stateful JS singletons moved to QML"
);

// ── 5b. Saved data: reading, parsing and writing it is DataStorage's (QML) ─────
for (const file of qmlFiles) {
    if (["QML/Services/DataStorage.qml", "QML/Services/MarketCache.qml"].includes(relativePath(file))) continue; // the two services that own saved data
    assert(
        !/JSON\.(parse|stringify)|savePluginData|loadPluginData/.test(strip(read(file))),
        `${relativePath(file)}: saved data is read and written by DataStorage (settings, symbols) and MarketCache (market data) only`
    );
}
for (const file of jsFiles.filter((f) => !/JS\/Providers\//.test(f.replace(/\\/g, "/"))))
    assert(
        !/savePluginData|loadPluginData/.test(strip(read(file))),
        `${relativePath(file)}: JS never reads or writes plugin data`
    );

// ── 6. JavaScript stays small ────────────────────────────────────────────────
const jsLines = jsFiles.reduce(
    (total, file) =>
        total +
        strip(read(file))
            .split("\n")
            .filter((line) => line.trim() !== "").length,
    0
);
const qmlLines = qmlFiles.reduce(
    (total, file) =>
        total +
        strip(read(file))
            .split("\n")
            .filter((line) => line.trim() !== "").length,
    0
);
assert(
    // The former 1550-line budget rebased for Prettier layout; application JS behavior is unchanged.
    jsLines <= 2160,
    `JS must stay small (${jsLines} code lines; QML has ${qmlLines}): move declarations and wiring to QML before adding JS`
);
assert(qmlLines > jsLines, "QML carries more of the code than JS");

console.log(`Architecture audit passed (JS ${jsLines} code lines, QML ${qmlLines})`);
