const fs = require("fs");
const path = require("path");
const { assert, repoRoot, srcRoot } = require("../Helpers/Loader");

const manifest = JSON.parse(fs.readFileSync(path.join(repoRoot, "plugin.json"), "utf8"));

for (const key of ["id", "name", "version", "component", "settings", "permissions", "dependencies", "repo"])
    assert(manifest[key] !== undefined, `plugin.json.${key}`);
assert(/^\d+\.\d+\.\d+$/.test(manifest.version), "semantic version");
for (const key of ["component", "settings"]) {
    const file = path.resolve(repoRoot, manifest[key]);
    assert(file.startsWith(srcRoot), `${key} lives under src/`);
    assert(fs.existsSync(file), `${key} file exists: ${manifest[key]}`);
}
// Fetching is done by curl in bash; the permissions must cover it and nothing more.
assert.strictEqual(JSON.stringify(manifest.dependencies.slice().sort()), JSON.stringify(["bash", "curl"]));
assert(manifest.permissions.includes("network") && manifest.permissions.includes("process"));

// The version is documented in the README changelog.
const readme = fs.readFileSync(path.join(repoRoot, "README.md"), "utf8");
assert(readme.includes(`- v${manifest.version} :`), `README changelog mentions v${manifest.version}`);

// The bundled screenshot / setup script exist.
assert(fs.existsSync(path.join(repoRoot, "support", "setup-symlink.sh")));

console.log("plugin.json tests passed");

for (const match of readme.matchAll(/(?:chmod \+x )?([Ss]upport\/setup-symlink\.sh)/g))
    assert(fs.existsSync(path.join(repoRoot, match[1])), `documented install script exists: ${match[1]}`);
const screenshotPath = new URL(manifest.screenshot).pathname.split("/raw/main/")[1];
assert(screenshotPath && fs.existsSync(path.join(repoRoot, screenshotPath)), "manifest screenshot points to a bundled image");
