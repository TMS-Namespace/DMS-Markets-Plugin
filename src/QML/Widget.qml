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

pragma ComponentBehavior: Bound
import QtQuick
import "../JS/Helpers/Constants.js" as JsConstants
import "../JS/Helpers/Helpers.js" as Helpers
import "../JS/Helpers/SymbolErrorMap.js" as SymbolErrors
import "./Helpers"
import "./Services"
import "./Views"
import qs.Common
import qs.Modules.Plugins
import qs.Services

PluginComponent {
    id: root

    readonly property bool _errorHandlerReady: _configureErrorHandler()
    property bool _initialized: false
    property var _knownSymbolFetchSignatures: ({})

    // ── Symbol change detection ───────────────────────────────────────────────
    property var _knownSymbolIds: []
    property string _lastProviderCredentialsSignature: ""
    property var _pendingFetches: ({})

    // The last market data of every symbol is kept on disk (one file per symbol): it is shown right after a start,
    // while the providers are still being asked, and updated in the background whenever a provider answers.
    property string cacheDirectory: ""                  // where the saved market data lives; "" = the user's cache directory
    property bool canFetchAnySymbol: {
        if (symbols.length === 0)
            return false;
        for (let i = 0; i < symbols.length; i++) {
            let providerId = symbols[i].provider || ProvidersManager.defaultId;
            let handler = ProvidersManager.handlerFromId(providerId);
            if (handler && handler.isValidCredential(providerCredentials[providerId] || ""))
                return true;
        }
        return false;
    }
    property color downColor: {
        let savedColor = (pluginData.downColor || "").trim();
        return savedColor !== "" ? savedColor : constants.defaultDownColor;
    }
    property var graphData: ({})
    property var lastFetchTimes: ({})   // when each pull was last started (the schedule)
    readonly property var marketCache: cache
    property int popoutRows: {
        let requestedRows = parseInt(pluginData.popoutRows || constants.defaultPopoutRows);
        return (isNaN(requestedRows) || requestedRows < 1) ? constants.defaultPopoutRows : requestedRows;
    }

    // ── Live state ────────────────────────────────────────────────────────────
    property var priceData: ({})
    property var providerCredentials: dataStorage.readCredentials(pluginData)
    property var refreshedTimes: ({})   // when each pull last succeeded (shown as "refreshed x ago")
    property bool showChartRange: Helpers.pluginDataBool(pluginData.showChartRange)
    property bool showPriceChange: dataStorage.readShowPriceChange(pluginData)
    property bool showProviderName: Helpers.pluginDataBool(pluginData.showProviderName)
    property bool showRefreshedSince: Helpers.pluginDataBool(pluginData.showRefreshedSince)
    property bool showTicker: Helpers.pluginDataBool(pluginData.showTicker)

    // Latest error per symbol and pull (a SymbolErrorMap map: { uid: { price, graph } }), cleared on success.
    property var symbolErrors: ({})
    property var symbols: dataStorage.readCurrentSymbols(pluginData.symbols)

    // ── Settings-driven display properties ────────────────────────────────────
    property color upColor: {
        let savedColor = (pluginData.upColor || "").trim();
        return savedColor !== "" ? savedColor : constants.defaultUpColor;
    }

    // ── Error handling ────────────────────────────────────────────────────────
    // Configured before anything that can fail is evaluated (declaration order matters).
    function _configureErrorHandler() {
        Logger.configure({
            devMode: constants.devMode
        });
        ErrorHandler.configure({
            // DMS's own toast: short message as the title, technical details expandable.
            notify: function (message, details, category) {
                ToastService.showError("Markets: " + message, details, "", category);
            }
        });
        return true;
    }

    // Compare credential settings without changing provider state.
    function _providerCredentialsSignature(credentials) {
        let ids = ProvidersManager.types.map(function (type) {
            return ProvidersManager.idOf(type);
        }).sort();
        let parts = [];
        for (let i = 0; i < ids.length; i++)
            parts.push(ids[i] + "=" + (credentials[ids[i]] || ""));
        return parts.join("|");
    }

    // Shows the saved data of the given symbols (asynchronously read), then calls `proceed`.
    function _restoreThen(symbolList, proceed) {
        let uids = symbolList.map(function (symbol) {
            return symbol.uid;
        });
        let signatures = _symbolFetchSignatureMap(symbolList);
        cache.load(uids, function (records) {
            let currentSignatures = root._symbolFetchSignatureMap(root.symbols);
            uids.forEach(function (uid) {
                if (records[uid] && currentSignatures[uid] === signatures[uid])
                    fetcher.restore(uid, records[uid], signatures[uid]);
            });
            proceed();
        });
    }

    // Publish the latest error for one symbol and fetch type.
    function _setSymbolError(uid, fetchType, record) {
        symbolErrors = SymbolErrors.set(symbolErrors, uid, fetchType, record);
    }

    // What a symbol's fetching depends on, as one comparable string: when it changes, the symbol is refreshed.
    function _symbolFetchSignature(symbol) {
        return Helpers.symbolFetchSignature(symbol, ProvidersManager.defaultId);
    }

    // Index the requested configuration by each symbol handle.
    function _symbolFetchSignatureMap(symbolList) {
        let result = {};
        for (let i = 0; i < symbolList.length; i++)
            result[symbolList[i].uid] = _symbolFetchSignature(symbolList[i]);
        return result;
    }

    layerNamespacePlugin: "markets"
    popoutHeight: {
        let visible = Math.min(popoutRows, symbols.length);
        let totalRows = visible > 0 ? visible : popoutRows;
        return Math.max(constants.popoutMinHeight, totalRows * constants.rowHeight + (totalRows - 1) * Theme.spacingS + constants.popoutPadding);
    }
    popoutWidth: constants.popoutWidth

    // ═══════════════════════════════════════════════════════════════════════
    //  BAR PILLS
    // ═══════════════════════════════════════════════════════════════════════

    horizontalBarPill: Component {
        HorizontalBarPill {
            displayText: symbolManager.barDisplayText
            iconSize: root.iconSize
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  POPOUT
    // ═══════════════════════════════════════════════════════════════════════

    popoutContent: Component {
        PopoutComponent {
            id: popout

            detailsText: root.symbols.length > 0 ? root.symbols.length + " symbol" + (root.symbols.length !== 1 ? "s" : "") + " tracked" : "Add symbols in Settings"
            headerText: constants.barDefaultLabel
            showCloseButton: false

            PopoutPanel {
                downColor: root.downColor
                graphData: root.graphData
                headerOffset: popout.headerHeight + popout.detailsHeight
                implicitHeight: root.popoutHeight - popout.headerHeight - popout.detailsHeight - Theme.spacingXL
                lastFetchTimes: root.refreshedTimes
                pendingFetches: root._pendingFetches
                popoutRows: root.popoutRows
                priceData: root.priceData
                showChartRange: root.showChartRange
                showPriceChange: root.showPriceChange
                showProviderName: root.showProviderName
                showRefreshedSince: root.showRefreshedSince
                showTicker: root.showTicker
                symbolErrors: root.symbolErrors
                symbols: root.symbols
                upColor: root.upColor
                width: parent.width

                onClosePopout: root.closePopout()
                onRefreshAll: fetcher.forceRefreshAll()
                onRefreshSymbol: function (uid) {
                    fetcher.forceRefreshSymbol(uid);
                }
                onRemoveSymbol: function (uid) {
                    symbolManager.removeSymbol(uid);
                }
                onTogglePin: function (uid) {
                    symbolManager.togglePin(uid);
                }
            }
        }
    }
    verticalBarPill: Component {
        VerticalBarPill {
            iconSize: root.iconSize
            shortLabel: symbolManager.pinnedSymbols.length > 0 ? symbolManager.pinnedSymbols[0].name : "MKT"
        }
    }

    Component.onCompleted: {
        // Providers that failed to load are reported once; the others keep working.
        let loadErrors = ProvidersManager.loadErrors;
        for (let errorIndex = 0; errorIndex < loadErrors.length; errorIndex++)
            ErrorHandler.handle("providers", loadErrors[errorIndex].error, {
                context: loadErrors[errorIndex].name
            });
        // Migration may assign uids and rewrite ranges. Saving the migrated list makes DMS deliver it through
        // pluginData again: right away (inside this very call) or later. Neither case may be waited for, so
        // the symbols that already carry a uid are started now, and any that arrive later are picked up by
        // the symbol watcher as new symbols.
        dataStorage.migrateSavedSymbols(pluginData.symbols);
        dataStorage.migrateSettings(pluginData);
        setVisibilityOverride(canFetchAnySymbol);
        let ready = symbols.filter(function (symbol) {
            return !!symbol.uid;
        });
        _knownSymbolIds = ready.map(function (symbol) {
            return symbol.uid;
        });
        _knownSymbolFetchSignatures = _symbolFetchSignatureMap(ready);
        _lastProviderCredentialsSignature = _providerCredentialsSignature(providerCredentials);
        _initialized = true;
        Logger.debug("widget", "initialized: " + symbols.length + " symbols, " + ready.length + " ready to fetch");
        if (ready.length > 0)
            _restoreThen(ready, function () {
                fetcher.startInitialFetches(ready);
            });
    }
    onCanFetchAnySymbolChanged: setVisibilityOverride(canFetchAnySymbol)
    onProviderCredentialsChanged: {
        Logger.debug("widget", "provider credentials changed");
        let signature = _providerCredentialsSignature(providerCredentials);
        if (_initialized && signature !== _lastProviderCredentialsSignature)
            fetcher.forceRefreshAll();
        _lastProviderCredentialsSignature = signature;
    }
    onSymbolsChanged: {
        if (!_initialized)
            return;
        Logger.debug("widget", "symbols changed: " + symbols.length + " symbols");
        // DMS delivers the saved data after the widget has started, and again after every save. A list saved by an
        // older version is migrated and saved whenever it arrives (a no-op for a current one); the migrated list is
        // delivered again and its symbols are then fetched like any new symbols. Migrating is deferred: saving
        // inside this notification would re-enter it with the redelivered data.
        migrationTimer.restart();
        newSymbolChecker.restart();
    }

    // ── QML constants ─────────────────────────────────────────────────────────
    Constants {
        id: constants
    }

    // ── Saved data ────────────────────────────────────────────────────────────
    // All reading and writing of plugin data goes through DataStorage (checked, reported
    // saves; damaged data is backed up rather than discarded).
    DataStorage {
        id: dataStorage

        pluginId: root.pluginId
        pluginService: root.pluginService
    }
    MarketCache {
        id: cache

        directory: root.cacheDirectory !== "" ? root.cacheDirectory : cache.defaultDirectory
        snapshotOf: function (uid) {
            let snapshot = fetcher.snapshotOf(uid);
            let symbol = root.symbols.filter(function (candidate) {
                return candidate.uid === uid;
            })[0];
            if (!snapshot || !symbol)
                return null;
            snapshot.signature = root._symbolFetchSignature(symbol);
            return snapshot;
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────
    MarketDataFetcher {
        id: fetcher

        graphData: root.graphData
        lastFetchTimes: root.lastFetchTimes
        priceData: root.priceData
        providerCredentials: root.providerCredentials
        refreshedTimes: root.refreshedTimes
        symbols: root.symbols

        onFetchTimesUpdated: function (newTimes) {
            root.lastFetchTimes = newTimes;
        }
        onGraphDataReady: function (newGraphData) {
            root.graphData = newGraphData;
        }
        onPendingFetchesUpdated: function (newPending) {
            root._pendingFetches = newPending;
        }
        onPriceDataReady: function (newPriceData) {
            root.priceData = newPriceData;
        }
        onRefreshedTimesUpdated: function (newTimes) {
            root.refreshedTimes = newTimes;
        }
    }
    SymbolManager {
        id: symbolManager

        priceData: root.priceData
        storage: dataStorage
        symbols: root.symbols
    }
    Timer {
        id: newSymbolChecker

        interval: JsConstants.SYMBOL_WATCH_DELAY_MS
        repeat: false

        onTriggered: {
            let currentIds = root.symbols.map(function (symbol) {
                return symbol.uid;
            });
            let currentSignatures = _symbolFetchSignatureMap(root.symbols);
            let previousIds = root._knownSymbolIds;
            // New symbols show their saved data first, then are fetched.
            _restoreThen(root.symbols.filter(function (symbol) {
                return !!symbol.uid && previousIds.indexOf(symbol.uid) === -1;
            }), function () {
                fetcher.fetchNewSymbols(root.symbols, previousIds);
            });
            // A removed symbol's saved data goes with it. (DMS starts with an empty list, but then nothing is known yet,
            // so there is nothing to compare with: only symbols this widget already knew can be removed.)
            previousIds.forEach(function (uid) {
                if (currentIds.indexOf(uid) !== -1)
                    return;
                fetcher.forget(uid);
                root.symbolErrors = Helpers.withoutEntry(root.symbolErrors, uid);
                cache.discard(uid);
            });
            Logger.debug("widget", "checking " + root.symbols.length + " symbols for new or changed ones");
            for (let i = 0; i < root.symbols.length; i++) {
                let symbol = root.symbols[i];
                if (root._knownSymbolIds.indexOf(symbol.uid) !== -1 && root._knownSymbolFetchSignatures[symbol.uid] !== currentSignatures[symbol.uid]) {
                    Logger.debug("widget", symbol.ticker + " changed: refreshing");
                    // What was fetched (and saved) for the old settings would be wrong now: gone until the new answer.
                    fetcher.forget(symbol.uid);
                    cache.discard(symbol.uid);
                    fetcher.forceRefreshSymbol(symbol.uid);
                }
            }
            root._knownSymbolIds = currentIds;
            root._knownSymbolFetchSignatures = currentSignatures;
        }
    }
    Timer {
        id: migrationTimer

        interval: 0
        repeat: false

        onTriggered: dataStorage.migrateSavedSymbols(root.pluginData.symbols)
    }

    // ── Per-symbol fetch results ─────────────────────────────────────────────
    Connections {
        // Forward fetch failures and recoveries to the displayed error map.
        function onSymbolErrorChanged(uid, fetchType, record) {
            root._setSymbolError(uid, fetchType, record);
        }
        // New data from a provider is shown first (already done), then saved in the background.
        function onSymbolStored(uid) {
            cache.markDirty(uid);
        }

        target: fetcher
    }
}
