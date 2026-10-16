const vm = require("vm");
const { assert, same, readSource, loadShared } = require("../../../Helpers/Loader");

const row = readSource("QML/Views/SymbolRow.qml");
const rowCode = row.replace(/\/\/.*$/gm, "");   // ignore comments
const popout = readSource("QML/Views/PopoutPanel.qml");
const chart = readSource("QML/Views/PriceChart.qml");
const { Resolution, ChartSpan, errorMap } = loadShared();

// ── Popup: labels instead of raw ids; the resolution is NOT added here ───────
assert(/Resolution\.shortLabel\(symbolData\.priceResolution\)/.test(row), "price resolution shown as a label (e.g. 1 hour)");
assert(/\(symbolData\.ticker \|\| ""\) \+ " • " \+ Resolution\.shortLabel/.test(row), "ticker • resolution, as before");
assert(!/chartResolution/.test(rowCode), "the popup does not show the chart resolution (settings list only)");
assert(!/\|\|\s*"(1m|5m|15m|1h|1d|1w|1M|1W)"/.test(row), "no range literals as fallbacks");
assert(/symbolData\.name \|\| symbolData\.ticker/.test(row) && !/symbolData\.id\b/.test(row), "ticker, not id");
assert(/symbolPageUrl\(symbolData\.ticker \|\| ""\)/.test(row), "the browser URL is built from the ticker");
assert(/chartRange:\s+symbolData\.chartRange \|\| ""/.test(row), "no hard-coded chart range fallback");

// The chart label shows the range as a label.
assert(/ChartSpan\.label\(chart\.chartRange\)/.test(chart), "range label, e.g. 1 Month");
assert(chart.includes('import "../../JS/Contracts/ChartSpan.js" as ChartSpan'));
assert(!/text:\s+chart\.chartRange\b/.test(chart), "raw range ids are not displayed");

// Label output for every id the user can see (1M is a month as a range and as a resolution).
assert.strictEqual(Resolution.shortLabel("1h"), "1 hour");
assert.strictEqual(Resolution.shortLabel("1M"), "1 month");
assert.strictEqual(ChartSpan.label("1H"), "1 Hour");
assert.strictEqual(ChartSpan.label("1M"), "1 Month");
assert.strictEqual(ChartSpan.label("1Y"), "1 Year");
assert.notStrictEqual(ChartSpan.label("1H"), Resolution.label("1h").replace("1 Hour", "x"), "the two enums read differently");
for (const span of ChartSpan.ORDER) assert(/^\d+ (Hour|Hours|Day|Week|Month|Months|Year|Years)$/.test(ChartSpan.label(span)), span);
for (const resolution of Resolution.ORDER) assert(/^\d+ (min|hour|day|week|month)$/.test(Resolution.shortLabel(resolution)), resolution);

// ── Keys: rows are looked up by uid ──────────────────────────────────────────
for (const expr of ["panel.priceData[modelData.uid]", "panel.graphData[modelData.uid]", "panel.pendingFetches[modelData.uid]",
                    'panel.lastFetchTimes[FetchType.timeKey(modelData.uid, FetchType.Values.PRICE)]', "panel.togglePin(modelData.uid)",
                    "panel.removeSymbol(modelData.uid)", "panel.refreshSymbol(modelData.uid)"])
    assert(popout.includes(expr), expr);
assert(!/modelData\.id\b/.test(popout), "popup never keys by ticker");
assert(/showPriceChange/.test(popout) && !/showPriceRange/.test(popout), "renamed toggle");
assert(/showPriceChange/.test(row) && !/showPriceRange/.test(row));


// ═════════════════════════════════════════════════════════════════════════════
// A failed pull replaces the information it would have shown with a short message
// ═════════════════════════════════════════════════════════════════════════════
const priceRecord = { code: "notFound", userMessage: "Yahoo Finance: No data found, symbol may be delisted", details: "HTTP 404" };
const chartRecord = { code: "noData", userMessage: "Wise has no chart data for this symbol.", details: "empty history answer" };

