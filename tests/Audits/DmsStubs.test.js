// The harness stands in for DMS's own qs.* modules (tests/Helpers/Harness). A stand-in in the wrong module hides real
// load errors ("StringSetting is not a type" passed the tests once because the stub lived in qs.Widgets while DMS has it
// in qs.Modules.Plugins). When DMS is installed, every stand-in must sit exactly where the real type is, and every
// qs module the plugin imports must exist there too. Without DMS installed this check is skipped.
const fs = require("fs");
const path = require("path");
const { assert, srcRoot, listFiles } = require("../Helpers/Loader");

const dmsRoot = ["/usr/share/quickshell/dms", path.join(process.env.HOME || "", ".config/quickshell/dms")].find((dir) =>
    fs.existsSync(path.join(dir, "Common"))
);
if (!dmsRoot) {
    console.log("DMS is not installed; skipping the stand-in placement audit");
} else {
    const harness = path.join(__dirname, "..", "Helpers", "Harness");
    let checked = 0;
    for (const file of listFiles(harness, /\.qml$/)) {
        const relative = path.relative(harness, file);
        if (relative === "shell.qml") continue;
        assert(
            fs.existsSync(path.join(dmsRoot, relative)),
            `${relative}: the stand-in has no counterpart in DMS (${dmsRoot}); move it to where the real type lives`
        );
        checked++;
    }
    assert(checked >= 10, "stand-ins found");

    // Every qs.* module the plugin imports is a directory of DMS, and every DMS type the plugin uses by name is stubbed
    // in that same module (a type used but not stubbed fails the load test; a stub in another module is caught above).
    for (const file of listFiles(srcRoot, /\.qml$/)) {
        for (const match of fs.readFileSync(file, "utf8").matchAll(/^import qs\.([\w.]+)\s*$/gm))
            assert(
                fs.existsSync(path.join(dmsRoot, ...match[1].split("."))),
                `${path.relative(srcRoot, file)}: DMS has no module qs.${match[1]}`
            );
    }
    console.log(`DMS stand-in placement audit passed (${checked} stand-ins)`);
}
