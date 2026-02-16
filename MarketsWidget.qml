// MarketsWidget.qml — Main DMS bar widget with popout
//
// Shows pinned market symbols in the bar and provides a popout panel listing
// all tracked symbols with live prices, change indicators, and sparkline charts.
//
// Data fetching is abstracted through providers.js — the widget itself knows
// nothing about Stooq or any specific data source.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "providers.js" as Providers

PluginComponent {
    id: root

    layerNamespacePlugin: "markets"

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
                var ch   = d.change || 0
                var sign = ch >= 0 ? "+" : ""
                parts.push(sym.name + " " + d.close.toFixed(2) + " " + sign + ch.toFixed(2))
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

            // Price
            var pk  = sym.id + "_price"
            var lp  = newTimes[pk] || 0
            if (now - lp >= intervalToMs(sym.priceInterval)) {
                doFetch(sym, "price")
                newTimes[pk] = now
            }

            // Graph
            var gk = sym.id + "_graph"
            var lg = newTimes[gk] || 0
            if (now - lg >= intervalToMs(sym.graphInterval)) {
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
            property string symbolId:     ""
            property string providerName: ""
            property string fetchType:    "price"
            property string _buffer:      ""

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
                    root.onFetchComplete(symbolId, providerName, fetchType, _buffer)
                destroy()
            }
        }
    }

    function doFetch(sym, fetchType) {
        var url
        if (fetchType === "price")
            url = Providers.buildPriceUrl(sym.id, sym.provider, sym.priceInterval)
        else
            url = Providers.buildHistoryUrl(sym.id, sym.provider, sym.graphInterval)

        if (!url) return

        var curlCmd = "curl -fsSL --connect-timeout 10 --max-time 20 --proto '=https' --tlsv1.2"
                    + " -A '' -b '' '" + url + "'"

        var proc = fetchComponent.createObject(root, {
            symbolId:     sym.id,
            providerName: sym.provider,
            fetchType:    fetchType
        })
        proc.command = ["sh", "-c", curlCmd]
        proc.running = true
    }

    function onFetchComplete(symbolId, providerName, fetchType, csvText) {
        if (fetchType === "price") {
            var parsed = Providers.parsePriceResponse(providerName, csvText)
            if (parsed.length > 0) {
                var latest  = parsed[parsed.length - 1]
                var newData = {}
                for (var pk in priceData) newData[pk] = priceData[pk]
                newData[symbolId] = {
                    open:   latest.open,
                    high:   latest.high,
                    low:    latest.low,
                    close:  latest.close,
                    date:   latest.date,
                    time:   latest.time,
                    change:        latest.close - latest.open,
                    changePercent: latest.open !== 0
                                   ? ((latest.close - latest.open) / latest.open * 100)
                                   : 0
                }
                priceData = newData
            }
        } else {
            var history = Providers.parseHistoryResponse(providerName, csvText)
            if (history.length > 0) {
                var newGraph = {}
                for (var gk in graphData) newGraph[gk] = graphData[gk]
                // Keep only the last 50 data points for the sparkline
                newGraph[symbolId] = history.slice(-50)
                graphData = newGraph
            }
        }
    }

    // ── Symbol management ────────────────────────────────────────────────────
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
                    anchors.fill: parent
                    spacing: Theme.spacingS
                    clip: true
                    model: root.symbols

                    delegate: SymbolRow {
                        width: symbolList.width
                        symbolData: modelData
                        priceInfo:  root.priceData[modelData.id] || ({})
                        chartData:  root.graphData[modelData.id] || []

                        onTogglePin:    root.togglePin(modelData.id)
                        onRemoveSymbol: root.removeSymbol(modelData.id)
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
    popoutHeight: 500
}
