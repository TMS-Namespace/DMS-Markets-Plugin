const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const os = require("os");
const { spawnSync } = require("child_process");

const repoRoot = path.resolve(__dirname, "..");

function stripQmlJs(source) {
    return source
        .replace(/^\s*\.pragma\s+library\s*$/gm, "")
        .replace(/^\s*\.import\s+"ProviderInterface\.js"\s+as\s+PI\s*$/gm,
                 "var PI = ProviderInterface;")
        .replace(/^\s*\.import\s+"Constants\.js"\s+as\s+Constants\s*$/gm,
                 "var Constants = ConstantsModule;");
}

function loadConstants() {
    const context = { console, Object, JSON, Math, Date };
    const source = stripQmlJs(fs.readFileSync(path.join(repoRoot, "JS", "Constants.js"), "utf8"));
    vm.runInNewContext(source, context, { filename: "Constants.js" });
    return context;
}

function loadProviderInterface() {
    const constants = loadConstants();
    const context = {
        console,
        ConstantsModule: constants,
        Object,
        JSON,
        Math,
        Date,
        parseInt,
        parseFloat,
        isNaN,
        encodeURIComponent
    };
    const source = stripQmlJs(fs.readFileSync(path.join(repoRoot, "JS", "ProviderInterface.js"), "utf8"));
    vm.runInNewContext(source, context, { filename: "ProviderInterface.js" });
    return context;
}

function loadYahooProvider(providerInterface) {
    const constants = loadConstants();
    const context = {
        console,
        ProviderInterface: providerInterface,
        ConstantsModule: constants,
        Object,
        JSON,
        Math,
        Date,
        parseInt,
        parseFloat,
        isNaN,
        encodeURIComponent
    };
    const source = stripQmlJs(fs.readFileSync(path.join(repoRoot, "JS", "YahooProvider.js"), "utf8"));
    vm.runInNewContext(source, context, { filename: "YahooProvider.js" });
}

function loadStooqProvider(providerInterface) {
    const constants = loadConstants();
    const context = {
        console,
        ProviderInterface: providerInterface,
        ConstantsModule: constants,
        Object,
        JSON,
        Math,
        Date,
        parseInt,
        parseFloat,
        isNaN,
        encodeURIComponent
    };
    const source = stripQmlJs(fs.readFileSync(path.join(repoRoot, "JS", "StooqProvider.js"), "utf8"));
    vm.runInNewContext(source, context, { filename: "StooqProvider.js" });
}

function loadProviderBootstrap() {
    const constants = loadConstants();
    const providers = loadProviderInterface();
    const context = {
        console,
        ConstantsModule: constants,
        ProviderInterface: providers,
        Object,
        JSON,
        Math,
        Date,
        parseInt,
        parseFloat,
        isNaN,
        encodeURIComponent
    };
    let source = stripQmlJs(fs.readFileSync(path.join(repoRoot, "JS", "ProviderBootstrap.js"), "utf8"));
    source = source
        .replace(/^\s*\.import\s+"StooqProvider\.js"\s+as\s+StooqProvider\s*$/gm,
                 stripQmlJs(fs.readFileSync(path.join(repoRoot, "JS", "StooqProvider.js"), "utf8")))
        .replace(/^\s*\.import\s+"YahooProvider\.js"\s+as\s+YahooProvider\s*$/gm,
                 stripQmlJs(fs.readFileSync(path.join(repoRoot, "JS", "YahooProvider.js"), "utf8")));
    vm.runInNewContext(source, context, { filename: "ProviderBootstrap.js" });
    return context;
}

function sampleChartResponse() {
    return JSON.stringify({
        chart: {
            result: [{
                meta: { symbol: "EURUSD=X" },
                timestamp: [1767225600, 1767312000, 1767398400],
                indicators: {
                    quote: [{
                        open:   [1.10, 1.11, null],
                        high:   [1.12, 1.13, 1.15],
                        low:    [1.09, 1.10, 1.12],
                        close:  [1.11, 1.12, 1.14],
                        volume: [0, 0, 0]
                    }]
                }
            }],
            error: null
        }
    });
}

