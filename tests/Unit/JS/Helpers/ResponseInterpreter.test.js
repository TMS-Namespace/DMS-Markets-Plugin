const { assert, same, loadShared, throwsWith } = require("../../../Helpers/Loader");

const { interpreter, errors, yahoo, wise } = loadShared();
const envelope = (curl, status, body = "") => `${interpreter.ENVELOPE_PREFIX} ${curl} ${status}\n${body}`;
const run = (stdout, extra = {}, hooks = {}, exitCode = 0) =>
    interpreter.fromProcess("wise", "Wise", Object.assign({ exitCode, stdout, stderr: "" }, extra), hooks);

// ── The contract object ──────────────────────────────────────────────────────
const good = interpreter.success("wise", 200, '{"a":1}');
same(
    { ok: good.ok, status: good.status, body: good.body, error: good.error, providerId: good.providerId },
    { ok: true, status: 200, body: '{"a":1}', error: null, providerId: "wise" }
);
const bad = interpreter.failure("wise", new errors.PluginError("http", "Nope.", "d", { status: 418 }), 0, "body");
assert.strictEqual(bad.ok, false);
assert.strictEqual(bad.status, 418, "the status of the error is used when none is given");
assert.strictEqual(bad.error.userMessage, "Nope.");
assert.strictEqual(
    interpreter.failure("wise", new Error("raw"), 0, null).error.userMessage,
    "Something went wrong.",
    "foreign errors are wrapped"
);
assert.strictEqual(interpreter.failure("wise", "text").body, "");
assert.strictEqual(interpreter.success("wise", 0, undefined).status, 200);
assert.strictEqual(interpreter.assertOk(good), good);
assert.throws(
    () => interpreter.assertOk(bad),
    (thrown) => thrown === bad.error,
    "assertOk rethrows the response's error"
);
throwsWith(
    () => interpreter.assertOk("not a response"),
    "provider response is required",
    "contract violations are errors"
);

// ── Envelope ─────────────────────────────────────────────────────────────────
same(interpreter.parseEnvelope(envelope(0, 200, '{"x":1}\nline2')), {
    hasEnvelope: true,
    curlExit: 0,
    status: 200,
    body: '{"x":1}\nline2'
});
same(
    interpreter.parseEnvelope(envelope(6, "000")),
    { hasEnvelope: true, curlExit: 6, status: 0, body: "" },
    "000 = no HTTP answer"
);
same(
    interpreter.parseEnvelope(`${interpreter.ENVELOPE_PREFIX} 0 \nbody`),
    { hasEnvelope: true, curlExit: 0, status: 0, body: "body" },
    "empty status"
);
same(interpreter.parseEnvelope(`${interpreter.ENVELOPE_PREFIX} 0 200\r\nbody`).body, "body", "CRLF tolerated");
same(
    interpreter.parseEnvelope("just a body"),
    { hasEnvelope: false, curlExit: 0, status: 0, body: "just a body" },
    "custom scripts have none"
);
for (const notEnvelope of [
    "",
    undefined,
    null,
    "MARKETS-RESPONSE x y\nb",
    "markets-response 0 200\nb",
    " MARKETS-RESPONSE 0 200\nb"
])
    assert.strictEqual(interpreter.parseEnvelope(notEnvelope).hasEnvelope, false, JSON.stringify(notEnvelope));
assert.strictEqual(interpreter.parseEnvelope(null).body, "");
// A body that merely contains the prefix later is not mistaken for an envelope.
assert.strictEqual(interpreter.parseEnvelope(`data\n${interpreter.ENVELOPE_PREFIX} 0 200\n`).hasEnvelope, false);

// ── Success paths ────────────────────────────────────────────────────────────
for (const status of [200, 201, 204, 299]) {
    const response = run(envelope(0, status, "payload"));
    assert.strictEqual(response.ok, true, `HTTP ${status}`);
    assert.strictEqual(response.status, status);
    assert.strictEqual(response.body, "payload");
}
const plain = run("body without envelope");
assert.strictEqual(plain.ok, true, "a custom script's output is the body");
assert.strictEqual(plain.status, 200);

