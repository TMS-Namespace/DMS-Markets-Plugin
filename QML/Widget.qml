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

PluginComponent {
    id: root

    layerNamespacePlugin: "markets"

    // ── Global colors ─────────────────────────────────────────────────────────
    property color upColor: {
        var c = (pluginData.upColor || "").trim()
        return c !== "" ? c : "#4CAF50"
    }
    property color downColor: {
        var c = (pluginData.downColor || "").trim()
        return c !== "" ? c : "#F44336"
    }

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

    // Loading state: number of active fetches per symbol
    property var _pendingFetches: ({})

    // ── Number formatting with thousands separator ───────────────────────────
    function formatNumber(num, decimals) {
        if (isNaN(num)) return "—"
        var fixed = num.toFixed(decimals !== undefined ? decimals : 2)
        var parts = fixed.split(".")
        parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",")
        return parts.join(".")
    }

    // ── Computed bar display ─────────────────────────────────────────────────
    property var pinnedSymbols: {
        var result = []
        for (var i = 0; i < symbols.length; i++) {
            if (symbols[i].pinned) result.push(symbols[i])
        }
        return result
    }

    property string barDisplayText: {
        if (pinnedSymbols.length === 0) return "Markets"
        var parts = []
        for (var i = 0; i < pinnedSymbols.length; i++) {
            var sym = pinnedSymbols[i]
            var d   = priceData[sym.id]
            if (d && d.close !== undefined && !isNaN(d.close)) {
                var closeVal = d.close
                var label = sym.name + " " + formatNumber(closeVal)
                if (sym.showChangeWhenPinned) {
                    var ch   = d.change || 0
                    var sign = ch >= 0 ? "+" : ""
                    label += " " + sign + formatNumber(ch)
                }
                parts.push(label)
            } else {
                parts.push(sym.name + " …")
            }
        }
        return parts.join("  │  ")
    }

    // ── Interval helpers ─────────────────────────────────────────────────────
    function intervalToMs(interval) {
        var map = {
            "1m":  60000,
            "5m":  300000,
            "15m": 900000,
            "1h":  3600000,
            "1d":  86400000,
            "1w":  604800000,
            "1M":  2592000000
        }
        return map[interval] || 3600000
    }

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
        for (var k in lastFetchTimes)
            newTimes[k] = lastFetchTimes[k]

        for (var i = 0; i < symbols.length; i++) {
            var sym = symbols[i]

            // Price — refresh based on price interval
            var pk  = sym.id + "_price"
            var lp  = newTimes[pk] || 0
            var priceRefresh = intervalToMs(sym.priceInterval)
            if (now - lp >= priceRefresh) {
                doFetch(sym, "price")
                newTimes[pk] = now
            }

            // Graph — use chart range config for refresh timing
            var gk = sym.id + "_graph"
            var lg = newTimes[gk] || 0
            var histConfig = Providers.getHistoryConfig(sym.graphInterval)
            if (now - lg >= histConfig.refreshMs) {
                doFetch(sym, "graph")
                newTimes[gk] = now
            }
        }
        lastFetchTimes = newTimes
    }

    // ── Process-based fetch ──────────────────────────────────────────────────
    Component {
        id: fetchComponent

        Process {
            property string symbolId:       ""
            property string providerName:   ""
            property string fetchType:      "price"
            property string chartRange:     "1M"
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
                if (exitCode === 0 && _buffer.trim())
                    root.onFetchComplete(symbolId, providerName, fetchType, chartRange, _buffer)
                else if (exitCode !== 0)
                    console.warn("[Markets]", symbolId, fetchType, "exited with code", exitCode)
                root._decrementPending(symbolId)
                destroy()
            }
        }
    }

    function doFetch(sym, fetchType) {
        var url
        var tailLines = 0
        if (fetchType === "price") {
            // Map price range to the best candle interval for /q/l/
            var priceInterval = Providers.getPriceInterval(sym.priceInterval)
            url = Providers.buildPriceUrl(sym.id, sym.provider, priceInterval)
        } else {
            // Use chart range config to pick the right candle interval
            var histConfig = Providers.getHistoryConfig(sym.graphInterval)
            url = Providers.buildHistoryUrl(sym.id, sym.provider, histConfig.interval)
            tailLines = histConfig.maxPoints + 2   // +2 for header + safety
        }

        if (!url) return

        var curlCmd = "curl -fsSL --connect-timeout 10 --max-time 20"
                    + " -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64)'"
                    + " '" + url + "'"
        if (tailLines > 0)
            curlCmd += " | tail -n " + tailLines

        var proc = fetchComponent.createObject(root, {
            symbolId:     sym.id,
            providerName: sym.provider,
            fetchType:    fetchType,
            chartRange:   sym.graphInterval || "1M"
        })
        proc.command = ["sh", "-c", curlCmd]
        proc.running = true

        // Track loading state
        var pf = {}
        for (var key in _pendingFetches) pf[key] = _pendingFetches[key]
        pf[sym.id] = (pf[sym.id] || 0) + 1
        _pendingFetches = pf
    }

    // ── Inversion helper ─────────────────────────────────────────────────
    function _isInverted(symbolId) {
        for (var i = 0; i < symbols.length; i++)
            if (symbols[i].id === symbolId) return !!symbols[i].invert
        return false
    }

    function _inv(v) {
        if (v === 0 || isNaN(v)) return 0
        return Math.round(100 / v) / 100   // 1/v rounded to 2 decimals
    }

    function onFetchComplete(symbolId, providerName, fetchType, chartRange, csvText) {
        var invert = _isInverted(symbolId)

        if (fetchType === "price") {
            var parsed = Providers.parsePriceResponse(providerName, csvText)
            if (parsed.length > 0) {
                var latest  = parsed[parsed.length - 1]
                var o = latest.open, h = latest.high, l = latest.low, c = latest.close

                if (invert) {
                    o = _inv(o); h = _inv(h); l = _inv(l); c = _inv(c)
                    // After inversion high/low may swap
                    var tmp = h; h = Math.min(h, l); l = Math.max(tmp, l)
                }

                var newData = {}
                for (var pk in priceData) newData[pk] = priceData[pk]
                newData[symbolId] = {
                    open:   o,
                    high:   h,
                    low:    l,
                    close:  c,
                    date:   latest.date,
                    time:   latest.time,
                    change:        c - o,
                    changePercent: o !== 0
                                   ? ((c - o) / o * 100)
                                   : 0
                }
                priceData = newData
            }
        } else {
            var history = Providers.parseHistoryResponse(providerName, csvText)
            if (history.length === 0)
                console.warn("[Markets]", symbolId, "history returned no data — chart unavailable")
            if (history.length > 0) {
                if (invert) {
                    for (var j = 0; j < history.length; j++) {
                        var pt = history[j]
                        pt.open  = _inv(pt.open)
                        pt.close = _inv(pt.close)
                        var ih = _inv(pt.high), il = _inv(pt.low)
                        pt.high = Math.max(ih, il)
                        pt.low  = Math.min(ih, il)
                    }
                }
                var newGraph = {}
                for (var gk in graphData) newGraph[gk] = graphData[gk]
                // Slice to the appropriate number of data points for the chart range
                var histConfig = Providers.getHistoryConfig(chartRange)
                newGraph[symbolId] = history.slice(-histConfig.maxPoints)
                graphData = newGraph
            }
        }
    }

    // ── Symbol management ────────────────────────────────────────────────────
    function _decrementPending(symId) {
        var pf = {}
        for (var key in _pendingFetches) pf[key] = _pendingFetches[key]
        pf[symId] = Math.max(0, (pf[symId] || 0) - 1)
        if (pf[symId] === 0) delete pf[symId]
        _pendingFetches = pf
    }

    function togglePin(symbolId) {
        var newSymbols = JSON.parse(JSON.stringify(symbols))
        for (var i = 0; i < newSymbols.length; i++) {
            if (newSymbols[i].id === symbolId) {
                newSymbols[i].pinned = !newSymbols[i].pinned
                break
            }
        }
        if (pluginService)
            pluginService.savePluginData(pluginId, "symbols", JSON.stringify(newSymbols))
    }

    function removeSymbol(symbolId) {
        var newSymbols = []
        for (var i = 0; i < symbols.length; i++) {
            if (symbols[i].id !== symbolId)
                newSymbols.push(symbols[i])
        }
        if (pluginService)
            pluginService.savePluginData(pluginId, "symbols", JSON.stringify(newSymbols))
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
        for (var i = 0; i < symbols.length; i++)
            currentIds.push(symbols[i].id)

        for (var j = 0; j < symbols.length; j++) {
            if (_knownSymbolIds.indexOf(symbols[j].id) === -1) {
                doFetch(symbols[j], "price")
                doFetch(symbols[j], "graph")
            }
        }
        _knownSymbolIds = currentIds
    }

    // ── Initial fetch on load ────────────────────────────────────────────────
    Component.onCompleted: {
        // Populate known IDs before enabling change detection
        var ids = []
        for (var i = 0; i < symbols.length; i++)
            ids.push(symbols[i].id)
        _knownSymbolIds = ids
        _initialized = true

        if (symbols.length > 0)
            checkAndFetch()
    }

    // ── Configurable popout rows ─────────────────────────────────────────────
    property int popoutRows: {
        var v = parseInt(pluginData.popoutRows || "5")
        return (isNaN(v) || v < 1) ? 5 : v
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
            showCloseButton: true

            Item {
                width: parent.width
                implicitHeight: root.popoutHeight
                                - popout.headerHeight
                                - popout.detailsHeight
                                - Theme.spacingXL

                // ── Symbol list ──────────────────────────────────────────
                ListView {
                    id: symbolList
                    anchors.left: parent.left
                    anchors.right: scrollIndicator.visible ? scrollIndicator.left : parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    spacing: Theme.spacingS
                    clip: true
                    model: root.symbols
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: SymbolRow {
                        width: symbolList.width
                        symbolData: modelData
                        priceInfo:  root.priceData[modelData.id] || ({})
                        chartData:  root.graphData[modelData.id] || []
                        isLoading:  (root._pendingFetches[modelData.id] || 0) > 0
                        upColor:    root.upColor
                        downColor:  root.downColor

                        onTogglePin:    root.togglePin(modelData.id)
                        onRemoveSymbol: root.removeSymbol(modelData.id)
                    }
                }

                // ── Custom scroll indicator ──────────────────────────────
                Rectangle {
                    id: scrollIndicator
                    visible: root.symbols.length > root.popoutRows
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 4
                    color: "transparent"

                    Rectangle {
                        width: parent.width
                        radius: 2
                        color: Theme.outlineVariant
                        opacity: symbolList.moving ? 0.8 : 0.4

                        property real ratio: symbolList.height / symbolList.contentHeight
                        height: Math.max(20, parent.height * ratio)
                        y: symbolList.contentHeight > symbolList.height
                           ? (symbolList.contentY / (symbolList.contentHeight - symbolList.height)) * (parent.height - height)
                           : 0

                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }
                }

                // ── Empty state ──────────────────────────────────────────
                Column {
                    visible: root.symbols.length === 0
                    anchors.centerIn: parent
                    spacing: Theme.spacingM

                    DankIcon {
                        name: "add_chart"
                        size: 48
                        color: Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    StyledText {
                        text: "No symbols added"
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    StyledText {
                        text: "Open Settings → Markets to add symbols"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }
    }

    popoutWidth:  440
    popoutHeight: {
        // 76 per row + spacingS between + header/details/padding
        var rowH = 76 + Theme.spacingS
        return Math.max(200, popoutRows * rowH + 80)
    }
}
