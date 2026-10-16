// Candle timestamps are UTC, whatever time zone the machine is in (Wise finding 7).
const { spawnSync } = require("child_process");
const path = require("path");
const { assert, same } = require("../../../../Helpers/Loader");

const probe = `
const { loadShared } = require(${JSON.stringify(path.resolve(__dirname, "../../../../Helpers/Loader"))});
const wise = loadShared().wise;
const rows = [{ value: 1, time: Date.UTC(2026, 0, 1, 23, 30, 5) }, { value: 2, time: Date.UTC(2026, 11, 31, 0, 0, 0) }];
console.log(JSON.stringify(wise.parseHistory(JSON.stringify(rows)).map((candle) => candle.date + " " + candle.time)));`;
for (const zone of ["UTC", "Asia/Kolkata", "America/Sao_Paulo", "Pacific/Kiritimati", "America/St_Johns"]) {
    const result = spawnSync(process.execPath, ["-e", probe], { encoding: "utf8", env: { ...process.env, TZ: zone } });
    assert.strictEqual(result.status, 0, result.stderr);
    same(JSON.parse(result.stdout), ["2026-01-01 23:30:05", "2026-12-31 00:00:00"], `UTC dates under ${zone}`);
}
console.log("Wise UTC tests passed");
