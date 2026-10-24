// RuntimeWarnings.test.js - expected disk-failure output must never hide other runtime diagnostics.
const assert = require("node:assert/strict");
const { unexpectedWarnings } = require("../../Helpers/RuntimeWarnings");
const filePath = "/tmp/cache/symbol.json";
const declaration = `INFO qml: T:EXPECTED-FILE-WRITE-WARNING ${JSON.stringify({ path: filePath, maxCount: 2 })}`;
const warning = `WARN scene: QML FileView at file:///repo/src/QML/Services/MarketCache.qml[513:9]: Write of ${filePath} failed: Unknown error when opening file.`;
assert.deepEqual(unexpectedWarnings(warning), [warning]);
assert.deepEqual(unexpectedWarnings(`${declaration}\n${warning}\n${warning}`), []);
assert.deepEqual(unexpectedWarnings(`${declaration}\n${warning}\n${warning}\n${warning}`), [warning]);
for (const unrelated of [
    warning.replace("WARN", "ERROR"),
    warning.replace(filePath, "/tmp/cache/another.json"),
    warning.replace("MarketCache.qml", "Another.qml"),
    warning.replace("Unknown error when opening file.", "Permission denied."),
    "WARN scene: Binding loop detected for property value",
    "ERROR scene: TypeError: Property _isLive of object [null] is not a function"
])
    assert.deepEqual(unexpectedWarnings(`${declaration}\n${unrelated}`), [unrelated]);
// Fixed Quickshell versions need not emit the upstream warning.
assert.deepEqual(unexpectedWarnings(declaration), []);
console.log("Runtime warning policy tests passed");