function verifyFetchArguments(providers) {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "markets-fetch-test-"));
    try {
        const capture = path.join(tempDir, "curl-arguments");
        const marker = path.join(tempDir, "injected");
        const bashEnv = path.join(tempDir, "mock-curl.bash");
        fs.writeFileSync(bashEnv, `
ionice() { :; }
renice() { :; }
curl() {
    printf '%s\\n' "$@" > "$MARKETS_TEST_CAPTURE"
    while (( $# )); do
        if [[ "$1" == -o ]]; then
            printf 'fixture data\\n' > "$2"
            shift
        fi
        shift
    done
}
`);
        const url = "https://example.test/quote'" + ';touch ' + marker
            + ';#$(touch ' + marker + ')`touch ' + marker + '`';
        for (const providerId of ["yahoo", "stooq"]) {
            const command = providers._buildRequestCommand(providers.getProvider(providerId), url, 0);
            assert.strictEqual(command[0], "bash");
            assert.strictEqual(command[6], url, "URL must be passed as a separate argument");
            const result = spawnSync(command[0], Array.from(command.slice(1)), {
                encoding: "utf8",
                timeout: 5000,
                env: { ...process.env, BASH_ENV: bashEnv, XDG_CACHE_HOME: tempDir,
                       MARKETS_TEST_CAPTURE: capture }
            });
            assert.strictEqual(result.status, 0, result.stderr);
            assert.strictEqual(result.stdout, "fixture data\n");
            assert(fs.readFileSync(capture, "utf8").split("\n").includes(url),
                   "curl must receive the original URL as literal data");
            assert(!fs.existsSync(marker), "URL must never execute as shell code");
        }
    } finally {
        fs.rmSync(tempDir, { recursive: true, force: true });
    }
}

function run() {
    const bootstrap = loadProviderBootstrap();
    assert.strictEqual(bootstrap.ensureProvidersRegistered(), 2,
                       "Provider bootstrap should explicitly register bundled providers");
    assert.strictEqual(bootstrap.ProviderInterface.getDefaultProviderId(), "yahoo",
                       "Yahoo should be the default provider for new symbols");

    const providers = loadProviderInterface();
    loadStooqProvider(providers);
    loadYahooProvider(providers);

    assert(providers.getProviderIds().includes("yahoo"), "Yahoo provider should register itself");
    assert.strictEqual(providers.providerIsDisabled("stooq"), true,
                       "Stooq should remain disabled while its API is unreliable");
    assert.strictEqual(providers.hasRequiredCredential("stooq"), false,
                       "Disabled Stooq provider should not be considered fetchable");
    assert.strictEqual(providers.providerRequiresCredential("yahoo"), false,
                       "Yahoo should not require stored credentials");

    const priceRequest = providers.getPriceRequest("EURUSD=X", "yahoo", "1h");
    assert(priceRequest.url.includes("/v8/finance/chart/EURUSD%3DX"),
           "Yahoo price URL should use encoded chart endpoint symbol");
    assert(priceRequest.url.includes("interval=1h"), "Yahoo price URL should map hourly interval");
    assert(priceRequest.url.includes("range=5d"), "Yahoo hourly price URL should use a valid intraday range");
    assert.strictEqual(JSON.stringify(priceRequest.command.slice(0, 4)),
                       JSON.stringify(["bash", "-o", "pipefail", "-c"]),
                       "Provider request should include a shell command for the fetcher");

    const historyRequest = providers.getHistoryRequest("BZ=F", "yahoo", "1d", 65);
    assert(historyRequest.url.includes("/v8/finance/chart/BZ%3DF"),
           "Yahoo history URL should use encoded chart endpoint symbol");
    assert(historyRequest.url.includes("interval=1d"), "Yahoo daily history URL should use daily candles");
    assert(historyRequest.url.includes("range=6mo"), "Yahoo 65-point daily history URL should use a wider range");
    assert.strictEqual(historyRequest.tailLines, 0, "Yahoo JSON responses must not be tailed");
    assert.strictEqual(historyRequest.command[6], historyRequest.url,
                       "Yahoo command should pass the provider URL separately");

    verifyFetchArguments(providers);

    const stooqRequest = providers.getHistoryRequest("eurusd", "stooq", "1d", 30);
    assert(stooqRequest.command[4].includes("dms-markets-stooq.cookies"),
           "Stooq command should own Stooq cookie handling");
    assert(stooqRequest.command[4].includes("https://stooq.com/__verify"),
           "Stooq command should own Stooq browser verification handling");

    const fetcherSource = fs.readFileSync(path.join(repoRoot, "QML", "Helpers", "MarketDataFetcher.qml"), "utf8");
    assert(!fetcherSource.includes("_buildStooqVerifiedCurlCommand"),
           "MarketDataFetcher must not contain Stooq-specific command builders");
    assert(!fetcherSource.includes("transport"),
           "MarketDataFetcher must not know provider transport concepts");
    assert(!fetcherSource.includes("query1.finance.yahoo.com"),
           "MarketDataFetcher must not contain Yahoo endpoint details");

    const parsed = providers.parseHistoryResponse("yahoo", sampleChartResponse());
    assert.strictEqual(parsed.length, 2, "Yahoo parser should skip incomplete candles");
    assert.strictEqual(JSON.stringify(parsed[0]), JSON.stringify({
        date: "2026-01-01",
        time: "00:00:00",
        open: 1.10,
        high: 1.12,
        low: 1.09,
        close: 1.11,
        volume: 0
    }));
    assert.strictEqual(providers.parsePriceResponse("yahoo", sampleChartResponse()).at(-1).close, 1.12,
                       "Yahoo price parser should return the latest complete candle");
}

run();
console.log("provider tests ok");
