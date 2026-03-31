// Widget.qml — Main DMS bar widget with popout
//
// Shows pinned market symbols in the bar and provides a popout panel listing
// all tracked symbols with live prices, change indicators, and sparkline charts.
//
// Data fetching is abstracted through ProviderInterface.js — the widget itself
// knows nothing about Stooq or any specific data source.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "../JS/ProviderInterface.js" as Providers
import "../JS/StooqProvider.js" as StooqProvider
import "../JS/Helpers.js" as Helpers

PluginComponent {
    id: root

    layerNamespacePlugin: "markets"

    // ── Global colors ─────────────────────────────────────────────────────────
    property color upColor: {
        var colorValue = (pluginData.upColor || "").trim()
        return colorValue !== "" ? colorValue : "#4CAF50"
    }
    property color downColor: {
        var colorValue = (pluginData.downColor || "").trim()
        return colorValue !== "" ? colorValue : "#F44336"
    }
    // ── Global popout display toggles (all default to true) ──────────────
    property bool showTicker:         Helpers.pluginDataBool(pluginData.showTicker)
    property bool showPriceRange:     Helpers.pluginDataBool(pluginData.showPriceRange)
    property bool showChartRange:     Helpers.pluginDataBool(pluginData.showChartRange)
    property bool showRefreshedSince: Helpers.pluginDataBool(pluginData.showRefreshedSince)

    // ── Persisted symbols list ───────────────────────────────────────────────
    // Stored as JSON string in pluginData.symbols
    // Each entry: { id, name, provider, priceInterval, graphInterval, pinned }
    property var symbols: {
        try { return JSON.parse(pluginData.symbols || "[]") }
        catch (e) { return [] }
    }

    // ── Live state (not persisted) ───────────────────────────────────────────
    // priceData[symbolId] = { open, high, low, close, change, changePercent, date, time }
    property var priceData: ({})

    // graphData[symbolId] = DataPoint[] (up to 50 candles for sparkline)
    property var graphData: ({})

    // lastFetchTimes[symbolId + "_price"|"_graph"] = epoch ms
    property var lastFetchTimes: ({})

    // Tracks when each symbol last did a FULL history download (epoch ms).
    // Between full downloads, graph data is updated incrementally from price data.
    property var _lastFullGraphFetch: ({})

    // Loading state: number of active fetches per symbol
    property var _pendingFetches: ({})

    // ── Number formatting (delegated to Helpers.js) ──────────────────────────
    function formatNumber(number, decimals) { return Helpers.formatNumber(number, decimals) }

    // ── Computed bar display ─────────────────────────────────────────────────
    property var pinnedSymbols: {
        var result = []
        for (var symbolIndex = 0; symbolIndex < symbols.length; symbolIndex++) {
            if (symbols[symbolIndex].pinned) result.push(symbols[symbolIndex])
        }
        return result
    }

    property string barDisplayText: {
        if (pinnedSymbols.length === 0) return "Markets"
        var parts = []
        for (var symbolIndex = 0; symbolIndex < pinnedSymbols.length; symbolIndex++) {
            var symbol = pinnedSymbols[symbolIndex]
            var symbolPriceData = priceData[symbol.id]
            if (symbolPriceData && symbolPriceData.close !== undefined && !isNaN(symbolPriceData.close)) {
                var closeVal = symbolPriceData.close
                var label = symbol.name + " " + formatNumber(closeVal)
                if (symbol.showChangeWhenPinned) {
                    var changeAmount = symbolPriceData.change || 0
                    var sign = changeAmount >= 0 ? "+" : ""
                    label += " " + sign + formatNumber(changeAmount)
                }
                parts.push(label)
            } else {
                parts.push(symbol.name + " …")
            }
        }
        return parts.join("  │  ")
    }

    // ── Interval helpers (delegated to Helpers.js) ───────────────────────────
    function intervalToMs(interval) { return Helpers.intervalToMs(interval) }

    // ── Polling timer ────────────────────────────────────────────────────────
    // Fires every 30 s and checks per-symbol whether each fetch type is due.
    Timer {
        id: checkTimer
        interval: 30000
        running: root.symbols.length > 0
        repeat: true
        onTriggered: root.checkAndFetch()
    }

    function checkAndFetch() {
        var now      = Date.now()
        var newTimes = {}
        // shallow copy
        for (var key in lastFetchTimes)
            newTimes[key] = lastFetchTimes[key]

        for (var symbolIndex = 0; symbolIndex < symbols.length; symbolIndex++) {
            var symbol = symbols[symbolIndex]

            // Price — refresh based on price interval
            var priceKey      = symbol.id + "_price"
            var lastPriceTime = newTimes[priceKey] || 0
            var priceRefresh  = intervalToMs(symbol.priceInterval)
            if (now - lastPriceTime >= priceRefresh) {
                doFetch(symbol, "price")
                newTimes[priceKey] = now
            }

            // Graph — full re-download only once per day (86400000 ms) or
            // on first load; otherwise merge latest price into existing graph.
            var graphKey      = symbol.id + "_graph"
            var lastGraphTime = newTimes[graphKey] || 0
            var histConfig    = Providers.getHistoryConfig(symbol.graphInterval)
            if (now - lastGraphTime >= histConfig.refreshMs) {
                var lastFull = _lastFullGraphFetch[symbol.id] || 0
                var existing = graphData[symbol.id]

                if (!existing || existing.length === 0 || now - lastFull >= 86400000) {
                    // No data yet or stale — do a full history download
                    doFetch(symbol, "graph")
                } else {
                    // Incremental — merge last price candle into existing graph
                    _mergeLatestIntoGraph(symbol)
                }
                newTimes[graphKey] = now
            }
        }
        lastFetchTimes = newTimes
    }

    // ── Retry queue ──────────────────────────────────────────────────────────
    // Failed fetches are retried up to _maxRetries times with increasing delay.
    property int _maxRetries: 3
    property var _retryQueue: []      // [ { sym, fetchType, attempt } ]

    Timer {
        id: retryTimer
        interval: 3000
        repeat: false
        onTriggered: root._processRetryQueue()
    }

    function _scheduleRetry(symbol, fetchType, attempt) {
        var queueCopy = _retryQueue.slice()
        queueCopy.push({ sym: symbol, fetchType: fetchType, attempt: attempt })
        _retryQueue = queueCopy
        // Stagger retries: 3 s × attempt number
        retryTimer.interval = 3000 * attempt
        retryTimer.restart()
    }

    function _processRetryQueue() {
        if (_retryQueue.length === 0) return
        var queueCopy = _retryQueue.slice()
        var item = queueCopy.shift()
        _retryQueue = queueCopy
        console.log("[Markets] Retry", item.sym.id, item.fetchType, "(attempt", item.attempt + "/" + _maxRetries + ")")
        doFetch(item.sym, item.fetchType, item.attempt)
        // If more items remain, schedule next
        if (_retryQueue.length > 0) {
            retryTimer.interval = 2000
            retryTimer.restart()
        }
    }

    // ── Process-based fetch ──────────────────────────────────────────────────
    Component {
        id: fetchComponent

        Process {
            property string symbolId:       ""
            property string providerName:   ""
            property string fetchType:      "price"
            property string chartRange:     "1M"
            property int    _attempt:       0
            property string _buffer:        ""

            stdout: SplitParser {
                onRead: line => _buffer += line + "\n"
            }

            stderr: SplitParser {
                onRead: line => {
                    if (line.trim())
                        console.warn("[Markets] fetch", symbolId, ":", line)
                }
            }

            onExited: exitCode => {
                if (exitCode === 0 && _buffer.trim()) {
                    root.onFetchComplete(symbolId, providerName, fetchType, chartRange, _buffer)
                } else if (exitCode !== 0) {
                    // Genuine fetch failure (connection reset, timeout, etc.)
                    console.warn("[Markets]", symbolId, fetchType, "exited with code", exitCode)
                    if (_attempt < root._maxRetries) {
                        var symbol = root._findSymbol(symbolId)
                        if (symbol)
                            root._scheduleRetry(symbol, fetchType, _attempt + 1)
                    }
                } else if (!_buffer.trim()) {
                    // curl succeeded but response was empty (e.g. futures with no history)
                    console.warn("[Markets]", symbolId, fetchType, "returned empty response — no retry")
                }
                root._decrementPending(symbolId)
                destroy()
            }
        }
    }

    function _findSymbol(symbolId) {
        for (var symbolIndex = 0; symbolIndex < symbols.length; symbolIndex++)
            if (symbols[symbolIndex].id === symbolId) return symbols[symbolIndex]
        return null
    }

    function doFetch(symbol, fetchType, attempt) {
        var retryNum = attempt || 0
        var url
        var tailLines = 0
        if (fetchType === "price") {
            // Map price range to the best candle interval for /q/l/
            var priceInterval = Providers.getPriceInterval(symbol.priceInterval)
            url = Providers.buildPriceUrl(symbol.id, symbol.provider, priceInterval)
        } else {
            // Use chart range config to pick the right candle interval
            var histConfig = Providers.getHistoryConfig(symbol.graphInterval)
            url = Providers.buildHistoryUrl(symbol.id, symbol.provider, histConfig.interval)
            tailLines = histConfig.maxPoints + 2   // +2 for header + safety
        }

        if (!url) return

        var curlCmd = "curl -fsSL --connect-timeout 10 --max-time 20"
                    + " -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64)'"
                    + " -b 'cookie_uu=p'"
                    + " '" + url + "'"
        if (tailLines > 0)
            curlCmd += " | tail -n " + tailLines

        // Use bash with pipefail so curl errors propagate through pipes
        var shell = tailLines > 0 ? ["bash", "-o", "pipefail", "-c", curlCmd]
                                  : ["sh", "-c", curlCmd]

        var proc = fetchComponent.createObject(root, {
            symbolId:     symbol.id,
            providerName: symbol.provider,
            fetchType:    fetchType,
            chartRange:   symbol.graphInterval || "1M",
            _attempt:     retryNum
        })
        proc.command = shell
        proc.running = true

        // Track loading state
        var pendingCopy = {}
        for (var fetchKey in _pendingFetches) pendingCopy[fetchKey] = _pendingFetches[fetchKey]
        pendingCopy[symbol.id] = (pendingCopy[symbol.id] || 0) + 1
        _pendingFetches = pendingCopy
    }

    // ── Inversion helpers (delegated to Helpers.js) ──────────────────────
    function _isInverted(symbolId) { return Helpers.isInverted(symbols, symbolId) }
    function _inv(value) { return Helpers.inv(value) }

    // ── Incremental graph merge ──────────────────────────────────────────
    // Instead of re-downloading all history, update the graph in memory
    // using the already-fetched price data for the symbol.
    function _mergeLatestIntoGraph(symbol) {
        var currentPriceData = priceData[symbol.id]
        if (!currentPriceData || currentPriceData.close === undefined || isNaN(currentPriceData.close)) return

        var existing = graphData[symbol.id]
        if (!existing || existing.length === 0) return

        var latestDate = currentPriceData.date || ""
        var lastPoint  = existing[existing.length - 1]

        // Build a new data point from the current price
        var newDataPoint = {
            date:   latestDate,
            time:   currentPriceData.time || "",
            open:   currentPriceData.open,
            high:   currentPriceData.high,
            low:    currentPriceData.low,
            close:  currentPriceData.close,
            volume: 0
        }

        var updated = existing.slice()  // shallow copy

        if (lastPoint.date === latestDate) {
            // Same date — update the last candle in place
            updated[updated.length - 1] = newDataPoint
        } else {
            // New date — append and trim oldest if over max
            var histConfig = Providers.getHistoryConfig(symbol.graphInterval)
            updated.push(newDataPoint)
            if (updated.length > histConfig.maxPoints)
                updated = updated.slice(-histConfig.maxPoints)
        }

        var newGraph = {}
        for (var graphKey in graphData) newGraph[graphKey] = graphData[graphKey]
        newGraph[symbol.id] = updated
        graphData = newGraph
    }

    function onFetchComplete(symbolId, providerName, fetchType, chartRange, csvText) {
        var invert = _isInverted(symbolId)

        if (fetchType === "price") {
            var parsed = Providers.parsePriceResponse(providerName, csvText)
            if (parsed.length > 0) {
                var latest     = parsed[parsed.length - 1]
                var openPrice  = latest.open
                var highPrice  = latest.high
                var lowPrice   = latest.low
                var closePrice = latest.close

                if (invert) {
                    openPrice  = _inv(openPrice)
                    highPrice  = _inv(highPrice)
                    lowPrice   = _inv(lowPrice)
                    closePrice = _inv(closePrice)
                    // After inversion high/low may swap
                    var tempHigh = highPrice
                    highPrice = Math.min(highPrice, lowPrice)
                    lowPrice  = Math.max(tempHigh, lowPrice)
                }

                var newData = {}
                for (var priceKey in priceData) newData[priceKey] = priceData[priceKey]
                newData[symbolId] = {
                    open:   openPrice,
                    high:   highPrice,
                    low:    lowPrice,
                    close:  closePrice,
                    date:   latest.date,
                    time:   latest.time,
                    change:        closePrice - openPrice,
                    changePercent: openPrice !== 0
                                   ? ((closePrice - openPrice) / openPrice * 100)
                                   : 0
                }
                priceData = newData

                // Update last-fetched timestamp so SymbolRow "ago" reflects actual completion
                var updatedTimes = {}
                for (var timeKey in lastFetchTimes) updatedTimes[timeKey] = lastFetchTimes[timeKey]
                updatedTimes[symbolId + "_price"] = Date.now()
                lastFetchTimes = updatedTimes
            }
        } else {
            var history = Providers.parseHistoryResponse(providerName, csvText)
            if (history.length === 0)
                console.warn("[Markets]", symbolId, "history returned no data — chart unavailable")
            if (history.length > 0) {
                if (invert) {
                    for (var historyIndex = 0; historyIndex < history.length; historyIndex++) {
                        var dataPoint = history[historyIndex]
                        dataPoint.open  = _inv(dataPoint.open)
                        dataPoint.close = _inv(dataPoint.close)
                        var invertedHigh = _inv(dataPoint.high)
                        var invertedLow  = _inv(dataPoint.low)
                        dataPoint.high = Math.max(invertedHigh, invertedLow)
                        dataPoint.low  = Math.min(invertedHigh, invertedLow)
                    }
                }
                var newGraph = {}
                for (var graphKey in graphData) newGraph[graphKey] = graphData[graphKey]
                // Slice to the appropriate number of data points for the chart range
                var histConfig = Providers.getHistoryConfig(chartRange)
                newGraph[symbolId] = history.slice(-histConfig.maxPoints)
                graphData = newGraph

                // Record that a full history download was completed
                var fullGraphCopy = {}
                for (var fetchKey in _lastFullGraphFetch) fullGraphCopy[fetchKey] = _lastFullGraphFetch[fetchKey]
                fullGraphCopy[symbolId] = Date.now()
                _lastFullGraphFetch = fullGraphCopy
            }
        }
    }

    // ── Symbol management ────────────────────────────────────────────────────
    function _decrementPending(symbolId) {
        var pendingCopy = {}
        for (var fetchKey in _pendingFetches) pendingCopy[fetchKey] = _pendingFetches[fetchKey]
        pendingCopy[symbolId] = Math.max(0, (pendingCopy[symbolId] || 0) - 1)
        if (pendingCopy[symbolId] === 0) delete pendingCopy[symbolId]
        _pendingFetches = pendingCopy
    }

    function togglePin(symbolId) {
        var newSymbols = JSON.parse(JSON.stringify(symbols))
        for (var symbolIndex = 0; symbolIndex < newSymbols.length; symbolIndex++) {
            if (newSymbols[symbolIndex].id === symbolId) {
                newSymbols[symbolIndex].pinned = !newSymbols[symbolIndex].pinned
                break
            }
        }
        if (pluginService)
            pluginService.savePluginData(pluginId, "symbols", JSON.stringify(newSymbols))
    }

    function removeSymbol(symbolId) {
        var newSymbols = []
        for (var symbolIndex = 0; symbolIndex < symbols.length; symbolIndex++) {
            if (symbols[symbolIndex].id !== symbolId)
                newSymbols.push(symbols[symbolIndex])
        }
        if (pluginService)
            pluginService.savePluginData(pluginId, "symbols", JSON.stringify(newSymbols))
    }

    function forceRefreshSymbol(symbolId) {
        for (var symbolIndex = 0; symbolIndex < symbols.length; symbolIndex++) {
            if (symbols[symbolIndex].id === symbolId) {
                var symbol = symbols[symbolIndex]
                // Reset full graph fetch tracker so doFetch triggers a full download
                var fullGraphCopy = {}
                for (var fetchKey in _lastFullGraphFetch) fullGraphCopy[fetchKey] = _lastFullGraphFetch[fetchKey]
                fullGraphCopy[symbolId] = 0
                _lastFullGraphFetch = fullGraphCopy
                // Start both fetches — timestamps updated in onFetchComplete
                doFetch(symbol, "price")
                doFetch(symbol, "graph")
                break
            }
        }
    }

    function forceRefreshAll() {
        for (var symbolIndex = 0; symbolIndex < symbols.length; symbolIndex++) {
            var symbol = symbols[symbolIndex]
            var fullGraphCopy = {}
            for (var fetchKey in _lastFullGraphFetch) fullGraphCopy[fetchKey] = _lastFullGraphFetch[fetchKey]
            fullGraphCopy[symbol.id] = 0
            _lastFullGraphFetch = fullGraphCopy
            doFetch(symbol, "price")
            doFetch(symbol, "graph")
        }
    }

    // ── Track known symbol IDs for detecting new additions ────────────────
    property var _knownSymbolIds: []
    property bool _initialized: false

    // Watch for symbols changes safely via a short-delay timer
    Timer {
        id: newSymbolChecker
        interval: 500
        repeat: false
        onTriggered: root.checkForNewSymbols()
    }

    onSymbolsChanged: {
        if (_initialized)
            newSymbolChecker.restart()
    }

    function checkForNewSymbols() {
        var currentIds = []
        for (var idIndex = 0; idIndex < symbols.length; idIndex++)
            currentIds.push(symbols[idIndex].id)

        var newTimes = {}
        for (var key in lastFetchTimes) newTimes[key] = lastFetchTimes[key]
        var now = Date.now()
        var hasNew = false

        for (var symbolIndex = 0; symbolIndex < symbols.length; symbolIndex++) {
            if (_knownSymbolIds.indexOf(symbols[symbolIndex].id) === -1) {
                doFetch(symbols[symbolIndex], "price")
                doFetch(symbols[symbolIndex], "graph")
                newTimes[symbols[symbolIndex].id + "_price"] = now
                newTimes[symbols[symbolIndex].id + "_graph"] = now
                hasNew = true
            }
        }
        if (hasNew) lastFetchTimes = newTimes
        _knownSymbolIds = currentIds
    }

    // ── Initial fetch on load ────────────────────────────────────────────────
    // Stagger initial graph fetches to avoid overwhelming the server.
    // Prices fire immediately; graph fetches are queued with 500ms delay each.
    property var _initialGraphQueue: []

    Timer {
        id: initialGraphTimer
        interval: 500
        repeat: false
        onTriggered: root._processInitialGraphQueue()
    }

    function _processInitialGraphQueue() {
        if (_initialGraphQueue.length === 0) return
        var queueCopy = _initialGraphQueue.slice()
        var symbol = queueCopy.shift()
        _initialGraphQueue = queueCopy
        doFetch(symbol, "graph")
        if (queueCopy.length > 0)
            initialGraphTimer.restart()
    }

    Component.onCompleted: {
        // Populate known IDs before enabling change detection
        var knownIds = []
        for (var idIndex = 0; idIndex < symbols.length; idIndex++)
            knownIds.push(symbols[idIndex].id)
        _knownSymbolIds = knownIds
        _initialized = true

        if (symbols.length > 0) {
            // Fetch prices immediately for all symbols
            var now = Date.now()
            var newTimes = {}
            var graphQueue = []
            for (var symbolIndex = 0; symbolIndex < symbols.length; symbolIndex++) {
                var symbol = symbols[symbolIndex]
                doFetch(symbol, "price")
                newTimes[symbol.id + "_price"] = now
                newTimes[symbol.id + "_graph"] = now
                graphQueue.push(symbol)
            }
            lastFetchTimes = newTimes
            // Stagger graph fetches: first after 300ms, then 500ms apart
            _initialGraphQueue = graphQueue
            initialGraphTimer.interval = 300
            initialGraphTimer.restart()
        }
    }

    // ── Configurable popout rows ─────────────────────────────────────────────
    property int popoutRows: {
        var rowCount = parseInt(pluginData.popoutRows || "5")
        return (isNaN(rowCount) || rowCount < 1) ? 5 : rowCount
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  BAR PILLS
    // ═══════════════════════════════════════════════════════════════════════

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS

            DankIcon {
                name: "show_chart"
                size: root.iconSize
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.barDisplayText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            DankIcon {
                name: "show_chart"
                size: root.iconSize
                color: Theme.primary
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.pinnedSymbols.length > 0
                      ? root.pinnedSymbols[0].name
                      : "MKT"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  POPOUT
    // ═══════════════════════════════════════════════════════════════════════

    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText:      "Markets"
            detailsText:     root.symbols.length > 0
                             ? root.symbols.length + " symbol" + (root.symbols.length !== 1 ? "s" : "") + " tracked"
                             : "Add symbols in Settings"
            showCloseButton: false

            PopoutPanel {
                width: parent.width
                implicitHeight: root.popoutHeight
                                - popout.headerHeight
                                - popout.detailsHeight
                                - Theme.spacingXL

                symbols:        root.symbols
                priceData:      root.priceData
                graphData:      root.graphData
                pendingFetches: root._pendingFetches
                lastFetchTimes: root.lastFetchTimes
                upColor:        root.upColor
                downColor:      root.downColor
                showTicker:         root.showTicker
                showPriceRange:     root.showPriceRange
                showChartRange:     root.showChartRange
                showRefreshedSince: root.showRefreshedSince
                popoutRows:     root.popoutRows
                headerOffset:   popout.headerHeight + popout.detailsHeight

                onTogglePin:    function(symbolId) { root.togglePin(symbolId) }
                onRemoveSymbol: function(symbolId) { root.removeSymbol(symbolId) }
                onRefreshSymbol: function(symbolId) { root.forceRefreshSymbol(symbolId) }
                onRefreshAll:   root.forceRefreshAll()
                onClosePopout:  root.closePopout()
            }
        }
    }

    popoutWidth:  440
    popoutHeight: {
        // 77 per row (76 + 1 subpixel compensation) + spacingS gaps + header/details/padding
        var rowHeight = 78
        var visibleCount = Math.min(popoutRows, symbols.length)
        var totalRows = visibleCount > 0 ? visibleCount : popoutRows
        return Math.max(200, totalRows * rowHeight + (totalRows - 1) * Theme.spacingS + 80)
    }
}
