// Widget.qml - Main DMS bar widget with popout
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
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "../JS/Helpers/Helpers.js" as Helpers
import "../JS/Helpers/SymbolErrorMap.js" as SymbolErrors
import "../JS/Helpers/Constants.js" as JsConstants
import "./Helpers"
import "./Services"
import "./Views"

PluginComponent {
    id: root

    layerNamespacePlugin: "markets"

    // ── QML constants ─────────────────────────────────────────────────────────
    Constants { id: constants }

    // ── Settings-driven display properties ────────────────────────────────────
    property color upColor: {
        var savedColor = (pluginData.upColor || "").trim()
        return savedColor !== "" ? savedColor : constants.defaultUpColor
    }
    property color downColor: {
        var savedColor = (pluginData.downColor || "").trim()
        return savedColor !== "" ? savedColor : constants.defaultDownColor
    }

    property bool showTicker:         Helpers.pluginDataBool(pluginData.showTicker)
    property bool showPriceChange:    storage.readShowPriceChange(pluginData)
    property bool showChartRange:     Helpers.pluginDataBool(pluginData.showChartRange)
    property bool showProviderName:   Helpers.pluginDataBool(pluginData.showProviderName)
    property bool showRefreshedSince: Helpers.pluginDataBool(pluginData.showRefreshedSince)

    property int popoutRows: {
        var requestedRows = parseInt(pluginData.popoutRows || constants.defaultPopoutRows)
        return (isNaN(requestedRows) || requestedRows < 1) ? constants.defaultPopoutRows : requestedRows
    }

    // ── Error handling ────────────────────────────────────────────────────────
    // Configured before anything that can fail is evaluated (declaration order matters).
    function _configureErrorHandler() {
        Logger.configure({ devMode: constants.devMode })
        ErrorHandler.configure({
            // DMS's own toast: short message as the title, technical details expandable.
            notify: function(message, details, category) {
                ToastService.showError("Markets: " + message, details, "", category)
            }
        })
        return true
    }
    readonly property bool _errorHandlerReady: _configureErrorHandler()

    // Latest error per symbol and pull (a SymbolErrorMap map: { uid: { price, graph } }), cleared on success.
    property var symbolErrors: ({})

    // Publish the latest error for one symbol and fetch type.
    function _setSymbolError(uid, fetchType, record) {
        symbolErrors = SymbolErrors.set(symbolErrors, uid, fetchType, record)
    }

    // ── Saved data ────────────────────────────────────────────────────────────
    // All reading and writing of plugin data goes through DataStorage (checked, reported
    // saves; damaged data is backed up rather than discarded).
    DataStorage {
        id: storage
        pluginId:      root.pluginId
        pluginService: root.pluginService
    }

    // The last market data of every symbol is kept on disk (one file per symbol): it is shown right after a start,
    // while the providers are still being asked, and updated in the background whenever a provider answers.
    property string cacheDirectory: ""                  // where the saved market data lives; "" = the user's cache directory
    readonly property var marketCache: cache
    MarketCache {
        id: cache
        directory: root.cacheDirectory !== "" ? root.cacheDirectory : cache.defaultDirectory
        snapshotOf: function(uid) {
            var snapshot = fetcher.snapshotOf(uid)
            var symbol = root.symbols.filter(function(candidate) { return candidate.uid === uid })[0]
            if (!snapshot || !symbol) return null
            snapshot.signature = root._symbolFetchSignature(symbol)
            return snapshot
        }
    }

    property var symbols: storage.readCurrentSymbols(pluginData.symbols)

    property var providerCredentials: storage.readCredentials(pluginData)
    property string _lastProviderCredentialsSignature: ""

    property bool canFetchAnySymbol: {
        if (symbols.length === 0) return false
        for (var i = 0; i < symbols.length; i++) {
            var providerId = symbols[i].provider || ProvidersManager.defaultId
            var handler = ProvidersManager.handlerFromId(providerId)
            if (handler && handler.isValidCredential(providerCredentials[providerId] || ""))
                return true
        }
        return false
    }

    onCanFetchAnySymbolChanged: setVisibilityOverride(canFetchAnySymbol)
    onProviderCredentialsChanged: {
        Logger.debug("widget", "provider credentials changed")
        var signature = _providerCredentialsSignature(providerCredentials)
        if (_initialized && signature !== _lastProviderCredentialsSignature)
            fetcher.forceRefreshAll()
        _lastProviderCredentialsSignature = signature
    }

    // ── Live state ────────────────────────────────────────────────────────────
    property var priceData:           ({})
    property var graphData:           ({})
    property var lastFetchTimes:      ({})   // when each pull was last started (the schedule)
    property var refreshedTimes:      ({})   // when each pull last succeeded (shown as "refreshed x ago")
    property var _pendingFetches:     ({})

    // ── Helpers ───────────────────────────────────────────────────────────────
    MarketDataFetcher {
        id: fetcher
        providerCredentials: root.providerCredentials
        symbols:             root.symbols
        priceData:           root.priceData
        graphData:           root.graphData
        lastFetchTimes:      root.lastFetchTimes
        refreshedTimes:      root.refreshedTimes

        onPriceDataReady:          function(newPriceData)  { root.priceData           = newPriceData  }
        onGraphDataReady:          function(newGraphData)  { root.graphData           = newGraphData  }
        onFetchTimesUpdated:       function(newTimes)      { root.lastFetchTimes      = newTimes      }
        onRefreshedTimesUpdated:   function(newTimes)      { root.refreshedTimes      = newTimes      }
        onPendingFetchesUpdated:   function(newPending)    { root._pendingFetches     = newPending    }
    }

    SymbolManager {
        id: symbolManager
        storage:       storage
        symbols:       root.symbols
        priceData:     root.priceData
    }

    // ── Symbol change detection ───────────────────────────────────────────────
    property var  _knownSymbolIds: []
    property var  _knownSymbolFetchSignatures: ({})
    property bool _initialized:    false

    // Compare credential settings without changing provider state.
    function _providerCredentialsSignature(credentials) {
        var ids = ProvidersManager.types.map(function(type) { return ProvidersManager.idOf(type) }).sort()
        var parts = []
        for (var i = 0; i < ids.length; i++)
            parts.push(ids[i] + "=" + (credentials[ids[i]] || ""))
        return parts.join("|")
    }

    // What a symbol's fetching depends on, as one comparable string: when it changes, the symbol is refreshed.
    function _symbolFetchSignature(symbol) {
        return Helpers.symbolFetchSignature(symbol, ProvidersManager.defaultId)
    }

    // Index the requested configuration by each symbol handle.
    function _symbolFetchSignatureMap(symbolList) {
        var result = {}
        for (var i = 0; i < symbolList.length; i++)
            result[symbolList[i].uid] = _symbolFetchSignature(symbolList[i])
        return result
    }

    // Shows the saved data of the given symbols (asynchronously read), then calls `proceed`.
    function _restoreThen(symbolList, proceed) {
        var uids = symbolList.map(function(symbol) { return symbol.uid })
        var signatures = _symbolFetchSignatureMap(symbolList)
        cache.load(uids, function(records) {
            var currentSignatures = root._symbolFetchSignatureMap(root.symbols)
            uids.forEach(function(uid) {
                if (records[uid] && currentSignatures[uid] === signatures[uid])
                    fetcher.restore(uid, records[uid], signatures[uid])
            })
            proceed()
        })
    }

    Timer {
        id: newSymbolChecker
        interval: JsConstants.SYMBOL_WATCH_DELAY_MS
        repeat: false
        onTriggered: {
            var currentIds = symbols.map(function(symbol) { return symbol.uid })
            var currentSignatures = _symbolFetchSignatureMap(symbols)
            var previousIds = _knownSymbolIds
            // New symbols show their saved data first, then are fetched.
            _restoreThen(symbols.filter(function(symbol) { return !!symbol.uid && previousIds.indexOf(symbol.uid) === -1 }),
                         function() { fetcher.fetchNewSymbols(symbols, previousIds) })
            // A removed symbol's saved data goes with it. (DMS starts with an empty list, but then nothing is known yet,
            // so there is nothing to compare with: only symbols this widget already knew can be removed.)
            previousIds.forEach(function(uid) { if (currentIds.indexOf(uid) === -1) cache.discard(uid) })
            Logger.debug("widget", "checking " + symbols.length + " symbols for new or changed ones")
            for (var i = 0; i < symbols.length; i++) {
                var symbol = symbols[i]
                if (_knownSymbolIds.indexOf(symbol.uid) !== -1
                        && _knownSymbolFetchSignatures[symbol.uid] !== currentSignatures[symbol.uid]) {
                    Logger.debug("widget", symbol.ticker + " changed: refreshing")
                    // What was fetched (and saved) for the old settings would be wrong now: gone until the new answer.
                    fetcher.forget(symbol.uid)
                    cache.discard(symbol.uid)
                    fetcher.forceRefreshSymbol(symbol.uid)
                }
            }
            _knownSymbolIds = currentIds
            _knownSymbolFetchSignatures = currentSignatures
        }
    }

    onSymbolsChanged: {
        if (!_initialized) return
        Logger.debug("widget", "symbols changed: " + symbols.length + " symbols")
        // DMS delivers the saved data after the widget has started, and again after every save. A list saved by an
        // older version is migrated and saved whenever it arrives (a no-op for a current one); the migrated list is
        // delivered again and its symbols are then fetched like any new symbols. Migrating is deferred: saving
        // inside this notification would re-enter it with the redelivered data.
        migrationTimer.restart()
        newSymbolChecker.restart()
    }

    Timer {
        id: migrationTimer
        interval: 0
        repeat: false
        onTriggered: storage.migrateSavedSymbols(pluginData.symbols)
    }

    Component.onCompleted: {
        // Providers that failed to load are reported once; the others keep working.
        var loadErrors = ProvidersManager.loadErrors
        for (var errorIndex = 0; errorIndex < loadErrors.length; errorIndex++)
            ErrorHandler.handle("providers", loadErrors[errorIndex].error, { context: loadErrors[errorIndex].name })
        // Migration may assign uids and rewrite ranges. Saving the migrated list makes DMS deliver it through
        // pluginData again: right away (inside this very call) or later. Neither case may be waited for, so
        // the symbols that already carry a uid are started now, and any that arrive later are picked up by
        // the symbol watcher as new symbols.
        storage.migrateSavedSymbols(pluginData.symbols)
        storage.migrateSettings(pluginData)
        setVisibilityOverride(canFetchAnySymbol)
        var ready = symbols.filter(function(symbol) { return !!symbol.uid })
        _knownSymbolIds = ready.map(function(symbol) { return symbol.uid })
        _knownSymbolFetchSignatures = _symbolFetchSignatureMap(ready)
        _lastProviderCredentialsSignature = _providerCredentialsSignature(providerCredentials)
        _initialized = true
        Logger.debug("widget", "initialized: " + symbols.length + " symbols, " + ready.length + " ready to fetch")
        if (ready.length > 0)
            _restoreThen(ready, function() { fetcher.startInitialFetches(ready) })
    }

    // ── Per-symbol fetch results ─────────────────────────────────────────────
    Connections {
        target: fetcher
        // Forward fetch failures and recoveries to the displayed error map.
        function onSymbolErrorChanged(uid, fetchType, record) {
            root._setSymbolError(uid, fetchType, record)
        }
        // New data from a provider is shown first (already done), then saved in the background.
        function onSymbolStored(uid) { cache.markDirty(uid) }
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

            headerText:      constants.barDefaultLabel
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
                symbolErrors:   root.symbolErrors
                lastFetchTimes: root.refreshedTimes
                upColor:        root.upColor
                downColor:      root.downColor
                showTicker:         root.showTicker
                showPriceChange:     root.showPriceChange
                showChartRange:     root.showChartRange
                showProviderName:   root.showProviderName
                showRefreshedSince: root.showRefreshedSince
                popoutRows:     root.popoutRows
                headerOffset:   popout.headerHeight + popout.detailsHeight

                onTogglePin:     function(uid) { symbolManager.togglePin(uid) }
                onRemoveSymbol:  function(uid) { symbolManager.removeSymbol(uid) }
                onRefreshSymbol: function(uid) { fetcher.forceRefreshSymbol(uid) }
                onRefreshAll:    fetcher.forceRefreshAll()
                onClosePopout:   root.closePopout()
            }
        }
    }

    popoutWidth:  constants.popoutWidth
    popoutHeight: {
        var visible   = Math.min(popoutRows, symbols.length)
        var totalRows = visible > 0 ? visible : popoutRows
        return Math.max(constants.popoutMinHeight,
                        totalRows * constants.rowHeight
                        + (totalRows - 1) * Theme.spacingS
                        + constants.popoutPadding)
    }
}
