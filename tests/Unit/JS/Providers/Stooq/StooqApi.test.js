// Execute the embedded Stooq proof-of-work program locally; no provider or network calls are made.
const crypto = require("crypto");
const { spawnSync } = require("child_process");
const { assert, loadShared } = require("../../../../Helpers/Loader");
const { stooq, stooqConstants } = loadShared();
const script = stooq.fetchScript(0);
const match = /nonce=\$\(node -e '([^']+)'/.exec(script);
assert(match, "the verification program is present in the fetch script");
const program = match[1];
const solve = (difficulty) =>
    spawnSync(process.execPath, ["-e", program, "fixture", String(difficulty)], { encoding: "utf8", timeout: 5000 });
const solved = solve(1);
assert.strictEqual(solved.status, 0, solved.stderr);
assert(
    crypto
        .createHash("sha256")
        .update("fixture" + solved.stdout.trim())
        .digest("hex")
        .startsWith("0")
);
for (const invalid of [-1, 1.5, "bad", stooqConstants.STOOQ_POW_MAX_DIFFICULTY + 1]) {
    const rejected = solve(invalid);
    assert.strictEqual(rejected.status, 1, `unsupported challenge ${invalid} is refused`);
    assert.strictEqual(rejected.stdout, "");
}
assert(program.includes("nonce<" + stooqConstants.STOOQ_POW_MAX_ATTEMPTS), "the search has a fixed attempt cap");
assert(program.includes("Date.now()<deadline"), "the search also has a time limit");
console.log("Stooq proof-of-work bounds passed");
