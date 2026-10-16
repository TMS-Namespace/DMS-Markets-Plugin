const { assert, same, loadShared } = require("../../../Helpers/Loader");

const { errors } = loadShared();
const { PluginError, Code } = errors;

// ── Shape ────────────────────────────────────────────────────────────────────
const error = new PluginError(Code.NETWORK, "Can't reach Wise.", "curl exit 6", { status: 0, retryable: true });
assert(error instanceof Error && error instanceof PluginError, "is a real Error (stack, instanceof, throwable)");
assert.strictEqual(error.name, "PluginError");
assert.strictEqual(error.code, "network");
assert.strictEqual(error.userMessage, "Can't reach Wise.");
assert.strictEqual(error.details, "curl exit 6");
assert.strictEqual(error.message, "Can't reach Wise. — curl exit 6", "message = what a developer reads in the log");
assert.strictEqual(error.retryable, true);
assert.strictEqual(error.status, 0);
assert.strictEqual(typeof error.stack, "string");
assert(errors.isPluginError(error));
assert.throws(() => { throw error; }, (thrown) => thrown === error);

// Defaults and edge cases.
const bare = new PluginError();
assert.strictEqual(bare.code, "unknown");
assert.strictEqual(bare.userMessage, "Something went wrong.");
assert.strictEqual(bare.message, "Something went wrong.");
assert.strictEqual(bare.retryable, false, "not retryable unless stated");
assert.strictEqual(bare.status, 0);
assert.strictEqual(new PluginError("x", "m", "", { status: 404 }).status, 404);
assert.strictEqual(new PluginError("x", "m", "", { retryable: "yes" }).retryable, false, "only a real true counts");
assert.strictEqual(new PluginError("x", "m", "d").message, "m — d");
assert.strictEqual(new PluginError("x", "m").message, "m");

// ── Codes ────────────────────────────────────────────────────────────────────
assert(Object.isFrozen(Code), "codes are constants");
const values = Object.values(Code);
assert.strictEqual(new Set(values).size, values.length, "codes are unique");
for (const needed of ["INVALID_SYMBOL", "UNSUPPORTED", "POLL_TOO_FAST", "UNKNOWN_PROVIDER", "PROVIDER_CONFIG", "NETWORK", "TIMEOUT", "HTTP",
                      "NOT_FOUND", "RATE_LIMITED", "CREDENTIAL", "PROCESS", "PARSE", "NO_DATA", "STORAGE", "UNKNOWN"])
    assert(Code[needed], needed);

// ── from(): foreign errors never leak their text to users ────────────────────
const foreign = errors.from(new TypeError("Cannot read properties of undefined"));
assert(foreign instanceof PluginError);
assert.strictEqual(foreign.code, "unknown");
assert.strictEqual(foreign.userMessage, "Something went wrong.", "generic user message");
assert.strictEqual(foreign.details, "Cannot read properties of undefined", "original text kept for the log");
assert(foreign.cause instanceof TypeError, "the original error is kept as the cause");
assert.strictEqual(errors.from(error), error, "PluginErrors pass through unchanged");
assert.strictEqual(errors.from("plain text").details, "plain text");
assert.strictEqual(errors.from(undefined).userMessage, "Something went wrong.");
assert.strictEqual(errors.from(null).code, "unknown");
assert.strictEqual(errors.from({ message: 5 }).details, "5");
assert.strictEqual(errors.from(new Error("x"), Code.STORAGE).code, "storage", "fallback code for foreign errors");
assert.strictEqual(errors.from(error, Code.STORAGE).code, "network", "...but never overrides a PluginError's own");

assert(!errors.isPluginError(new Error("x")) && !errors.isPluginError(null) && !errors.isPluginError({ code: "network" }));

console.log("PluginError tests passed");
