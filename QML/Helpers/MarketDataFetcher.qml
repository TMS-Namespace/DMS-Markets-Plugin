// MarketDataFetcher.qml — Data-fetching engine for the Markets plugin
//
// Encapsulates all network I/O: polling timer, retry queue, curl Process
// instances, incremental graph merge, and response parsing.
// Widget.qml owns the state (priceData / graphData / …) and passes them in
// as read/write properties; this item mutates them via the parent bindings.
//
// Signals emitted after each successful parse allow Widget.qml to react
// without knowing the fetch internals.

import QtQuick
import Quickshell
import Quickshell.Io
import "../../JS/ProviderInterface.js" as Providers
import "../../JS/Helpers.js" as Helpers
import "../../JS/Constants.js" as JsK

Item {

    // ── QML constants ─────────────────────────────────────────────────────────
    Constants { id: c }

    // ── Inputs (bound from Widget.qml) ────────────────────────────────────────
    property string apiKey:              ""
    property var    symbols:             []
    property var    priceData:           ({})
    property var    graphData:           ({})
    property var    lastFetchTimes:      ({})
    property var    _pendingFetches:     ({})
    property var    _lastFullGraphFetch: ({})
    property int    _activeFetchCount:   0
    property var    _fetchQueue:         []
    property var    _queuedFetchKeys:    ({})

    onApiKeyChanged: {
        // Only push the key into the provider registry when it is valid;
        // clear it when the key is removed or invalid to stop active fetches.
        if (Helpers.isValidApiKey(apiKey))
            Providers.setApiKey(c.stooqProviderId, apiKey)
        else
            Providers.setApiKey(c.stooqProviderId, "")
    }
    Component.onCompleted: {
        if (Helpers.isValidApiKey(apiKey))
            Providers.setApiKey(c.stooqProviderId, apiKey)
    }

    // ── Signals ───────────────────────────────────────────────────────────────
    // Emit updated copies so Widget.qml can assign them back to its properties.
    signal priceDataReady(var newPriceData)
    signal graphDataReady(var newGraphData)
    signal fetchTimesUpdated(var newTimes)
    signal pendingFetchesUpdated(var newPending)
    signal fullGraphFetchUpdated(var newFullFetch)
    signal tokenError(string message)

    // ── Polling timer ─────────────────────────────────────────────────────────
    Timer {
        id: checkTimer
        interval: JsK.POLL_INTERVAL_MS
        running: symbols.length > 0 && apiKey !== ""
        repeat: true
        onTriggered: _checkAndFetch()
    }

    function _checkAndFetch() {
        var now      = Date.now()
        var newTimes = {}
        for (var key in lastFetchTimes)
            newTimes[key] = lastFetchTimes[key]

        for (var i = 0; i < symbols.length; i++) {
            var symbol = symbols[i]

            var priceKey      = symbol.id + "_price"
            var lastPriceTime = newTimes[priceKey] || 0
            var priceRefresh  = Helpers.intervalToMs(symbol.priceInterval)
            if (now - lastPriceTime >= priceRefresh) {
                doFetch(symbol, "price")
                newTimes[priceKey] = now
            }

            var graphKey      = symbol.id + "_graph"
            var lastGraphTime = newTimes[graphKey] || 0
            var histConfig    = Providers.getHistoryConfig(symbol.graphInterval)
            if (now - lastGraphTime >= histConfig.refreshMs) {
                var lastFull = _lastFullGraphFetch[symbol.id] || 0
                var existing = graphData[symbol.id]

                if (!existing || existing.length === 0 || now - lastFull >= JsK.FULL_GRAPH_REFRESH_MS) {
                    doFetch(symbol, "graph")
                } else {
                    _mergeLatestIntoGraph(symbol)
                }
                newTimes[graphKey] = now
            }
        }
        fetchTimesUpdated(newTimes)
    }

    // ── Retry queue ───────────────────────────────────────────────────────────
    property int _maxRetries: JsK.MAX_RETRIES
    property var _retryQueue: []

    Timer {
        id: retryTimer
        interval: JsK.RETRY_INTERVAL_MS
        repeat: false
        onTriggered: _processRetryQueue()
    }

    function _scheduleRetry(symbol, fetchType, attempt) {
        var q = _retryQueue.slice()
        q.push({ sym: symbol, fetchType: fetchType, attempt: attempt })
        _retryQueue = q
        retryTimer.interval = JsK.RETRY_INTERVAL_MS * attempt
        retryTimer.restart()
    }

    function _processRetryQueue() {
        if (_retryQueue.length === 0) return
        var q    = _retryQueue.slice()
        var item = q.shift()
        _retryQueue = q
        if (c.devMode) console.log("[Markets/Fetcher] retry", item.sym.id, item.fetchType,
                    "(attempt", item.attempt + "/" + _maxRetries + ")")
        doFetch(item.sym, item.fetchType, item.attempt)
        if (_retryQueue.length > 0) {
            retryTimer.interval = JsK.RETRY_SUBSEQUENT_MS
            retryTimer.restart()
        }
    }

    // ── Process-based fetch ───────────────────────────────────────────────────
    Component {
        id: fetchComponent

        Process {
            property string symbolId:     ""
            property string providerName: ""
            property string fetchType:    "price"
            property string chartRange:   "1M"
            property string fetchKey:     ""
            property int    _attempt:     0
            property string _buffer:      ""

            stdout: StdioCollector {
                onStreamFinished: {
                    _buffer = text
                }
            }

            stderr: SplitParser {
                onRead: line => {
                    if (line.trim() && c.devMode)
                        console.warn("[Markets/Fetcher] fetch", symbolId, "stderr:", line)
                }
            }

            onExited: exitCode => {
                if (exitCode === 0 && _buffer.trim()) {
                    _onFetchComplete(symbolId, providerName, fetchType, chartRange, _buffer)
                } else if (exitCode !== 0) {
                    if (c.devMode) console.warn("[Markets/Fetcher]", symbolId, fetchType, "exited with code", exitCode)
                    if (_attempt < _maxRetries) {
                        var symbol = _findSymbol(symbolId)
                        if (symbol)
                            _scheduleRetry(symbol, fetchType, _attempt + 1)
                    }
                } else {
                    if (c.devMode) console.warn("[Markets/Fetcher]", symbolId, fetchType,
                                 "returned empty response — no retry")
                }
                _finishFetch(fetchKey, symbolId)
                destroy()
            }
        }
    }

    Timer {
        id: fetchPumpTimer
        interval: JsK.FETCH_QUEUE_PUMP_MS
        repeat: false
        onTriggered: _pumpFetchQueue()
    }

    function _findSymbol(symbolId) {
        for (var i = 0; i < symbols.length; i++)
            if (symbols[i].id === symbolId) return symbols[i]
        return null
    }

    // ── Public: start a fetch ─────────────────────────────────────────────────
    function doFetch(symbol, fetchType, attempt) {
        var retryNum  = attempt || 0
        if (c.devMode) console.log("[Markets/Fetcher] doFetch", symbol.id, fetchType,
                                   retryNum > 0 ? "(retry " + retryNum + ")" : "")
        var url
        var tailLines = 0

        if (fetchType === "price") {
            var priceInterval = Providers.getPriceInterval(symbol.priceInterval)
            url = Providers.buildPriceUrl(symbol.id, symbol.provider, priceInterval)
        } else {
            var histConfig = Providers.getHistoryConfig(symbol.graphInterval)
            url = Providers.buildHistoryUrl(symbol.id, symbol.provider, histConfig.interval)
            tailLines = histConfig.maxPoints + 2
        }

        if (!url) return

        var fetchKey = symbol.id + "_" + fetchType + "_" + url
        if (_queuedFetchKeys[fetchKey]) {
            if (c.devMode) console.log("[Markets/Fetcher] already queued/running", symbol.id, fetchType)
            return
        }

        var curlCmd = _buildCurlCommand(url, tailLines)
        var shell = ["bash", "-o", "pipefail", "-c", curlCmd]

        var queuedKeys = {}
        for (var qk in _queuedFetchKeys) queuedKeys[qk] = _queuedFetchKeys[qk]
        queuedKeys[fetchKey] = true
        _queuedFetchKeys = queuedKeys

        var queue = _fetchQueue.slice()
        queue.push({
            symbolId:     symbol.id,
            providerName: symbol.provider,
            fetchType:    fetchType,
            chartRange:   symbol.graphInterval || "1M",
            fetchKey:     fetchKey,
            attempt:      retryNum,
            command:      shell
        })
        _fetchQueue = queue

        var pending = {}
        for (var k in _pendingFetches) pending[k] = _pendingFetches[k]
        pending[symbol.id] = (pending[symbol.id] || 0) + 1
        pendingFetchesUpdated(pending)

        fetchPumpTimer.restart()
    }

    function _pumpFetchQueue() {
        if (_fetchQueue.length === 0) return
        if (_activeFetchCount >= JsK.MAX_CONCURRENT_FETCHES) return

        var queue = _fetchQueue.slice()
        var job = queue.shift()
        _fetchQueue = queue
        _activeFetchCount = _activeFetchCount + 1

        var proc = fetchComponent.createObject(this, {
            symbolId:     job.symbolId,
            providerName: job.providerName,
            fetchType:    job.fetchType,
            chartRange:   job.chartRange,
            fetchKey:     job.fetchKey,
            _attempt:     job.attempt
        })
        proc.command = job.command
        proc.running = true
    }

    function _finishFetch(fetchKey, symbolId) {
        _activeFetchCount = Math.max(0, _activeFetchCount - 1)

        var queuedKeys = {}
        for (var key in _queuedFetchKeys)
            if (key !== fetchKey) queuedKeys[key] = _queuedFetchKeys[key]
        _queuedFetchKeys = queuedKeys

        _decrementPending(symbolId)
        fetchPumpTimer.restart()
    }

    function _buildCurlCommand(url, tailLines) {
        var cmd = ""
        cmd += "set -e\n"
        cmd += "if command -v ionice >/dev/null 2>&1; then ionice -c3 -p $$ >/dev/null 2>&1 || true; fi\n"
        cmd += "if command -v renice >/dev/null 2>&1; then renice -n 19 -p $$ >/dev/null 2>&1 || true; fi\n"
        cmd += "cookie=\"${XDG_CACHE_HOME:-$HOME/.cache}/dms-markets-stooq.cookies\"\n"
        cmd += "mkdir -p \"$(dirname \"$cookie\")\"\n"
        cmd += "tmp=\"$(mktemp)\"\n"
        cmd += "hdr=\"$(mktemp)\"\n"
        cmd += "cleanup() { rm -f \"$tmp\" \"$hdr\"; }\n"
        cmd += "trap cleanup EXIT\n"
        cmd += "url='" + url + "'\n"
        cmd += "fetch() {\n"
        cmd += "  curl -fsSL --connect-timeout 10 --max-time 20"
        cmd += " -D \"$hdr\""
        cmd += " -b \"$cookie\" -c \"$cookie\""
        cmd += " -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64)'"
        cmd += " \"$url\" -o \"$tmp\"\n"
        cmd += "}\n"
        cmd += "fetch\n"
        cmd += "if grep -q 'This site requires JavaScript to verify your browser' \"$tmp\"; then\n"
        cmd += "  challenge=$(sed -n 's/.*const c=\"\\([^\"]*\\)\",d=\\([0-9][0-9]*\\).*/\\1 \\2/p' \"$tmp\" | head -n 1)\n"
        cmd += "  if [ -z \"$challenge\" ]; then cat \"$tmp\"; exit 0; fi\n"
        cmd += "  cval=${challenge% *}\n"
        cmd += "  dval=${challenge##* }\n"
        cmd += "  n=$(node -e 'const crypto=require(\"crypto\"); const c=process.argv[1], d=Number(process.argv[2]); const target=\"0\".repeat(d); for (let n=0;;n++) { if (crypto.createHash(\"sha256\").update(c+n).digest(\"hex\").startsWith(target)) { console.log(n); break; } }' \"$cval\" \"$dval\")\n"
        cmd += "  curl -fsSL --connect-timeout 10 --max-time 20"
        cmd += " -b \"$cookie\" -c \"$cookie\""
        cmd += " -X POST -H 'Content-Type: application/x-www-form-urlencoded'"
        cmd += " --data-urlencode \"c=$cval\" --data-urlencode \"n=$n\""
        cmd += " 'https://stooq.com/__verify' >/dev/null\n"
        cmd += "  fetch\n"
        cmd += "fi\n"
        cmd += "if grep -qi 'filename=error.txt' \"$hdr\"; then echo 'get your apikey'; exit 0; fi\n"
        if (tailLines > 0)
            cmd += "tail -n " + tailLines + " \"$tmp\"\n"
        else
            cmd += "cat \"$tmp\"\n"
        return cmd
    }

    // ── Incremental graph merge ───────────────────────────────────────────────
    function _mergeLatestIntoGraph(symbol) {
        var pd = priceData[symbol.id]
        if (!pd || pd.close === undefined || isNaN(pd.close)) return

        var existing = graphData[symbol.id]
        if (!existing || existing.length === 0) return

        var newPoint = {
            date: pd.date || "", time: pd.time || "",
            open: pd.open, high: pd.high, low: pd.low, close: pd.close, volume: 0
        }

        var updated   = existing.slice()
        var lastPoint = updated[updated.length - 1]

        if (lastPoint.date === newPoint.date) {
            updated[updated.length - 1] = newPoint
        } else {
            var histConfig = Providers.getHistoryConfig(symbol.graphInterval)
            updated.push(newPoint)
            if (updated.length > histConfig.maxPoints)
                updated = updated.slice(-histConfig.maxPoints)
        }

        var g = {}
        for (var k in graphData) g[k] = graphData[k]
        g[symbol.id] = updated
        graphDataReady(g)
    }

    // ── Parse and store completed fetch ───────────────────────────────────────
    function _onFetchComplete(symbolId, providerName, fetchType, chartRange, csvText) {
        if (Providers.isApiKeyError(csvText)) {
            tokenError("API key missing or invalid — enter your Stooq API key in plugin settings")
            return
        }
        var invert = Helpers.isInverted(symbols, symbolId)

        if (fetchType === "price") {
            var parsed = Providers.parsePriceResponse(providerName, csvText)
            if (parsed.length === 0) return

            var latest     = parsed[parsed.length - 1]
            var openPrice  = latest.open
            var highPrice  = latest.high
            var lowPrice   = latest.low
            var closePrice = latest.close

            if (invert) {
                openPrice  = Helpers.inv(openPrice)
                highPrice  = Helpers.inv(highPrice)
                lowPrice   = Helpers.inv(lowPrice)
                closePrice = Helpers.inv(closePrice)
                var tmpH   = highPrice
                highPrice  = Math.min(highPrice, lowPrice)
                lowPrice   = Math.max(tmpH, lowPrice)
            }

            var newData = {}
            for (var pk in priceData) newData[pk] = priceData[pk]
            newData[symbolId] = {
                open: openPrice, high: highPrice, low: lowPrice, close: closePrice,
                date: latest.date, time: latest.time,
                change:        closePrice - openPrice,
                changePercent: openPrice !== 0
                               ? ((closePrice - openPrice) / openPrice * 100) : 0
            }
            priceDataReady(newData)

            var times = {}
            for (var tk in lastFetchTimes) times[tk] = lastFetchTimes[tk]
            times[symbolId + "_price"] = Date.now()
            fetchTimesUpdated(times)

        } else {
            var history = Providers.parseHistoryResponse(providerName, csvText)
            if (history.length === 0) {
                if (c.devMode) console.warn("[Markets/Fetcher]", symbolId, "history returned no data — chart unavailable")
                return
            }

            if (invert) {
                for (var hi = 0; hi < history.length; hi++) {
                    var dp      = history[hi]
                    dp.open     = Helpers.inv(dp.open)
                    dp.close    = Helpers.inv(dp.close)
                    var invHigh = Helpers.inv(dp.high)
                    var invLow  = Helpers.inv(dp.low)
                    dp.high     = Math.max(invHigh, invLow)
                    dp.low      = Math.min(invHigh, invLow)
                }
            }

            var histConfig = Providers.getHistoryConfig(chartRange)
            var newGraph   = {}
            for (var gk in graphData) newGraph[gk] = graphData[gk]
            newGraph[symbolId] = history.slice(-histConfig.maxPoints)
            graphDataReady(newGraph)

            var fullFetch = {}
            for (var fk in _lastFullGraphFetch) fullFetch[fk] = _lastFullGraphFetch[fk]
            fullFetch[symbolId] = Date.now()
            fullGraphFetchUpdated(fullFetch)
        }
    }

    // ── Pending counter ───────────────────────────────────────────────────────
    function _decrementPending(symbolId) {
        var p = {}
        for (var k in _pendingFetches) p[k] = _pendingFetches[k]
        p[symbolId] = Math.max(0, (p[symbolId] || 0) - 1)
        if (p[symbolId] === 0) delete p[symbolId]
        pendingFetchesUpdated(p)
    }

    // ── Public: force-refresh a single symbol ─────────────────────────────────
    function forceRefreshSymbol(symbolId) {
        if (c.devMode) console.log("[Markets/Fetcher] forceRefreshSymbol", symbolId)
        for (var i = 0; i < symbols.length; i++) {
            if (symbols[i].id === symbolId) {
                var fullFetch = {}
                for (var k in _lastFullGraphFetch) fullFetch[k] = _lastFullGraphFetch[k]
                fullFetch[symbolId] = 0
                fullGraphFetchUpdated(fullFetch)
                doFetch(symbols[i], "price")
                doFetch(symbols[i], "graph")
                break
            }
        }
    }

    // ── Public: force-refresh every symbol ────────────────────────────────────
    function forceRefreshAll() {
        if (c.devMode) console.log("[Markets/Fetcher] forceRefreshAll", symbols.length, "symbols")
        var fullFetch = {}
        for (var k in _lastFullGraphFetch) fullFetch[k] = _lastFullGraphFetch[k]
        for (var i = 0; i < symbols.length; i++) {
            fullFetch[symbols[i].id] = 0
            doFetch(symbols[i], "price")
            doFetch(symbols[i], "graph")
        }
        fullGraphFetchUpdated(fullFetch)
    }

    // ── Initial stagger queue ─────────────────────────────────────────────────
    property var _initialGraphQueue: []

    Timer {
        id: initialGraphTimer
        interval: JsK.INITIAL_GRAPH_STAGGER_MS
        repeat: false
        onTriggered: _processInitialGraphQueue()
    }

    function _processInitialGraphQueue() {
        if (_initialGraphQueue.length === 0) return
        var q      = _initialGraphQueue.slice()
        var symbol = q.shift()
        _initialGraphQueue = q
        doFetch(symbol, "graph")
        if (q.length > 0) initialGraphTimer.restart()
    }

    // ── Public: kick off all initial fetches ──────────────────────────────────
    function startInitialFetches(symbolList) {
        if (c.devMode) console.log("[Markets/Fetcher] startInitialFetches —", symbolList.length, "symbols")
        var now      = Date.now()
        var newTimes = {}
        var queue    = []
        for (var i = 0; i < symbolList.length; i++) {
            var sym = symbolList[i]
            doFetch(sym, "price")
            newTimes[sym.id + "_price"] = now
            newTimes[sym.id + "_graph"] = now
            queue.push(sym)
        }
        fetchTimesUpdated(newTimes)
        _initialGraphQueue     = queue
        initialGraphTimer.interval = JsK.INITIAL_GRAPH_DELAY_MS
        initialGraphTimer.restart()
    }

    // ── Public: fetch newly-added symbols ─────────────────────────────────────
    function fetchNewSymbols(newSymbolList, knownIds) {
        var now      = Date.now()
        var newTimes = {}
        for (var k in lastFetchTimes) newTimes[k] = lastFetchTimes[k]
        var hasNew   = false

        for (var i = 0; i < newSymbolList.length; i++) {
            var sym = newSymbolList[i]
            if (knownIds.indexOf(sym.id) === -1) {
                doFetch(sym, "price")
                doFetch(sym, "graph")
                newTimes[sym.id + "_price"] = now
                newTimes[sym.id + "_graph"] = now
                hasNew = true
            }
        }
        if (hasNew) fetchTimesUpdated(newTimes)
    }
}
