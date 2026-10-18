// Verify editor metadata repair preserves installed APIs, handles upstream fixes, and rejects incomplete installations.
const assert = require("assert").strict;
const fs = require("fs");
const os = require("os");
const path = require("path");
const { prepareQmlImports } = require("../../../support/PrepareQmlImports");

const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "markets-qml-imports-"));
const installedRoot = path.join(temporaryRoot, "installed");
const installedModule = path.join(installedRoot, "Quickshell", "Io");
const overlayRoot = path.join(temporaryRoot, "editor");
const overlayModule = path.join(overlayRoot, "Quickshell", "Io");
const moduleDeclaration = "module Quickshell.Io\ntypeinfo io.qmltypes\nprefer :/qt/qml/Quickshell/Io/\nFileView 0.0 FileView.qml\n";
const incompleteMetadata = `import QtQuick.tooling 1.2
Module {
    Component {
        name: "Process"
        Signal {
            name: "exited"
            Parameter { name: "exitCode"; type: "int" }
            Parameter { name: "exitStatus"; type: "QProcess::ExitStatus" }
        }
    }
}
`;

try {
    fs.mkdirSync(installedModule, { recursive: true });
    fs.writeFileSync(path.join(installedModule, "qmldir"), moduleDeclaration);
    fs.writeFileSync(path.join(installedModule, "io.qmltypes"), incompleteMetadata);
    fs.writeFileSync(path.join(installedModule, "FileView.qml"), "import QtQml\nQtObject {}\n");
    fs.writeFileSync(path.join(installedModule, "plugin.so"), "binary stand-in");

    assert.equal(prepareQmlImports([installedRoot], overlayRoot), overlayRoot);
    assert.equal(fs.readFileSync(path.join(overlayModule, "io.qmltypes"), "utf8"), incompleteMetadata);
    assert.equal(fs.readFileSync(path.join(overlayModule, "FileView.qml"), "utf8"), "import QtQml\nQtObject {}\n");
    assert(!fs.existsSync(path.join(overlayModule, "plugin.so")), "editor imports do not copy plugin binaries");
    const editorDeclaration = fs.readFileSync(path.join(overlayModule, "qmldir"), "utf8");
    assert(editorDeclaration.includes("typeinfo io.qmltypes"));
    assert(editorDeclaration.includes("typeinfo qprocess.qmltypes"));
    assert(editorDeclaration.includes("FileView 0.0 FileView.qml"));
    assert(!editorDeclaration.includes("prefer "), "resource paths must not bypass the corrected metadata");
    const enumMetadata = fs.readFileSync(path.join(overlayModule, "qprocess.qmltypes"), "utf8");
    assert(enumMetadata.includes('name: "ExitStatus"; values: ["NormalExit", "CrashExit"]'));
    assert.equal(fs.readFileSync(path.join(installedModule, "qmldir"), "utf8"), moduleDeclaration);
    assert.equal(fs.readFileSync(path.join(installedModule, "io.qmltypes"), "utf8"), incompleteMetadata);

    // Regeneration is repeatable and removes the supplement after an upstream metadata fix.
    prepareQmlImports([installedRoot], overlayRoot);
    const completeMetadata = incompleteMetadata.replace("Module {", 'Module { Component { name: "QProcess"; Enum { name: "ExitStatus"; values: ["NormalExit", "CrashExit"] } }');
    fs.writeFileSync(path.join(installedModule, "io.qmltypes"), completeMetadata);
    prepareQmlImports([installedRoot], overlayRoot);
    assert.equal(fs.readFileSync(path.join(overlayModule, "io.qmltypes"), "utf8"), completeMetadata);
    assert(!fs.existsSync(path.join(overlayModule, "qprocess.qmltypes")));
    assert(!fs.readFileSync(path.join(overlayModule, "qmldir"), "utf8").includes("qprocess.qmltypes"));

    // Broken discovery must fail explicitly and preserve the last usable editor imports.
    assert.throws(() => prepareQmlImports([], overlayRoot), /metadata was not found/);
    assert.throws(() => prepareQmlImports([overlayRoot], overlayRoot), /cannot also be the source/);
    fs.writeFileSync(path.join(installedModule, "qmldir"), "module Quickshell.Io\n");
    assert.throws(() => prepareQmlImports([installedRoot], overlayRoot), /no typeinfo/);
    assert.equal(fs.readFileSync(path.join(overlayModule, "io.qmltypes"), "utf8"), completeMetadata);
    console.log("QML editor import preparation passed");
} finally {
    fs.rmSync(temporaryRoot, { recursive: true, force: true });
}
