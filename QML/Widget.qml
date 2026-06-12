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
import "../JS/ProviderBootstrap.js" as ProviderBootstrap
import "../JS/Helpers.js" as Helpers
import "../JS/Constants.js" as JsK
import "./Helpers"
import "./Views"

PluginComponent {
    id: root

    layerNamespacePlugin: "markets"

    // ── QML constants ─────────────────────────────────────────────────────────
    Constants { id: c }

    readonly property int providerRegistrationCount: ProviderBootstrap.ensureProvidersRegistered()

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

    // ── Persisted symbol list ─────────────────────────────────────────────────
    property var symbols: {
        try { return JSON.parse(pluginData.symbols || "[]") }
        catch (e) { return [] }
    }

    property var providerCredentials: {
        var result = {}
        var ids = Providers.getProviderIds()
        for (var i = 0; i < ids.length; i++) {
            var providerId = ids[i]
            var meta = Providers.getProviderMeta(providerId)
            if (meta.requiresCredential)
                result[providerId] = Helpers.deobfuscate(pluginData[meta.credentialSettingKey] || "")
        }
        return result
    }
    property string _lastProviderCredentialsSignature: ""

    property bool canFetchAnySymbol: {
        if (symbols.length === 0) return false
        for (var i = 0; i < symbols.length; i++) {
            var providerId = symbols[i].provider || Providers.getDefaultProviderId()
            if (Providers.isValidCredential(providerId, providerCredentials[providerId] || ""))
                return true
        }
        return false
    }

    onCanFetchAnySymbolChanged: setVisibilityOverride(canFetchAnySymbol)
    onProviderCredentialsChanged: {
        var signature = _providerCredentialsSignature(providerCredentials)
        if (_initialized && signature !== _lastProviderCredentialsSignature)
            fetcher.forceRefreshAll()
        _lastProviderCredentialsSignature = signature
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
        providerCredentials: root.providerCredentials
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
    property var  _knownSymbolFetchSignatures: ({})
    property bool _initialized:    false

    function _providerCredentialsSignature(credentials) {
        var ids = Providers.getProviderIds().sort()
        var parts = []
        for (var i = 0; i < ids.length; i++)
            parts.push(ids[i] + "=" + (credentials[ids[i]] || ""))
        return parts.join("|")
    }

    function _symbolFetchSignature(symbol) {
        return JSON.stringify({
            provider:      symbol.provider || Providers.getDefaultProviderId(),
            priceInterval: symbol.priceInterval || "1h",
            graphInterval: symbol.graphInterval || "1M",
            invert:        Helpers.boolValue(symbol.invert, false)
        })
    }

    function _symbolFetchSignatureMap(symbolList) {
        var result = {}
        for (var i = 0; i < symbolList.length; i++)
            result[symbolList[i].id] = _symbolFetchSignature(symbolList[i])
        return result
    }

    Timer {
        id: newSymbolChecker
        interval: JsK.SYMBOL_WATCH_DELAY_MS
        repeat: false
        onTriggered: {
            var currentIds = symbols.map(function(s) { return s.id })
            var currentSignatures = _symbolFetchSignatureMap(symbols)
            fetcher.fetchNewSymbols(symbols, _knownSymbolIds)
            for (var i = 0; i < symbols.length; i++) {
                var sym = symbols[i]
                if (_knownSymbolIds.indexOf(sym.id) !== -1
                        && _knownSymbolFetchSignatures[sym.id] !== currentSignatures[sym.id]) {
                    fetcher.forceRefreshSymbol(sym.id)
                }
            }
            _knownSymbolIds = currentIds
            _knownSymbolFetchSignatures = currentSignatures
        }
    }

    onSymbolsChanged: {
        if (c.devMode && _initialized) console.log("[Markets/Widget] symbols changed —", symbols.length, "symbols")
        if (_initialized) newSymbolChecker.restart()
    }

    Component.onCompleted: {
        setVisibilityOverride(canFetchAnySymbol)
        _knownSymbolIds = symbols.map(function(s) { return s.id })
        _knownSymbolFetchSignatures = _symbolFetchSignatureMap(symbols)
        _lastProviderCredentialsSignature = _providerCredentialsSignature(providerCredentials)
        _initialized    = true
        if (c.devMode) console.log("[Markets/Widget] initialized —", symbols.length, "symbols")
        if (symbols.length > 0)
            fetcher.startInitialFetches(symbols)
    }

    // ── Provider credential error handling ───────────────────────────────────
    Timer {
        id: credentialErrorCooldown
        interval: c.credentialErrorCooldownMs
        repeat: false
        property bool active: false
        onTriggered: active = false
    }

    Connections {
        target: fetcher
        function onCredentialError(message) {
            if (!credentialErrorCooldown.active) {
                credentialErrorCooldown.active = true
                credentialErrorCooldown.restart()
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
