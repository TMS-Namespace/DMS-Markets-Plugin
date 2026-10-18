// Enforce documented functions, descriptive names, stateless JS modules and registered QML folders.
const fs = require("fs");
const path = require("path");
const { assert, srcRoot, listFiles } = require("../Helpers/Loader");
const files = listFiles(srcRoot, /\.(js|qml)$/);
const stripLiterals = (text) => text.replace(/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|\/\/[^\n]*|\/\*[\s\S]*?\*\//g, " ");
for (const file of files) {
    const text = fs.readFileSync(file, "utf8");
    const name = path.relative(srcRoot, file);
    assert(text.startsWith("//"), `${name}: start with a short description of the file's role`);
    assert(!text.includes("\u2014"), `${name}: use ordinary punctuation instead of em dashes`);
    const lines = text.split("\n");
    for (let index = 0; index < lines.length; index++) {
        if (/^\s*function \w+\(/.test(lines[index]))
            assert(index > 0 && /^\s*\/\//.test(lines[index - 1]), `${name}:${index + 1}: explain the function`);
    }
    const code = stripLiterals(text);
    assert(
        !/\b(?:var|let|const)\s+(?:c|s|k|r|e|sel|ctx|fn|btn|tmp)\b|\bcatch\s*\(\s*(?:e|err|ex)\s*\)/.test(code),
        `${name}: use descriptive variable and exception names`
    );
    assert(
        !/\bfunction\s*\(\s*(?:c|s|k|r|e|sel|ctx|fn|btn|tmp)\b/.test(code),
        `${name}: name callback arguments for what they contain`
    );
    if (file.endsWith(".js")) assert(/^\.pragma library$/m.test(text), `${name}: JS modules are stateless libraries`);
    if (file.endsWith(".qml"))
        assert(fs.existsSync(path.join(path.dirname(file), "qmldir")), `${name}: every QML folder has a qmldir`);
    for (const match of text.matchAll(/^\s*\.?import "([^"]+\.js)" as (\w+)/gm)) {
        const withoutImport = code.replace(new RegExp(`\\bas\\s+${match[2]}\\b`), "");
        assert(new RegExp(`\\b${match[2]}\\b`).test(withoutImport), `${name}: unused JS import ${match[2]}`);
    }
}
const helperSource = fs.readFileSync(path.join(srcRoot, "JS/Helpers/Helpers.js"), "utf8");
assert(
    !/function (?:obfuscate|deobfuscate)\(/.test(helperSource),
    "credential compatibility belongs in the migration module"
);
const storageSource = fs.readFileSync(path.join(srcRoot, "QML/Services/DataStorage.qml"), "utf8");
assert(!/function loadDraftField\(/.test(storageSource), "do not restore the obsolete draft-reading API");
const widgetSource = fs.readFileSync(path.join(srcRoot, "QML/Widget.qml"), "utf8");
assert(
    /property var symbols: dataStorage\.readCurrentSymbols\(pluginData\.symbols\)/.test(widgetSource),
    "only current-format symbols reach the widget"
);
console.log("Code requirements audit passed");
