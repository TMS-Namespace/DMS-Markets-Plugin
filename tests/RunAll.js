// Runs every test under tests/, each in its own process. Layout:
//   Unit/          one module in isolation; mirrors the src/ structure
//   Integration/   several modules together through the real stack; mirrors src/ (Integration/Live talks to real services)
//   Audits/        static rules about the whole code base (architecture, error handling, imports, manifest)
//   Helpers/       the test helpers: the Node module loader and the QML harness (not tests)
// File types:
//   *.test.js   plain Node (logic modules, static audits, extracted QML functions)
//   *.test.qml  the real Qt6 QML runtime: Quickshell run headless (QT_QPA_PLATFORM=offscreen) with the
//               harness in tests/Helpers/Harness (contracts, singletons, services are really instantiated)
// `--live` additionally runs tests/Integration/Live/ProviderLive.test.qml (real requests; needs network access).
const { unexpectedWarnings } = require("./Helpers/RuntimeWarnings");
const fs = require("fs");
const path = require("path");
const os = require("os");
const { spawnSync } = require("child_process");

const harness = path.join(__dirname, "Helpers", "Harness");
// QML tests run with a stand-in curl first on PATH (canned answers, no network); the live test sets its own PATH back.
const fakeBin = path.join(__dirname, "Helpers", "FakeBin");
const liveFile = path.join(__dirname, "Integration", "Live", "ProviderLive.test.qml");

function collect(dir, suffix) {
    return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory())
            return (entry.name === "Helpers" && dir === __dirname) || entry.name === "Live"
                ? []
                : collect(full, suffix); // Live is opt-in
        return entry.name.endsWith(suffix) ? [full] : [];
    });
}

function runNode(file) {
    const result = spawnSync(process.execPath, [file], { encoding: "utf8" });
    return { ok: result.status === 0, output: `${result.stdout}${result.stderr}` };
}

function runQml(file, extraEnv = {}, timeout = 120000) {
    // Saved market data goes to the user's cache directory: every test run gets one of its own (never the real one).
    const cacheHome = fs.mkdtempSync(path.join(os.tmpdir(), "markets-test-cache-"));
    const result = spawnSync("quickshell", ["-p", harness], {
        encoding: "utf8",
        timeout,
        env: {
            ...process.env,
            PATH: `${fakeBin}${path.delimiter}${process.env.PATH}`,
            QT_QPA_PLATFORM: "offscreen",
            NO_COLOR: "1",
            TEST_FILE: file,
            XDG_CACHE_HOME: cacheHome,
            ...extraEnv
        }
    });
    fs.rmSync(cacheHome, { recursive: true, force: true });
    const lines = `${result.stdout}${result.stderr}`.split("\n").filter((line) => line.includes("T:"));
    const summary = lines
        .map((line) => /T:SUMMARY passed=(\d+) failed=(\d+)/.exec(line))
        .filter(Boolean)
        .pop();
    const failures = lines
        .filter((line) => /T:(FAIL|LOAD-ERROR)/.test(line))
        .map((line) => line.slice(line.indexOf("T:")));
    // Any QML runtime warning is a failure too: a TypeError in a binding, a component that is not ready, an unknown
    // property... break things silently in DMS, and a passing assertion elsewhere would hide them.
    const warnings = unexpectedWarnings(`${result.stdout}${result.stderr}`);
    const ok = !!summary && Number(summary[2]) === 0 && failures.length === 0 && warnings.length === 0;
    const output = ok
        ? ""
        : failures.concat(warnings.map((line) => `QML warning: ${line.trim()}`)).join("\n") ||
          "the suite did not report a result\n" + `${result.stdout}${result.stderr}`.slice(-2000);
    return { ok, output, count: summary ? Number(summary[1]) : 0 };
}

const hasQuickshell = spawnSync("quickshell", ["--version"], { encoding: "utf8" }).status === 0;
const files = [
    ...collect(__dirname, ".test.js")
        .sort()
        .map((file) => ({ file, run: runNode })),
    ...collect(__dirname, ".test.qml")
        .sort()
        .map((file) => ({ file, run: runQml }))
];
if (process.argv.includes("--live"))
    files.push({
        file: liveFile,
        run: (file) =>
            runQml(
                file,
                { PATH: process.env.PATH, TEST_TIMEOUT_MS: "1500000", TEST_ASYNC_TIMEOUT_MS: "1500000" },
                1600000
            )
    });

let failed = 0,
    skipped = 0;
for (const { file, run } of files) {
    const name = path.relative(__dirname, file);
    if (run === runQml && !hasQuickshell) {
        skipped++;
        console.log(`SKIP ${name} (quickshell not found)`);
        continue;
    }
    const result = run(file);
    if (result.ok) {
        console.log(`PASS ${name}${result.count ? ` (${result.count})` : ""}`);
    } else {
        failed++;
        console.log(`FAIL ${name}\n${result.output}`);
    }
}
if (failed) {
    console.log(`${failed} test file(s) failed`);
    process.exit(1);
}
console.log(`all tests passed${skipped ? ` (${skipped} skipped)` : ""}`);
