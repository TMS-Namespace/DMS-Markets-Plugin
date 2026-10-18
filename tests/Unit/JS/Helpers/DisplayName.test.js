// The display name of a symbol: 1 to 10 characters; letters, digits and - + * / \ . ~ % $ ^ _ ? ! # ( ) [ ] =
const { assert, loadModule } = require("../../../Helpers/Loader");
const Rules = loadModule("JS/Helpers/SymbolRules.js", new Map());
const Constants = loadModule("JS/Helpers/Constants.js", new Map());

assert.strictEqual(Constants.DISPLAY_NAME_MAX_LENGTH, 10);
const ok = (name) => assert.strictEqual(Rules.validateName(name).valid, true, `accepted: ${name}`);
const bad = (name, fragment) => {
    const verdict = Rules.validateName(name);
    assert.strictEqual(verdict.valid, false, `refused: ${JSON.stringify(name)}`);
    assert(
        verdict.message.length > 0 && (!fragment || verdict.message.includes(fragment)),
        `${JSON.stringify(name)}: ${verdict.message}`
    );
};

// Letters, digits and spaces, one to ten of them.
["A", "Gold", "Euro Usd", "S P 500", "a b", "EURUSD", "S500", "abcDEF0123", "0123456789"].forEach(ok);
// Every allowed special character, each on its own and inside a name.
"-+*/\\.~%$^_?!#()[]=".split("").forEach((character) => {
    ok(character);
    ok(`A${character}B`);
});
["EUR/USD", "BRL-PLN", "S&P", "S&P 500", "AT&T", "&", "DX-Y.NYB", "A_B", "(Gold)", "[HG]=F", "100%", "C\\D"].forEach(
    ok
);
// Ten is the longest.
ok("1234567890");
bad("12345678901", "at most 10");
bad("A very long name", "at most 10");
// Empty and not text.
bad("", "Enter");
bad(undefined, "Enter");
bad(null, "Enter");
bad(5, "Enter");
// Everything else is refused, including the characters a shell or URL treats specially.
// Spaces are fine inside and around, but a name of only spaces is no name.
ok("Gold ");
ok(" Gold");
bad("   ", "Enter");
bad(" ", "Enter");
for (const character of ["'", '"', "`", ";", "|", "<", ">", "{", "}", "@", ",", ":", "\t", "\n", "é", "€", "日"])
    bad(`A${character}B`, "letters, digits");
// The message names the allowed characters.
assert(
    Rules.validateName("a;b").message.includes("letters, digits, spaces and & - + * / \\ . ~ % $ ^ _ ? ! # ( ) [ ] =")
);
// The pattern is the one constant (no second copy of the rule).
assert.strictEqual(new RegExp(Constants.DISPLAY_NAME_PATTERN).test("Gold"), true);

console.log("DisplayName tests passed");
