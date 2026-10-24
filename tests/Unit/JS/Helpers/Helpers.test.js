const { assert, createRegistry, loadModule } = require("../../../Helpers/Loader");

const helpers = loadModule("JS/Helpers/Helpers.js", createRegistry());

// resolutionToMs: known resolutions, fallback to the default price resolution
assert.strictEqual(helpers.resolutionToMs("1m"), 60000);
assert.strictEqual(helpers.resolutionToMs("1h"), 3600000);
assert.strictEqual(helpers.resolutionToMs("1d"), 86400000);
assert.strictEqual(helpers.resolutionToMs("bogus"), 3600000, "unknown resolution falls back to 1h");
assert.strictEqual(helpers.resolutionToMs(undefined), 3600000);

// boolValue / pluginDataBool coercion of persisted values
for (const [input, expected] of [
    [true, true],
    ["true", true],
    [1, true],
    ["1", true],
    [false, false],
    ["false", false],
    [0, false],
    ["no", false]
])
    assert.strictEqual(helpers.boolValue(input, !expected), expected, `boolValue(${input})`);
assert.strictEqual(helpers.boolValue(undefined, true), true);
assert.strictEqual(helpers.boolValue("", false), false);
assert.strictEqual(helpers.boolValue(null), false);
assert.strictEqual(helpers.pluginDataBool(undefined), true, "plugin flags default to true");
assert.strictEqual(helpers.pluginDataBool("false"), false);

// formatNumber
assert.strictEqual(helpers.formatNumber(1234567.891), "1,234,567.89");
assert.strictEqual(helpers.formatNumber(0.5, 4), "0.5000");
assert.strictEqual(helpers.formatNumber(NaN), "-");

// inv (1/x), including degenerate input
assert.strictEqual(helpers.inv(4), 0.25);
assert.strictEqual(helpers.inv(0), 0);
assert.strictEqual(helpers.inv(NaN), 0);

// isInverted
const symbols = [{ uid: "A", invert: true }, { uid: "B", invert: "false" }, { uid: "C" }];
assert.strictEqual(helpers.isInverted(symbols, "A"), true);
assert.strictEqual(helpers.isInverted(symbols, "B"), false);
assert.strictEqual(helpers.isInverted(symbols, "C"), false);
assert.strictEqual(helpers.isInverted(symbols, "missing"), false);

// timeAgo
const now = Date.now();
assert.strictEqual(helpers.timeAgo(0), "");
assert.strictEqual(helpers.timeAgo(now - 5000), "5 sec. ago");
assert.strictEqual(helpers.timeAgo(now - 5 * 60000), "5 min. ago");
assert.strictEqual(helpers.timeAgo(now - 3 * 3600000), "3 hr. ago");
assert.strictEqual(helpers.timeAgo(now - 86400000), "1 day ago");
assert.strictEqual(helpers.timeAgo(now - 3 * 86400000), "3 days ago");

// ── Internal symbol handles (UUID) ───────────────────────────────────────────
const uuid = helpers.generateUuid();
assert.strictEqual(typeof uuid, "string");
assert(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(uuid), `version 4 layout: ${uuid}`);
assert.strictEqual(helpers.isUuid(uuid), true);
const many = new Set(Array.from({ length: 5000 }, () => helpers.generateUuid()));
assert.strictEqual(many.size, 5000, "generated ids do not collide");
for (const notUuid of [
    "",
    "abc",
    undefined,
    null,
    5,
    "g1111111-1111-4111-8111-111111111111",
    "11111111-1111-4111-8111-11111111111",
    "EURUSD=X"
])
    assert.strictEqual(helpers.isUuid(notUuid), false, String(notUuid));
assert.strictEqual(helpers.isUuid("11111111-1111-4111-8111-111111111111"), true);
assert.strictEqual(helpers.isUuid(uuid.toUpperCase()), false, "ids are lower case");

// uuidFrom: UUID-shaped, deterministic, different for different text
{
    const first = helpers.uuidFrom("yahoo|EURUSD=X|0");
    assert(helpers.isUuid(first), first);
    assert.strictEqual(helpers.uuidFrom("yahoo|EURUSD=X|0"), first);
    assert.notStrictEqual(helpers.uuidFrom("yahoo|EURUSD=X|1"), first);
    for (let i = 0; i < 200; i++) assert(helpers.isUuid(helpers.uuidFrom(`seed-${i}`)), `seed-${i}`);
    assert.strictEqual(
        new Set(Array.from({ length: 500 }, (_, i) => helpers.uuidFrom(`sym|${i}`))).size,
        500,
        "no collisions in 500"
    );
}
console.log("Helpers tests passed");