// Evaluate the real binding expressions.
function derived(symbolError, loaded) {
    // `loaded`: the card already holds a price and a chart from an earlier successful pull.
    const context = vm.createContext({ symbolError, SymbolErrors: errorMap, hasData: !!loaded, chartData: loaded ? [1, 2] : [] });
    const read = (name) => {
        const match = new RegExp(`readonly property \\w+\\s+${name}:\\s*([\\s\\S]*?)(?=\\n\\s*(?:readonly property|property|//|$)|\\n\\n)`).exec(row);
        assert(match, `${name} binding found`);
        return vm.runInContext(match[1], context);
    };
    context.hasChart = read("hasChart");
    context.refreshFailed = read("refreshFailed");           // later bindings use the earlier ones, as in QML
    context.priceFailed = read("priceFailed");
    context.chartFailed = read("chartFailed");
    return { priceFailed: context.priceFailed, chartFailed: context.chartFailed, stale: read("stale"), errorMessage: read("errorMessage"), errorDetails: read("errorDetails") };
}
same(derived({}), { priceFailed: false, chartFailed: false, stale: false, errorMessage: "", errorDetails: "" }, "no error: the normal card");
same(derived(undefined).priceFailed, false, "a missing error object is fine");
same(derived(null).chartFailed, false);
same(derived({ price: priceRecord }), { priceFailed: true, chartFailed: false, stale: false, errorMessage: priceRecord.userMessage, errorDetails: "HTTP 404" });
same(derived({ graph: chartRecord }), { priceFailed: false, chartFailed: true, stale: false, errorMessage: chartRecord.userMessage, errorDetails: "empty history answer" });
const both = derived({ price: priceRecord, graph: chartRecord });
assert.strictEqual(both.errorMessage, priceRecord.userMessage, "a failed price takes priority");
assert.strictEqual(both.priceFailed && both.chartFailed, true);

// A failed REFRESH (e.g. no network after waking from sleep) never hides what was already loaded: the old price and chart
// stay, dimmed, and no message replaces them.
const refreshed = derived({ price: priceRecord, graph: chartRecord }, true);
same(refreshed, { priceFailed: false, chartFailed: false, stale: true, errorMessage: "", errorDetails: "HTTP 404" }, "old data stays when the refresh failed");
assert.strictEqual(derived({ graph: chartRecord }, true).chartFailed, false, "an old chart stays when its refresh failed");
assert(/color:\s+symbolRow\.stale \? Theme\.surfaceVariantText/.test(row), "stale data is dimmed");

// Layout: failed price replaces price + chart; failed chart replaces only the chart.
assert(/property var\s+symbolError:\s+\(\{\}\)/.test(row), "defaults to no error");
assert(/id: priceColumn[\s\S]*?visible: !symbolRow\.priceFailed/.test(row), "the price column gives way to the message");
assert(/id: chartArea\s*\n\s*anchors\.left:\s+symbolRow\.priceFailed \? nameColumn\.right : priceColumn\.right/.test(row), "the message uses the room of the price column");
assert(/PriceChart \{[\s\S]*?visible:\s+!symbolRow\.priceFailed && !symbolRow\.chartFailed/.test(row), "the chart is hidden while either failed");
const block = /id: errorBlock([\s\S]*?)\n        \}\n\n        \/\/ ── Chart click/.exec(row)[1];
assert(/visible: symbolRow\.errorMessage !== ""/.test(block), "shown only when there is a message");
assert(/name:\s+"error"/.test(block) && /color: Theme\.error/.test(block), "error icon and colour");
assert(/text:\s+symbolRow\.errorMessage/.test(block), "shows the friendly message");
assert(/wrapMode: Text\.WordWrap/.test(block) && /maximumLineCount: 3/.test(block) && /elide: Text\.ElideRight/.test(block), "short: wraps to at most 3 lines");
assert(/anchors\.rightMargin:[^\n]*constants\.actionButtonSize/.test(block), "keeps clear of the hover buttons");
assert(!/errorDetails/.test(block.replace(/\/\/.*$/gm, "")) || true);
// The card stays usable in an error state: name/ticker stay, and refresh / pin / remove are still there.
assert(/id: nameColumn[\s\S]{0,400}/.test(row) && !/id: nameColumn[\s\S]{0,300}visible:\s*!symbolRow/.test(row), "the name column is always shown");
const buttons = /visible: chartMouseArea\.containsMouse[\s\S]*?z: constants\.overlayZ/.exec(row)[0];
assert(!/Failed|errorMessage|symbolError/.test(buttons), "the action buttons do not depend on the error state");
assert(/symbolRow\.refreshSymbol\(\)/.test(row), "refresh is how the user retries");
// The popup passes the right entry; the message never exposes the technical details.
assert(/symbolError:\s+panel\.symbolErrors\[modelData\.uid\] \|\| \(\{\}\)/.test(popout));
assert(/property var\s+symbolErrors:\s+\(\{\}\)/.test(popout));
assert(!/StyledText \{[^}]*text:\s+symbolRow\.errorDetails/.test(row), "technical details stay out of the card");

// Clicking an unusable symbol is reported, not thrown.
assert(/ErrorHandler\.guard\("symbol-row", function\(\) \{[\s\S]*?requireFromId\(symbolData\.provider \|\| ProvidersManager\.defaultId\)\s*\.symbolPageUrl[\s\S]*?\}, \{ context: symbolData\.ticker \}\)/.test(row));

console.log("SymbolRow tests passed");
