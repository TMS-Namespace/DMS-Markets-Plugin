// Run the editor's Qt 6 QML diagnostics and parse every JavaScript file; no npm packages or network calls are needed.
const fs = require("fs");
const path = require("path");
const os = require("os");
const vm = require("vm");
const { spawn, spawnSync } = require("child_process");
const { pathToFileURL, fileURLToPath } = require("url");
const { prepareQmlImports, qmlImportPaths } = require("./PrepareQmlImports");

const { checkProviders } = require("./CheckProviders");

const root = path.resolve(__dirname, "..");

// List source and test files without traversing symlinked editor imports.
function collect(directory, suffix) {
    return fs
        .readdirSync(directory, { withFileTypes: true })
        .flatMap((entry) => {
            const file = path.join(directory, entry.name);
            return entry.isDirectory() ? collect(file, suffix) : entry.name.endsWith(suffix) ? [file] : [];
        })
        .sort();
}

// Use the same language server as the editor, or an explicitly supplied Qt installation.
function findLanguageServer() {
    if (process.env.QMLLS) return process.env.QMLLS;
    const configHome = process.env.XDG_CONFIG_HOME || path.join(os.homedir(), ".config");
    const candidates = ["qmlls", "/usr/lib64/qt6/bin/qmlls", "/usr/lib/qt6/bin/qmlls"];
    for (const editor of ["Code", "Code - Insiders", "VSCodium", "Code - OSS"])
        candidates.push(path.join(configHome, editor, "User/globalStorage/theqtcompany.qt-qml/qmlls/files/qmlls"));
    for (const executable of candidates) {
        const result = spawnSync(executable, ["--help"], { encoding: "utf8", timeout: 5000 });
        if (result.status === 0 && /QML languageserver/.test(result.stdout)) return executable;
    }
    throw new Error(
        "Qt 6 qmlls was not found. Install the Qt QML editor extension or set QMLLS to its executable path."
    );
}

// QML's .pragma/.import directives are valid library syntax, not ordinary JavaScript expressions.
function checkJavaScript(files) {
    let failed = 0;
    for (const file of files) {
        let source = fs.readFileSync(file, "utf8");
        try {
            if (file.startsWith(path.join(root, "src", "JS") + path.sep)) {
                source = source.replace(/^[ \t]*\.(?:pragma|import)\b[^\n]*/gm, (directive) => {
                    if (!/^[ \t]*\.pragma library[ \t]*$/.test(directive)) {
                        const imported = /^[ \t]*\.import "([^"]+)" as \w+[ \t]*$/.exec(directive);
                        if (!imported || !fs.existsSync(path.resolve(path.dirname(file), imported[1])))
                            throw new SyntaxError(
                                `${path.relative(root, file)}: invalid QML JavaScript directive: ${directive.trim()}`
                            );
                    }
                    return directive.replace(/[^\n]/g, " ");
                });
            }
            new vm.Script(source, { filename: path.relative(root, file) });
        } catch (error) {
            failed++;
            console.error(error.stack);
        }
    }
    return failed;
}

