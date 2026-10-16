const { assert, createRegistry, loadModule, srcRoot, listFiles, same } = require("../../../Helpers/Loader");
const fs = require("fs");

// Constant names only (the vm context also exposes JS globals such as `console`).
const constantNames = (module) => Object.keys(module).filter((constantName) => /^[A-Z][A-Z0-9_]*$/.test(constantName) && constantName !== "JSON");

const constants = loadModule("JS/Helpers/Constants.js", createRegistry());

// Shared constants must stay provider-agnostic.
for (const name of constantNames(constants))
    assert(!/^(YAHOO|STOOQ|WISE)_/.test(name), `${name} belongs in its provider's constants file`);

// Fetch plumbing the providers rely on.
same(constants.FETCH_SHELL_COMMAND, ["bash", "-o", "pipefail", "-c"]);
for (const name of ["CURL_CONNECT_TIMEOUT_SECONDS", "CURL_MAX_TIME_SECONDS", "FETCH_USER_AGENT",
                    "PROCESS_NICE_LEVEL", "PROCESS_IONICE_CLASS", "POLL_INTERVAL_MS", "MAX_RETRIES"])
    assert(constants[name] !== undefined, `${name} defined`);
assert.strictEqual(constants.DEFAULT_PRICE_RESOLUTION, "1h");
assert(!/'/.test(constants.FETCH_USER_AGENT), "User agent is embedded in single quotes in the shell script");

// Each provider's constants are self-describing and use only its own prefix.
for (const [folder, prefix] of [["Yahoo", "YAHOO"], ["Stooq", "STOOQ"], ["Wise", "WISE"]]) {
    const providerConstants = loadModule(`JS/Providers/${folder}/${folder}Constants.js`, createRegistry());
    const names = constantNames(providerConstants);
    assert(names.length > 5, `${folder} constants present`);
    for (const name of names) assert(name.startsWith(prefix + "_"), `${name} should start with ${prefix}_`);
    assert.strictEqual(providerConstants[`${prefix}_PROVIDER_ID`], folder.toLowerCase());
    for (const name of names.filter((candidate) => /_URL$/.test(candidate)))
        assert(/^https:\/\//.test(providerConstants[name]), `${name} must use https`);
}

// Every JS file is a stateless library (`.pragma library`) so state is shared per process.
for (const file of listFiles(`${srcRoot}/JS`, /\.js$/))
    assert(/^\s*\.pragma\s+library\s*$/m.test(fs.readFileSync(file, "utf8")), `${file} must be .pragma library`);

console.log("Constants tests passed");