// ── Process-level failures ───────────────────────────────────────────────────
for (const exit of [127, 126, -1]) {
    const response = run("", { stderr: "bash: curl: command not found" }, {}, exit);
    assert.strictEqual(response.error.code, "process", `exit ${exit}`);
    assert.strictEqual(response.error.userMessage, "Couldn't run curl. Make sure curl and bash are installed.");
    assert.strictEqual(response.error.retryable, false);
    assert(/command not found/.test(response.error.details), "stderr goes to the details");
    assert(/process exit/.test(response.error.details));
}
assert.strictEqual(run("", {}, {}, 2).error.code, "network", "any other script failure");
assert.strictEqual(interpreter.fromProcess("wise", "Wise", undefined).error.code, "process", "no result at all");
assert.strictEqual(interpreter.fromProcess("wise", "Wise", { exitCode: "x", stdout: 5 }).ok, false);

// ── curl exit codes ──────────────────────────────────────────────────────────
for (const [exit, code, retry, text] of [
    [6, "network", true, "Can't reach Wise. Check your internet connection."],
    [7, "network", true, "Can't reach Wise. Check your internet connection."],
    [52, "network", true, "Can't reach Wise."],
    [55, "network", true, "Can't reach Wise."],
    [56, "network", true, "Can't reach Wise."],
    [5, "network", true, "Can't reach Wise."],
    [28, "timeout", true, "Wise took too long to answer."],
    [35, "network", false, "Couldn't make a secure connection to Wise."],
    [60, "network", false, "secure connection"],
    [51, "network", false, "secure connection"],
    [22, "http", false, "Wise returned an error."],
    [3, "network", false, "The request to Wise failed."],
    [99, "network", false, "failed"]
]) {
    const response = run(envelope(exit, "000"), { stderr: `curl: (${exit}) message` });
    assert.strictEqual(response.ok, false, `curl ${exit}`);
    assert.strictEqual(response.error.code, code, `curl ${exit} code`);
    assert.strictEqual(response.error.retryable, retry, `curl ${exit} retryable`);
    assert(response.error.userMessage.includes(text), `curl ${exit}: ${response.error.userMessage}`);
    assert(
        response.error.details.includes(`curl exit ${exit}`) && response.error.details.includes("message"),
        "details carry the technical facts"
    );
}

// ── HTTP statuses ────────────────────────────────────────────────────────────
for (const [status, code, retry, text] of [
    [429, "rateLimited", true, "Wise is limiting requests"],
    [500, "http", true, "Wise is having problems (HTTP 500)"],
    [502, "http", true, "HTTP 502"],
    [503, "http", true, "HTTP 503"],
    [599, "http", true, "HTTP 599"],
    [401, "credential", false, "Wise refused access (HTTP 401)"],
    [403, "credential", false, "HTTP 403"],
    [404, "notFound", false, "Wise doesn't know this symbol."],
    [400, "http", false, "Wise rejected the request (HTTP 400)"],
    [422, "http", false, "HTTP 422"],
    [418, "http", false, "HTTP 418"],
    [301, "http", false, "Wise answered with HTTP 301"]
]) {
    const response = run(envelope(0, status, "<html>error page</html>"));
    assert.strictEqual(response.ok, false, `HTTP ${status}`);
    assert.strictEqual(response.status, status);
    assert.strictEqual(response.error.code, code, `HTTP ${status} code`);
    assert.strictEqual(response.error.retryable, retry, `HTTP ${status} retryable`);
    assert(response.error.userMessage.includes(text), `HTTP ${status}: ${response.error.userMessage}`);
    assert.strictEqual(response.error.status, status);
    assert(
        response.error.details.includes(`HTTP ${status}`) && response.error.details.includes("error page"),
        "details carry status and a body snippet"
    );
    assert.strictEqual(response.body, "<html>error page</html>", "the body is kept on the response");
}

