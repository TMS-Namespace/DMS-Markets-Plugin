// Static audit of the whole code base for the error-handling rules:
//   - JS modules throw PluginError (never a bare Error) and never touch the UI
//   - nothing swallows an exception: every catch rethrows, reports it, or is a documented exception
//   - nothing logs outside devMode
//   - no unbounded loops
const fs = require("fs");
const path = require("path");
const { assert, srcRoot, listFiles } = require("../Helpers/Loader");

const files = listFiles(srcRoot, /\.(js|qml)$/);
const relativePath = (file) => path.relative(srcRoot, file);
const read = (file) => fs.readFileSync(file, "utf8");
const jsFiles = files.filter((file) => file.endsWith(".js"));
const qmlFiles = files.filter((file) => file.endsWith(".qml"));

// Source without comments (keeps line structure), so patterns inside comments never count.
const strip = (text) =>
    text.replace(/\/\*[\s\S]*?\*\//g, (comment) => comment.replace(/[^\n]/g, " ")).replace(/(^|[^:"'])\/\/.*$/gm, "$1");

// ── 1. Typed errors only ─────────────────────────────────────────────────────
for (const file of jsFiles) {
    const code = strip(read(file));
    assert(!/throw new Error\(/.test(code), `${relativePath(file)}: throw PluginError, not a bare Error`);
    assert(!/throw ["'`]/.test(code), `${relativePath(file)}: never throw a string`);
}
for (const file of qmlFiles) {
    const code = strip(read(file));
    assert(!/throw new Error\(/.test(code), `${relativePath(file)}: throw PluginError, not a bare Error`);
}

// ── 2. JS modules never touch the UI ─────────────────────────────────────────
for (const file of jsFiles)
    assert(
        !/ToastService|Qt\.|Quickshell|\bconsole\./.test(
            strip(read(file)).replace(/_log\(|console\.warn|console\.log/g, (logCall) =>
                logCall.startsWith("console") ? "" : logCall
            )
        ) || /ErrorHandler\.js$/.test(file),
        `${relativePath(file)}: JS modules must not use UI APIs or console (use PluginError / ErrorHandler)`
    );

// ── 3. Nothing swallows an exception ─────────────────────────────────────────
// Find every `catch (x) { ... }` with its brace-matched body.
function catches(code) {
    const found = [];
    const pattern = /catch\s*\((\w+)\)\s*\{/g;
    let match;
    while ((match = pattern.exec(code))) {
        let depth = 1,
            i = pattern.lastIndex;
        while (depth > 0 && i < code.length) {
            if (code[i] === "{") depth++;
            else if (code[i] === "}") depth--;
            i++;
        }
        found.push({
            variable: match[1],
            body: code.slice(pattern.lastIndex, i - 1),
            index: match.index,
            line: code.slice(0, match.index).split("\n").length
        });
    }
    return found;
}
// Handling = rethrow, report through ErrorHandler / the fetcher's reporter, wrap into a PluginError or a failed response,
// or record a load failure. Logging alone is NOT handling: a catch that only logs is a documented exception below.
const HANDLED =
    /\bthrow\b|_handleFinished\(|ProviderResponse\.failure\(|ErrorHandler\.handle\(|(^|[^.\w])handle\(|_reportSymbolError\(|_failed\(|_fail\(|_loadErrors\[|_loadErrorType\.createObject|PluginError\.PluginError\(/;
// The only catches that deliberately return a value instead; each is justified.
const ALLOWED_QUIET = [
    {
        file: "QML/Services/ErrorHandler.qml",
        contains: "notifier failed",
        why: "a failing toast notifier must not mask the error being handled: the error is already recorded and logged, and the notifier failure is logged too"
    },
    {
        file: "JS/Providers/Yahoo/YahooApi.js",
        contains: 'return ""',
        why: "extractApiError: a body that is not JSON simply carries no API message; parsing it as data raises the PARSE error"
    },
    { file: "JS/Providers/Wise/WiseApi.js", contains: 'return ""', why: "extractApiError: same as Yahoo" },
    {
        file: "JS/Helpers/SymbolRules.js",
        contains: "is not a valid regular expression",
        why: "the failure is reported to the caller as the returned problem text"
    },
    {
        file: "QML/Services/ProviderHandler.qml",
        contains: "the owner of",
        why: "a callback of a destroyed widget throws; that is no failed fetch, the call stays current and its result is reported (logged in dev mode)"
    },
    {
        file: "QML/Services/MarketCache.qml",
        contains: "could not run",
        why: "a program that cannot start is a failed step: the caller gets a failure code and decides (retry, fallback file)"
    },
    {
        file: "QML/Services/MarketCache.qml",
        contains: "is not usable",
        why: "a damaged saved file is skipped (logged) and the symbol starts empty, as on a first run; it must never be an error for the user"
    },
    {
        file: "QML/Services/MarketCache.qml",
        contains: "no snapshot of",
        why: "a symbol whose data cannot be collected is skipped (logged); the next update tries again"
    },
    {
        file: "QML/Services/Logger.qml",
        contains: "logging must never break the caller",
        why: "a failing log sink must not break the code that logged"
    }
];
const quietSeen = new Set();
let catchCount = 0;
for (const file of files) {
    const code = strip(read(file));
    const text = read(file);
    for (const caught of catches(text)) {
        catchCount++;
        const body = strip(caught.body);
        const handled = HANDLED.test(body);
        const allowed = ALLOWED_QUIET.find(
            (entry) => relativePath(file) === entry.file && caught.body.includes(entry.contains)
        );
        assert(
            handled || allowed,
            `${relativePath(file)}:${caught.line}: catch (${caught.variable}) swallows the exception:\n${caught.body.trim()}`
        );
        if (allowed && !handled) quietSeen.add(allowed.why);
        assert(body.trim() !== "" || allowed, `${relativePath(file)}:${caught.line}: empty catch block`);
    }
}
assert(catchCount >= 15, "the audit really found the catch blocks");
assert.strictEqual(
    quietSeen.size,
    ALLOWED_QUIET.length,
    "every documented exception still exists (remove stale entries)"
);
// `finally` guards the queue: the call completion and the process wrapper (ProviderHandler).
const fetcher = read(path.join(srcRoot, "QML/Helpers/MarketDataFetcher.qml"));
const handlerQml = read(path.join(srcRoot, "QML/Services/ProviderHandler.qml"));
assert(
    (handlerQml.match(/finally \{/g) || []).length >= 3,
    "the provider handler releases its resources in finally blocks"
);

// ── 4. Logging only through the Logger, which alone checks dev mode ──────────
for (const file of qmlFiles) {
    const code = strip(read(file));
    const relative = relativePath(file);
    if (relative !== "QML/Services/Logger.qml") {
        // (Constants.qml defines the switch itself)
        assert(!/console\.(log|warn|error|info|debug)/.test(code), `${relative}: log through Logger, never console.*`);
        assert(
            !/\bdevMode\b/.test(
                code
                    .replace(/Logger\.configure\(\{\s*devMode:\s*constants\.devMode\s*\}\)/g, "")
                    .replace(/readonly property bool devMode: (true|false)/, "")
            ),
            `${relative}: only the Logger knows dev mode; callers log without checking it`
        );
    }
}
const loggerSource = strip(read(path.join(srcRoot, "QML/Services/Logger.qml")));
assert(
    /function _write\(level, scope, text\) \{\s*if \(!devMode \|\| !sink\)\s*return/.test(loggerSource),
    "the Logger writes only in dev mode"
);
assert(
    /singleton Logger 1\.0 Logger\.qml/.test(read(path.join(srcRoot, "QML/Services/qmldir"))),
    "the Logger is a registered singleton"
);
assert.strictEqual((loggerSource.match(/console\./g) || []).length, 2, "the default sink is the one place that prints");

// ── 5. No unbounded loops ────────────────────────────────────────────────────
for (const file of files) {
    const code = strip(read(file));
    assert(
        !/while\s*\(\s*(true|1)\s*\)/.test(code) && !/for\s*\(\s*;\s*;\s*\)/.test(code),
        `${relativePath(file)}: unbounded loop`
    );
    assert(!/setInterval|setTimeout/.test(code), `${relativePath(file)}: raw timers (use QML Timer)`);
}
// Repeating timers: only the poll timer and the "x sec ago" tick; everything else (retry, pump, stagger) is one-shot.
const repeating = [];
for (const file of qmlFiles) {
    const code = strip(read(file));
    for (const timerMatch of code.matchAll(/Timer \{([\s\S]*?)\n\s*\}\n/g))
        if (/repeat:\s*true/.test(timerMatch[1]))
            repeating.push(`${relativePath(file)}#${(/id:\s*(\w+)/.exec(timerMatch[1]) || [, "anonymous"])[1]}`);
}
assert.deepStrictEqual(
    repeating.sort(),
    ["QML/Helpers/MarketDataFetcher.qml#checkTimer", "QML/Views/SymbolRow.qml#anonymous"],
    "only the poll timer and the ago tick repeat"
);
assert(
    /id: checkTimer[\s\S]*?running: root\.symbols\.length > 0/.test(fetcher),
    "polling stops when there are no symbols"
);
for (const [source, timers] of [
    [handlerQml, ["retryTimer", "pumpTimer"]],
    [fetcher, ["initialGraphTimer"]]
])
    for (const timer of timers)
        assert(new RegExp(`id: ${timer}[\\s\\S]*?repeat: false`).test(source), `${timer} is one-shot`);
// Retries are finite (see MarketDataFetcher tests for the behaviour): the limits are constants.
const constants = read(path.join(srcRoot, "JS/Helpers/Constants.js"));
for (const name of ["MAX_RETRIES", "RETRY_QUEUE_MAX", "MAX_CONCURRENT_FETCHES"])
    assert(new RegExp(`var ${name}\\s*=\\s*\\d+`).test(constants), `${name} is a finite constant`);

// ── 6. User-facing errors never carry raw internals ──────────────────────────
for (const file of qmlFiles) {
    const code = strip(read(file));
    // Validation results (`validation.message`, `status.message`) are user-facing text; exceptions are not.
    assert(
        !/ToastService\.show\w+\([^)]*\b(e|e2|err|error|ex|exception|backupError)\.(message|details|stack)/.test(code),
        `${relativePath(file)}: toasts must use userMessage, never an exception's message`
    );
    assert(
        !/text:\s*(e|e2|err|error|ex|exception)\.(message|details|stack)\b/.test(code),
        `${relativePath(file)}: show userMessage, not an exception's message`
    );
}

console.log("Error handling audit passed");
