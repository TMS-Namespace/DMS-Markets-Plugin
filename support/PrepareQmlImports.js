// Prepare editor-only imports from installed Quickshell metadata, supplementing its missing Qt process enum.
const fs = require("fs");
const path = require("path");

const overlayRoot = path.join(__dirname, "lint-imports");

// Honor custom Qt installations before searching the usual system QML directories.
function qmlImportPaths() {
    return [
        ...(process.env.QML_IMPORT_PATH || "").split(path.delimiter).filter(Boolean),
        ...["/usr/lib64/qt6/qml", "/usr/lib/qt6/qml", "/usr/lib/x86_64-linux-gnu/qt6/qml"].filter(fs.existsSync)
    ];
}

// Copy the installed module's declarations and QML files, keeping binaries and system files untouched.
function prepareQmlImports(importPaths = qmlImportPaths(), destinationRoot = overlayRoot) {
    const source = importPaths
        .map((directory) => path.resolve(directory, "Quickshell", "Io"))
        .find((directory) => fs.existsSync(path.join(directory, "qmldir")));
    if (!source)
        throw new Error(
            "Quickshell.Io metadata was not found. Install Quickshell or set QML_IMPORT_PATH to its QML import directory."
        );
    const destination = path.resolve(destinationRoot, "Quickshell", "Io");
    if (source === destination)
        throw new Error("The editor import overlay cannot also be the source of Quickshell metadata.");
    const moduleDeclaration = fs.readFileSync(path.join(source, "qmldir"), "utf8");
    const typeFiles = [...moduleDeclaration.matchAll(/^typeinfo\s+(\S+)\s*$/gm)].map((match) => match[1]);
    if (!typeFiles.length) throw new Error(`Quickshell.Io has no typeinfo declarations: ${source}`);
    const metadata = typeFiles.map((file) => fs.readFileSync(path.join(source, file), "utf8")).join("\n");
    if (!/\bname:\s*"Process"/.test(metadata)) throw new Error(`Quickshell.Io does not declare Process: ${source}`);
    const needsProcessEnum =
        /\btype:\s*"QProcess::ExitStatus"/.test(metadata) && !/\bname:\s*"QProcess"/.test(metadata);

    fs.rmSync(destination, { recursive: true, force: true });
    fs.cpSync(source, destination, {
        recursive: true,
        filter: (file) => fs.statSync(file).isDirectory() || /(?:\.qml|\.qmltypes|[/\\]qmldir)$/.test(file)
    });
    // Resource URLs point back at the uncorrected module; use the copied declarations instead.
    let editorDeclaration = moduleDeclaration.replace(/^prefer\s+.*(?:\r?\n|$)/gm, "");
    if (needsProcessEnum) {
        fs.writeFileSync(
            path.join(destination, "qprocess.qmltypes"),
            `// Qt's QProcess::ExitStatus enum, referenced by Quickshell's Process.exited signal.
import QtQuick.tooling 1.2
Module {
    Component {
        name: "QProcess"
        accessSemantics: "reference"
        Enum { name: "ExitStatus"; values: ["NormalExit", "CrashExit"] }
    }
}
`
        );
        editorDeclaration += "\ntypeinfo qprocess.qmltypes\n";
    }
    fs.writeFileSync(path.join(destination, "qmldir"), editorDeclaration);
    return destinationRoot;
}

module.exports = { prepareQmlImports, qmlImportPaths };
if (require.main === module) {
    try {
        console.log(`Prepared QML editor imports: ${prepareQmlImports()}`);
    } catch (error) {
        console.error(error.message);
        process.exitCode = 1;
    }
}
