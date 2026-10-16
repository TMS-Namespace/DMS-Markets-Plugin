// Everything the plugin stores or compares is UTC; nothing is converted to the
// user's local time zone (only the "… ago" labels, which are relative anyway).
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const { assert, same, srcRoot, listFiles } = require("../../../Helpers/Loader");

// ── Static: no local-time APIs anywhere in the sources ───────────────────────
const forbidden = [
    [/\.get(Hours|Minutes|Seconds|Date|Day|Month|FullYear|TimezoneOffset)\(/, "local-time getter (use getUTC*)"],
    [/\.set(Hours|Minutes|Seconds|Date|Month|FullYear)\(/, "local-time setter"],
    [/\.toLocale\w*\(/, "locale formatting"],
    [/Qt\.formatDate(Time)?\(|Qt\.formatTime\(/, "Qt local date formatting"],
    [/Intl\./, "Intl formatting"],
    [/new Date\(\s*[^()]+,[^()]+\)/, "Date constructor with components is local time (use Date.UTC)"],
    [/\.toString\(\)\s*\/\/.*date/i, "date toString is local time"]
];
for (const file of [...listFiles(srcRoot, /\.(js|qml)$/)]) {
    const code = fs.readFileSync(file, "utf8").replace(/\/\/.*$/gm, "").replace(/\/\*[\s\S]*?\*\//g, "");
    for (const [pattern, why] of forbidden)
        assert(!pattern.test(code), `${path.relative(srcRoot, file)}: ${why}`);
}
// The fetcher compares nothing by local time: it only uses epoch milliseconds (Date.now()).
const fetcher = fs.readFileSync(path.join(srcRoot, "QML/Helpers/MarketDataFetcher.qml"), "utf8");
assert(!/Date\.parse|new Date/.test(fetcher.replace(/\/\/.*$/gm, "")), "the fetcher does no date parsing");

// ── Dynamic: parsers produce the same UTC strings whatever the machine's zone ─
const probe = `
const { loadShared } = require(${JSON.stringify(path.resolve(__dirname, "../../../Helpers/Loader"))});
const { yahoo: yahooApi, wise: wiseApi } = loadShared();
const yahoo = JSON.stringify({ chart: { result: [{ timestamp: [1767225600, 1767268800], indicators: { quote: [{
    open: [1, 1], high: [1, 1], low: [1, 1], close: [1, 1], volume: [0, 0] }] } }] } });
const wise = JSON.stringify([{ value: 1, time: Date.UTC(2026, 0, 1, 23, 30, 5) }, { value: 2, time: Date.UTC(2026, 5, 30, 0, 0, 0) }]);
const stamp = (candle) => candle.date + " " + candle.time;
console.log(JSON.stringify({
    yahoo: yahooApi.parseHistory(yahoo).map(stamp),
    wise: wiseApi.parseHistory(wise).map(stamp),
    offset: new Date().getTimezoneOffset()
}));`;
const expected = {
    yahoo: ["2026-01-01 00:00:00", "2026-01-01 12:00:00"],
    wise: ["2026-01-01 23:30:05", "2026-06-30 00:00:00"]
};
const offsets = new Set();
for (const zone of ["UTC", "Asia/Kolkata", "America/Sao_Paulo", "Pacific/Auckland", "Pacific/Kiritimati", "America/St_Johns"]) {
    const result = spawnSync(process.execPath, ["-e", probe], { encoding: "utf8", env: { ...process.env, TZ: zone } });
    assert.strictEqual(result.status, 0, result.stderr);
    const probeOutput = JSON.parse(result.stdout);
    offsets.add(probeOutput.offset);
    same({ yahoo: probeOutput.yahoo, wise: probeOutput.wise }, expected, `UTC output in zone ${zone}`);
}
assert(offsets.size > 3, "the probe really ran under different local time zones");

// ── Contract: documented in the provider interface ───────────────────────────
const contract = fs.readFileSync(path.join(srcRoot, "JS/Helpers/SeriesRules.js"), "utf8");
assert(/date\s+"YYYY-MM-DD"\s+UTC/.test(contract) && /time\s+"HH:MM:SS" or ""\s+UTC/.test(contract), "SeriesRules documents UTC candles");

console.log("UTC tests passed");
