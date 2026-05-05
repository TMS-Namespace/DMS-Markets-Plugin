// Widget.qml — Main DMS bar widget with popout
//
// This file is intentionally thin: it owns the live state (priceData,
// graphData, …), declares the Settings-driven properties, instantiates
// the helper items (MarketDataFetcher, SymbolManager), and wires up the
// bar-pill and popout UI components.
//
// All fetch/parse logic lives in QML/Helpers/MarketDataFetcher.qml.
// Symbol management and bar-text computation live in QML/Helpers/SymbolManager.qml.
// UI-only components live in QML/Views/.

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
import "./Helpers"
import "./Views"

PluginComponent {
    id: root

    layerNamespacePlugin: "markets"

    onHasApiKeyChanged: setVisibilityOverride(hasApiKey)

    // ── QML constants ─────────────────────────────────────────────────────────
    Constants { id: c }

    // ── Settings-driven display properties ────────────────────────────────────
    property color upColor: {
        var v = (pluginData.upColor || "").trim()
        return v !== "" ? v : c.defaultUpColor
    }
    property color downColor: {
        var v = (pluginData.downColor || "").trim()
        return v !== "" ? v : c.defaultDownColor
    }

    property bool showTicker:         Helpers.pluginDataBool(pluginData.showTicker)
    property bool showPriceRange:     Helpers.pluginDataBool(pluginData.showPriceRange)
    property bool showChartRange:     Helpers.pluginDataBool(pluginData.showChartRange)
    property bool showRefreshedSince: Helpers.pluginDataBool(pluginData.showRefreshedSince)

    property int popoutRows: {
        var n = parseInt(pluginData.popoutRows || c.defaultPopoutRows)
        return (isNaN(n) || n < 1) ? c.defaultPopoutRows : n
    }

    // Deobfuscate the stored key once and share it — used for validation and fetching.
    property string _apiKey: Helpers.deobfuscate(pluginData.stooqApiKey || "")
    property bool hasApiKey: {
        var k = _apiKey.trim()
        return k.length >= c.apiKeyMinLength && k.length <= c.apiKeyMaxLength
    }

    // ── Persisted symbol list ─────────────────────────────────────────────────
    property var symbols: {
        try { return JSON.parse(pluginData.symbols || "[]") }
        catch (e) { return [] }
    }

    // ── Live state ────────────────────────────────────────────────────────────
    property var priceData:           ({})
    property var graphData:           ({})
    property var lastFetchTimes:      ({})
    property var _lastFullGraphFetch: ({})
    property var _pendingFetches:     ({})

    // ── Helpers ───────────────────────────────────────────────────────────────
    MarketDataFetcher {
        id: fetcher
        apiKey:              root._apiKey
        symbols:             root.symbols
        priceData:           root.priceData
        graphData:           root.graphData
        lastFetchTimes:      root.lastFetchTimes
        _pendingFetches:     root._pendingFetches
        _lastFullGraphFetch: root._lastFullGraphFetch

        onPriceDataReady:          function(newPriceData)  { root.priceData           = newPriceData  }
        onGraphDataReady:          function(newGraphData)  { root.graphData           = newGraphData  }
        onFetchTimesUpdated:       function(newTimes)      { root.lastFetchTimes      = newTimes      }
        onPendingFetchesUpdated:   function(newPending)    { root._pendingFetches     = newPending    }
        onFullGraphFetchUpdated:   function(newFullFetch)  { root._lastFullGraphFetch = newFullFetch  }
    }

    SymbolManager {
        id: symbolManager
        pluginId:      root.pluginId
        pluginService: root.pluginService
        symbols:       root.symbols
        priceData:     root.priceData
    }

    // ── Symbol change detection ───────────────────────────────────────────────
    property var  _knownSymbolIds: []
    property bool _initialized:    false

    Timer {
        id: newSymbolChecker
        interval: 500
        repeat: false
        onTriggered: {
            var currentIds = symbols.map(function(s) { return s.id })
            fetcher.fetchNewSymbols(symbols, _knownSymbolIds)
            _knownSymbolIds = currentIds
        }
    }

    onSymbolsChanged: {
        if (c.devMode && _initialized) console.log("[Markets/Widget] symbols changed —", symbols.length, "symbols")
        if (_initialized) newSymbolChecker.restart()
    }

    Component.onCompleted: {
        setVisibilityOverride(hasApiKey)
        _knownSymbolIds = symbols.map(function(s) { return s.id })
        _initialized    = true
        if (c.devMode) console.log("[Markets/Widget] initialized —", symbols.length, "symbols")
        if (symbols.length > 0)
            fetcher.startInitialFetches(symbols)
    }

    // ── Token error handling ──────────────────────────────────────────────────
    Timer {
        id: tokenErrorCooldown
        interval: c.tokenErrorCooldownMs
        repeat: false
        property bool active: false
        onTriggered: active = false
    }

    Connections {
        target: fetcher
        function onTokenError(message) {
            if (!tokenErrorCooldown.active) {
                tokenErrorCooldown.active = true
                tokenErrorCooldown.restart()
                ToastService.showError("Markets", message)
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  BAR PILLS
    // ═══════════════════════════════════════════════════════════════════════

    horizontalBarPill: Component {
        HorizontalBarPill {
            iconSize:    root.iconSize
            displayText: symbolManager.barDisplayText
        }
    }

    verticalBarPill: Component {
        VerticalBarPill {
            iconSize:   root.iconSize
            shortLabel: symbolManager.pinnedSymbols.length > 0
                        ? symbolManager.pinnedSymbols[0].name
                        : "MKT"
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  POPOUT
    // ═══════════════════════════════════════════════════════════════════════

    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText:      c.barDefaultLabel
            detailsText:     root.symbols.length > 0
                             ? root.symbols.length + " symbol"
                               + (root.symbols.length !== 1 ? "s" : "") + " tracked"
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

                onTogglePin:     function(symbolId) { symbolManager.togglePin(symbolId) }
                onRemoveSymbol:  function(symbolId) { symbolManager.removeSymbol(symbolId) }
                onRefreshSymbol: function(symbolId) { fetcher.forceRefreshSymbol(symbolId) }
                onRefreshAll:    fetcher.forceRefreshAll()
                onClosePopout:   root.closePopout()
            }
        }
    }

    popoutWidth:  c.popoutWidth
    popoutHeight: {
        var visible   = Math.min(popoutRows, symbols.length)
        var totalRows = visible > 0 ? visible : popoutRows
        return Math.max(c.popoutMinHeight,
                        totalRows * c.rowHeight
                        + (totalRows - 1) * Theme.spacingS
                        + c.popoutPadding)
    }
}

