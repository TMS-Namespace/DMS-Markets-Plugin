// Format project QML and JavaScript with Qt 6 and Prettier, preserving QML library directives and runtime APIs.
const fs = require("fs");
const path = require("path");
const { createRequire } = require("module");
const { spawn } = require("child_process");
const { pathToFileURL } = require("url");
const { collect, findLanguageServer } = require("./Lint");
const { prepareQmlImports, qmlImportPaths } = require("./PrepareQmlImports");
const root = path.resolve(__dirname, "..");

// npm exec puts the selected Prettier executable on PATH without adding dependencies to the plugin.
function findPrettier() {
    for (const directory of (process.env.PATH || "").split(path.delimiter)) {
        const executable = path.join(directory, "prettier");
        if (fs.existsSync(executable)) return createRequire(fs.realpathSync(executable))("prettier");
    }
    throw new Error("Run: npm exec --yes --package=prettier@3.6.2 -- node audit/Format.js");
}

// Protect QML directives as comments while Prettier formats the JavaScript body, then restore them verbatim.
async function formatJavaScript(files, prettier) {
    const options = JSON.parse(fs.readFileSync(path.join(root, ".prettierrc.json"), "utf8"));
    const results = new Map();
    for (const file of files) {
        const directives = [];
        const prepared = fs.readFileSync(file, "utf8").replace(/^\.(?:pragma|import)\b[^\n]*/gm, (directive) => {
            directives.push(directive);
            return "// QML_FORMAT_DIRECTIVE_" + (directives.length - 1);
        });
        let formatted = await prettier.format(prepared, { ...options, parser: "babel" });
        formatted = formatted.replace(
            /^\/\/ QML_FORMAT_DIRECTIVE_(\d+)[\t ]*$/gm,
            (_match, index) => directives[Number(index)]
        );
        results.set(file, formatted);
    }
    return results;
}

// Use the Qt 6 language server's native formatter, including project .qmlformat.ini settings.
async function formatQml(files) {
    const imports = [prepareQmlImports(), ...qmlImportPaths()];
    const server = spawn(
        findLanguageServer(),
        ["--no-cmake-calls", ...imports.flatMap((directory) => ["-I", directory])],
        { cwd: root }
    );
    let nextId = 0;
    let buffer = Buffer.alloc(0);
    let stderr = "";
    const pending = new Map();

    // Send one framed JSON-RPC message.
    function send(message) {
        const body = Buffer.from(JSON.stringify({ jsonrpc: "2.0", ...message }));
        server.stdin.write(`Content-Length: ${body.length}\r\n\r\n`);
        server.stdin.write(body);
    }

    // Reject outstanding requests when the server cannot complete formatting.
    function fail(error) {
        for (const callback of pending.values()) callback.reject(error);
        pending.clear();
    }

    // Match a response to its request without depending on diagnostic notification order.
    function request(method, params) {
        return new Promise((resolve, reject) => {
            const id = ++nextId;
            pending.set(id, { resolve, reject });
            send({ id, method, params });
        });
    }

    server.stdout.on("data", (chunk) => {
        buffer = Buffer.concat([buffer, chunk]);
        try {
            for (;;) {
                const end = buffer.indexOf("\r\n\r\n");
                if (end < 0) return;
                const header = /Content-Length:\s*(\d+)/i.exec(buffer.subarray(0, end).toString());
                if (!header) throw new Error("Invalid QML formatter protocol header");
                const length = Number(header[1]);
                if (buffer.length < end + 4 + length) return;
                const message = JSON.parse(buffer.subarray(end + 4, end + 4 + length).toString());
                buffer = buffer.subarray(end + 4 + length);
                if (pending.has(message.id)) {
                    const callback = pending.get(message.id);
                    pending.delete(message.id);
                    if (message.error) callback.reject(new Error(message.error.message));
                    else callback.resolve(message.result);
                } else if (message.method && message.id !== undefined) {
                    const result =
                        message.method === "workspace/configuration" ? message.params.items.map(() => null) : null;
                    send({ id: message.id, result });
                }
            }
        } catch (error) {
            fail(error);
        }
    });
    server.stderr.on("data", (chunk) => {
        stderr = (stderr + chunk.toString()).slice(-1500);
    });
    server.on("error", fail);
    server.on("exit", () => fail(new Error(`QML formatter exited early. ${stderr}`)));
    const deadline = setTimeout(() => {
        fail(new Error("QML formatting timed out"));
        server.kill();
    }, 90000);
    const results = new Map();
    try {
        const capabilities = await request("initialize", {
            processId: process.pid,
            rootUri: pathToFileURL(root).href,
            capabilities: {}
        });
        if (!capabilities.capabilities.documentFormattingProvider)
            throw new Error("Qt 6 qmlls does not support formatting");
        send({ method: "initialized", params: {} });
        for (const file of files) {
            const uri = pathToFileURL(file).href;
            // Qt's formatter rejects the valid runtime property named `id`. Protect its spelling during formatting only.
            const source = fs
                .readFileSync(file, "utf8")
                .replace(/property string id:/g, "property string qmlFormatterReservedId:");
            send({
                method: "textDocument/didOpen",
                params: { textDocument: { uri, languageId: "qml", version: 1, text: source } }
            });
            let edits;
            try {
                edits = await request("textDocument/formatting", {
                    textDocument: { uri },
                    options: { tabSize: 4, insertSpaces: true }
                });
            } catch (error) {
                throw new Error(`${path.relative(root, file)}: ${error.message}`);
            }
            if (!Array.isArray(edits)) throw new Error(`Missing formatting result for ${file}`);
            const lines = source.split("\n");
            const offset = (position) =>
                lines.slice(0, position.line).reduce((total, line) => total + line.length + 1, 0) + position.character;
            let formatted = source;
            for (const edit of edits
                .map((edit) => ({ start: offset(edit.range.start), end: offset(edit.range.end), text: edit.newText }))
                .sort((earlier, later) => later.start - earlier.start))
                formatted = formatted.slice(0, edit.start) + edit.text + formatted.slice(edit.end);
            results.set(file, formatted.replace(/property string qmlFormatterReservedId:/g, "property string id:"));
            send({ method: "textDocument/didClose", params: { textDocument: { uri } } });
        }
    } finally {
        clearTimeout(deadline);
        server.kill();
    }
    return results;
}

// Gather every result before writing; --check reports differences without modifying source files.
async function main() {
    if (process.argv.slice(2).some((argument) => argument !== "--check"))
        throw new Error("Usage: node audit/Format.js [--check]");
    const qmlFiles = ["src", "tests"].flatMap((directory) => collect(path.join(root, directory), ".qml"));
    const jsFiles = ["src", "tests", "audit"].flatMap((directory) => collect(path.join(root, directory), ".js"));
    const results = new Map([...(await formatJavaScript(jsFiles, findPrettier())), ...(await formatQml(qmlFiles))]);
    let changed = 0;
    for (const [file, formatted] of results) {
        if (fs.readFileSync(file, "utf8") === formatted) continue;
        changed++;
        if (process.argv.includes("--check")) console.error(path.relative(root, file));
        else fs.writeFileSync(file, formatted);
    }
    console.log(
        `Format: ${qmlFiles.length} QML files, ${jsFiles.length} JavaScript files; ${changed} ${process.argv.includes("--check") ? "need formatting" : "formatted"}.`
    );
    if (changed && process.argv.includes("--check")) process.exitCode = 1;
}

main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
});