// Collect diagnostics from all opened QML documents, including files with an empty diagnostic list.
function checkQml(executable, files) {
    return new Promise((resolve, reject) => {
        const importPaths = [prepareQmlImports(), ...qmlImportPaths()];
        const server = spawn(
            executable,
            ["--no-cmake-calls", ...importPaths.flatMap((directory) => ["-I", directory])],
            { cwd: root }
        );
        const diagnostics = new Map();
        const expected = new Set(files.map((file) => pathToFileURL(file).href));
        let buffer = Buffer.alloc(0),
            stderr = "",
            settled = false,
            settleTimer;
        const deadline = setTimeout(
            () =>
                finish(
                    new Error(
                        `QML diagnostics timed out: ${diagnostics.size}/${files.length} files reported.\n${stderr.slice(-1500)}`
                    )
                ),
            90000
        );

        // Frame one JSON-RPC request or response on the language server's standard input.
        function send(message) {
            if (server.stdin.destroyed) return;
            const body = Buffer.from(JSON.stringify({ jsonrpc: "2.0", ...message }));
            server.stdin.write(`Content-Length: ${body.length}\r\n\r\n`);
            server.stdin.write(body);
        }

        // Stop the server and settle the lint run exactly once, including startup and protocol errors.
        function finish(error) {
            if (settled) return;
            settled = true;
            clearTimeout(deadline);
            clearTimeout(settleTimer);
            server.kill();
            if (error) {
                reject(error);
                return;
            }
            let count = 0;
            for (const file of files) {
                for (const diagnostic of diagnostics.get(pathToFileURL(file).href) || []) {
                    if (diagnostic.severity && diagnostic.severity > 2) continue;
                    count++;
                    const location = diagnostic.range.start;
                    console.error(
                        `${path.relative(root, file)}:${location.line + 1}:${location.character + 1}: ${diagnostic.message.trim()}`
                    );
                }
            }
            resolve(count);
        }

        // Initialize the project, then wait until each document has been analyzed and updates have settled.
        function receive(message) {
            if (message.id === 1 && !message.method) {
                if (message.error) {
                    finish(new Error(message.error.message));
                    return;
                }
                send({ method: "initialized", params: {} });
                for (const file of files)
                    send({
                        method: "textDocument/didOpen",
                        params: {
                            textDocument: {
                                uri: pathToFileURL(file).href,
                                languageId: "qml",
                                version: 1,
                                text: fs.readFileSync(file, "utf8")
                            }
                        }
                    });
            } else if (message.method === "textDocument/publishDiagnostics") {
                const uri = pathToFileURL(fileURLToPath(message.params.uri)).href;
                if (!expected.has(uri)) return;
                diagnostics.set(uri, message.params.diagnostics);
                clearTimeout(settleTimer);
                if (diagnostics.size === files.length) settleTimer = setTimeout(() => finish(), 2000);
            } else if (message.method && message.id !== undefined) {
                const result =
                    message.method === "workspace/configuration" ? message.params.items.map(() => null) : null;
                send({ id: message.id, result });
            }
        }

        server.stdout.on("data", (chunk) => {
            buffer = Buffer.concat([buffer, chunk]);
            try {
                for (;;) {
                    const end = buffer.indexOf("\r\n\r\n");
                    if (end < 0) return;
                    const match = /content-length:\s*(\d+)/i.exec(buffer.subarray(0, end).toString());
                    if (!match) throw new Error("qmlls returned an invalid protocol header");
                    const length = Number(match[1]),
                        start = end + 4;
                    if (buffer.length < start + length) return;
                    const message = JSON.parse(buffer.subarray(start, start + length).toString());
                    buffer = buffer.subarray(start + length);
                    receive(message);
                }
            } catch (error) {
                finish(error);
            }
        });
        server.stderr.on("data", (chunk) => {
            stderr = (stderr + chunk.toString()).slice(-6000);
        });
        server.on("error", finish);
        server.on("exit", (code) => {
            if (!settled) finish(new Error(`qmlls exited before reporting all diagnostics (${code}).\n${stderr}`));
        });
        send({
            id: 1,
            method: "initialize",
            params: {
                processId: process.pid,
                rootUri: pathToFileURL(root).href,
                capabilities: {},
                workspaceFolders: [{ uri: pathToFileURL(root).href, name: path.basename(root) }]
            }
        });
    });
}

// Keep lint separate from the runtime suite so missing developer tooling can never masquerade as a passing lint run.
async function main() {
    console.log(`Provider contracts: ${checkProviders().join(", ")}; all implementations conform.`);
    const qmlFiles = ["src", "tests"].flatMap((directory) => collect(path.join(root, directory), ".qml"));
    const jsFiles = ["src", "tests", "audit"].flatMap((directory) => collect(path.join(root, directory), ".js"));
    const syntaxFailures = checkJavaScript(jsFiles);
    const diagnostics = await checkQml(findLanguageServer(), qmlFiles);
    console.log(
        `Lint: ${qmlFiles.length} QML files, ${jsFiles.length} JavaScript files; ${diagnostics} QML warnings/errors, ${syntaxFailures} JavaScript syntax errors.`
    );
    if (diagnostics || syntaxFailures) process.exitCode = 1;
}

module.exports = { collect, findLanguageServer };
if (require.main === module)
    main().catch((error) => {
        console.error(error.message);
        process.exitCode = 1;
    });
