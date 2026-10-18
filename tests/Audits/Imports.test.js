// Static checks over every QML/JS file: imports resolve, qmldir lists real files,
// and every `Alias.member` used in QML exists in the module the alias points to.
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const { assert, srcRoot, listFiles, loadModule, createRegistry } = require("../Helpers/Loader");

const qmlFiles = listFiles(srcRoot, /\.qml$/);
const jsFiles = listFiles(srcRoot, /\.js$/);
assert(qmlFiles.length > 10 && jsFiles.length > 10, "source files found under src/");
const registry = createRegistry();
const relativePath = (file) => path.relative(srcRoot, file);

// ── JS imports (".import "x.js" as Alias") resolve ────────────────────────────
for (const file of jsFiles)
    for (const match of fs.readFileSync(file, "utf8").matchAll(/^\s*\.import\s+"([^"]+)"\s+as\s+(\w+)/gm))
        assert(
            fs.existsSync(path.resolve(path.dirname(file), match[1])),
            `${relativePath(file)}: missing import ${match[1]}`
        );

// ── QML imports resolve (files or qmldir directories); aliases map to modules ─
for (const file of qmlFiles) {
    const text = fs.readFileSync(file, "utf8");
    const aliases = {};
    for (const match of text.matchAll(/^import\s+"([^"]+)"(?:\s+as\s+(\w+))?/gm)) {
        const target = path.resolve(path.dirname(file), match[1]);
        assert(fs.existsSync(target), `${relativePath(file)}: missing import ${match[1]}`);
        if (match[1].endsWith(".js")) aliases[match[2]] = target;
        else assert(fs.existsSync(path.join(target, "qmldir")), `${relativePath(file)}: ${match[1]} needs a qmldir`);
    }

    // Every Alias.member referenced in this file exists in the aliased JS module.
    for (const [alias, target] of Object.entries(aliases)) {
        const module = loadModule(relativePath(target), registry);
        const code = text
            .replace(/^\s*import .*$/gm, "")
            .replace(/\/\/.*$/gm, "")
            .replace(/"(?:[^"\\]|\\.)*"/g, '""');
        const used = new Set(
            [...code.matchAll(new RegExp(`(?<![\\w.])${alias}\\.(\\w+)`, "g"))].map((usage) => usage[1])
        );
        for (const member of used)
            assert(
                member in module,
                `${relativePath(file)}: ${alias}.${member} does not exist in ${relativePath(target)}`
            );
    }
}

// ── qmldir: file names must match listed components, and vice versa ───────────
for (const qmldir of listFiles(srcRoot, /^qmldir$/)) {
    const dir = path.dirname(qmldir);
    const listed = [];
    for (const line of fs.readFileSync(qmldir, "utf8").split("\n")) {
        const match = /^(?:singleton\s+)?(\w+)\s+[\d.]+\s+(\S+\.qml)$/.exec(line.trim());
        if (!match) continue;
        listed.push(match[2]);
        assert(fs.existsSync(path.join(dir, match[2])), `${relativePath(qmldir)}: ${match[2]} missing`);
        assert.strictEqual(match[1] + ".qml", match[2], `${relativePath(qmldir)}: component name must equal file name`);
    }
    for (const file of fs.readdirSync(dir).filter((fileName) => fileName.endsWith(".qml")))
        assert(listed.includes(file), `${relativePath(qmldir)}: ${file} is not registered`);
}

// ── No source file refers to the old layout ──────────────────────────────────
for (const file of [...qmlFiles, ...jsFiles]) {
    const text = fs.readFileSync(file, "utf8");
    assert(!/\.\.\/JS\/(Constants|Helpers)\.js/.test(text), `${relativePath(file)}: stale JS path`);
    assert(
        !/Contracts\/(DataPoint|SavedSymbol|ProviderResponse|ProviderPropertiesBase)\.js|ProviderInterface|ProviderBootstrap|ProviderPropertiesBase|ErrorHandler\.js/.test(
            text.replace(/\/\/.*$/gm, "")
        ),
        `${relativePath(file)}: refers to the removed JS contracts / interface / bootstrap / ErrorHandler.js`
    );
}

// ── Syntax check with qmllint when available (import-resolution warnings for the
//    DMS-provided `qs.*` modules are expected and ignored) ─────────────────────
const lint = spawnSync("qmllint", ["--version"], { encoding: "utf8" });
if (lint.status === 0) {
    for (const file of qmlFiles) {
        const result = spawnSync("qmllint", [file], { encoding: "utf8" });
        const output = `${result.stdout}${result.stderr}`;
        assert(
            !/syntax error|unexpected token|Expected token|unterminated/i.test(output),
            `${relativePath(file)}: qmllint reported a syntax error\n${output}`
        );
    }
} else {
    console.log("qmllint not found; skipping QML syntax check");
}

console.log("QML structure tests passed");
