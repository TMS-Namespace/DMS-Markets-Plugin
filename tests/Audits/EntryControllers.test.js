// Entry points compose UI and connect host APIs. Per-instance controllers own nonvisual state and actions.
const { assert, readSource } = require("../Helpers/Loader");

for (const name of ["Settings", "Widget"]) {
    const entry = readSource(`QML/${name}.qml`).replace(/\/\/[^\n]*/g, "");
    const controller = readSource(`QML/Helpers/${name}Controller.qml`).replace(/\/\/[^\n]*/g, "");
    // Nested components access the controller through the entry's root, avoiding implicit parent lookups.
    const expressions = entry.replace(/^.*property alias.*$/gm, "");
    assert(
        !/(^|[^\w.])(?:controller|widgetController|settingsController)\./.test(expressions),
        `${name}: qualify controller access through root.controller`
    );
    assert(entry.includes(`${name}Controller {`), `${name} creates its own controller`);
    assert(
        !/DataStorage\s*\{|MarketCache\s*\{|MarketDataFetcher\s*\{|SymbolManager\s*\{/.test(entry),
        `${name}: nonvisual components belong to its controller`
    );
    assert(
        !/SymbolRules\.|SymbolDraft\.|ProvidersManager\.|\.clampSelection\(|\.migrateSavedSymbols\(/.test(entry),
        `${name}: provider and saved-data decisions belong to helpers`
    );
    assert(
        !/import.*Views|import qs\.|ToastService|StyledText|MouseArea|DankTextField/.test(controller),
        `${name}: controller must work without views or DMS controls`
    );
}

const controller = readSource("QML/Helpers/SettingsController.qml");
assert(
    !/symbolEditor|tickerField|nameField|property var editor/.test(controller),
    "the settings controller takes plain data instead of reaching into visual controls"
);
console.log("Entry controller audit passed");
