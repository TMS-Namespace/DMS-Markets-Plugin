// Candle timestamps are UTC, whatever time zone the machine is in.
const { spawnSync } = require("child_process");
const path = require("path");
const { assert, same } = require("../../../../Helpers/Loader");

const probe = `
const { loadShared } = require(${JSON.stringify(path.resolve(__dirname, "../../../../Helpers/Loader"))});
const { yahoo } = loadShared();
const text = JSON.stringify({ chart: { result: [{ timestamp: [1767225600, 1767268800, 1782864000], indicators: { quote: [{
    open: [1, 1, 1], high: [1, 1, 1], low: [1, 1, 1], close: [1, 1, 1], volume: [0, 0, 0] }] } }] } });
console.log(JSON.stringify(yahoo.parseHistory(text).map((candle) => candle.date + " " + candle.time)));`;
for (const zone of ["UTC", "Asia/Kolkata", "America/Sao_Paulo", "Pacific/Kiritimati", "America/St_Johns"]) {
    const result = spawnSync(process.execPath, ["-e", probe], { encoding: "utf8", env: { ...process.env, TZ: zone } });
    assert.strictEqual(result.status, 0, result.stderr);
    same(
        JSON.parse(result.stdout),
        ["2026-01-01 00:00:00", "2026-01-01 12:00:00", "2026-07-01 00:00:00"],
        `UTC dates under ${zone}`
    );
}
console.log("Yahoo UTC tests passed");
