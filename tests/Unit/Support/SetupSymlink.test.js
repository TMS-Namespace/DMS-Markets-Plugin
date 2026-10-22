// SetupSymlink.test.js - installation respects XDG_CONFIG_HOME and keeps the host's dms plugin path.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const repository = path.resolve(__dirname, "../../..");
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "markets-install-"));
try {
    for (const configHome of [path.join(temporary, "custom config"), ""]) {
        const home = path.join(temporary, "home");
        const result = spawnSync("bash", [path.join(repository, "support/setup-symlink.sh")], {
            encoding: "utf8",
            env: { ...process.env, HOME: home, XDG_CONFIG_HOME: configHome }
        });
        assert.equal(result.status, 0, result.stderr);
        const installed = path.join(configHome || path.join(home, ".config"), "dms/plugins/MarketsPlugin");
        assert.equal(fs.readlinkSync(installed), repository);
    }
} finally {
    fs.rmSync(temporary, { recursive: true, force: true });
}
console.log("Dux installation path tests passed");