// ── The web API's own message ────────────────────────────────────────────────
const api = { extractApiError: (status, body) => (body.indexOf("{") === 0 ? JSON.parse(body).message : "") };
assert(
    run(envelope(0, 404, '{"message":"No data found, symbol may be delisted"}'), {}, api).error.userMessage.includes(
        "No data found, symbol may be delisted"
    ),
    "404 with an API message"
);
assert.strictEqual(
    run(envelope(0, 404, '{"message":"No data found, symbol may be delisted"}'), {}, api).error.userMessage,
    "Wise: No data found, symbol may be delisted"
);
assert.strictEqual(run(envelope(0, 400, '{"message":"bad range"}'), {}, api).error.userMessage, "Wise: bad range");
assert.strictEqual(
    run(envelope(0, 404, "not json"), {}, { extractApiError: () => "" }).error.userMessage,
    "Wise doesn't know this symbol.",
    "no message → friendly default"
);
assert(
    run(envelope(0, 400, '{"message":"' + "x".repeat(500) + '"}'), {}, api).error.userMessage.length <= 140,
    "user messages stay short"
);
assert(run(envelope(0, 400, "y".repeat(5000))).error.details.length < 500, "details keep only a snippet of the body");
assert.strictEqual(
    run(envelope(0, 500, '{"message":"internal"}'), {}, api).error.userMessage,
    "Wise is having problems (HTTP 500).",
    "5xx keeps the standard wording"
);
// Errors reported inside a 2xx answer.
const embedded = run(envelope(0, 200, '{"message":"quota exceeded"}'), {}, api);
assert.strictEqual(embedded.ok, false);
assert.strictEqual(embedded.error.userMessage, "Wise: quota exceeded");
assert.strictEqual(embedded.status, 200);
assert.strictEqual(run(envelope(0, 200, '{"fine":true}'), {}, { extractApiError: () => "" }).ok, true);

// ── Credentials and empty answers ────────────────────────────────────────────
const credentialResponse = run(
    "Get your apikey at https://x",
    {},
    { credentialSentinel: "get your apikey", authErrorMessage: "Stooq API key missing or invalid" }
);
assert.strictEqual(credentialResponse.error.code, "credential");
assert.strictEqual(credentialResponse.error.userMessage, "Stooq API key missing or invalid");
assert.strictEqual(
    run(envelope(0, 200, "GET YOUR APIKEY now"), {}, { credentialSentinel: "get your apikey" }).error.code,
    "credential",
    "case-insensitive"
);
assert.strictEqual(
    run(envelope(0, 200, "prefix Get your apikey"), {}, { credentialSentinel: "get your apikey" }).ok,
    true,
    "only at the start"
);
for (const empty of ["", "   \n  ", envelope(0, 200, ""), envelope(0, 200, "\n\n")]) {
    const response = run(empty);
    assert.strictEqual(response.error.code, "noData", JSON.stringify(empty));
    assert.strictEqual(response.error.userMessage, "Wise returned an empty answer.");
    assert.strictEqual(response.error.retryable, false);
}

// ── With the real providers' hooks ───────────────────────────────────────────
const yahooHooks = { extractApiError: yahoo.extractApiError },
    wiseHooks = { extractApiError: wise.extractApiError };
const yahooNotFound = JSON.stringify({
    chart: { result: null, error: { code: "Not Found", description: "No data found, symbol may be delisted" } }
});
const yahooResponse = interpreter.fromProcess(
    "yahoo",
    "Yahoo Finance",
    { exitCode: 0, stdout: envelope(0, 404, yahooNotFound), stderr: "" },
    yahooHooks
);
assert.strictEqual(yahooResponse.ok, false);
assert.strictEqual(yahooResponse.error.code, "notFound");
assert.strictEqual(
    yahooResponse.error.userMessage,
    "Yahoo Finance: No data found, symbol may be delisted",
    "Yahoo's own message"
);
const yahooEmbedded = interpreter.fromProcess(
    "yahoo",
    "Yahoo Finance",
    { exitCode: 0, stdout: envelope(0, 200, yahooNotFound), stderr: "" },
    yahooHooks
);
assert.strictEqual(yahooEmbedded.ok, false, "Yahoo error inside a 200 answer");
const wiseResponse = interpreter.fromProcess(
    "wise",
    "Wise",
    { exitCode: 0, stdout: envelope(0, 400, '{"message":"Invalid currency pair"}'), stderr: "" },
    wiseHooks
);
assert.strictEqual(wiseResponse.error.userMessage, "Wise: Invalid currency pair", "Wise's own message");
assert.strictEqual(
    interpreter.fromProcess(
        "yahoo",
        "Yahoo Finance",
        { exitCode: 0, stdout: envelope(0, 200, '{"chart":{"result":[{}],"error":null}}'), stderr: "" },
        yahooHooks
    ).ok,
    true
);

console.log("ResponseInterpreter tests passed");
