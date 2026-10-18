// MarketDataFetcher.qml - decides WHEN to pull data and what to do with the answers.
//
// It does not run requests, retry them, or understand any provider's data format:
//   • ProviderHandler  runs a request, retries transient failures, and returns the final ProviderResponse
//     together with the newest candles the pull asked for (parsed by the provider's own parser, so each
//     provider's format stays its own: Yahoo JSON, Wise JSON, Stooq CSV)
// What remains here is scheduling (the live price, the change reference and the chart history are
// independent pulls, each refreshed as often as its own resolution), post-processing that is the same for
// every provider (inversion, the price candle), and
// publishing the results - or the symbol's error - to the widget.
//
// Symbols are keyed everywhere by their internal `uid`; the `ticker` is only used to build requests.
// Failures never get lost: the final outcome of every pull, success or error, is published per
// symbol and pull via symbolErrorChanged so the symbol's card can show it.
//
// Widget.qml owns the state (priceData / graphData / …) and passes them in
// as read/write properties; this item mutates them via the parent bindings.

import QtQuick
import "../Contracts"
import "../Services"
import "../../JS/Helpers/Helpers.js" as Helpers
import "../../JS/Helpers/Constants.js" as JsConstants
import "../../JS/Contracts/PluginError.js" as PluginError
import "../../JS/Contracts/FetchType.js" as FetchType
import "../../JS/Helpers/SeriesRules.js" as SeriesRules
import "../../JS/Helpers/PriceRules.js" as PriceRules
import "../../JS/Helpers/SelectionPolicy.js" as SelectionPolicy

Item {
    id: root

    // ── Inputs (bound from Widget.qml) ────────────────────────────────────────
    property var    providerCredentials: ({})
    property var    symbols:             []
    property var    priceData:           ({})
    property var    graphData:           ({})
    property var    lastFetchTimes:      ({})    // when each pull was last STARTED (drives the schedule)
    property var    refreshedTimes:      ({})    // when each pull last SUCCEEDED (what "refreshed x min ago" shows, and what is saved)
    // Per symbol uid: the close of the period before the current one (at the change resolution), as the
    // provider reports it. The price's change is measured against it, so it matches the provider's quote page.
    property var    _references:         ({})

    onProviderCredentialsChanged: _syncProviderCredentials()
    Component.onCompleted: { _connectHandlers(); _syncProviderCredentials() }

    // ── Signals ───────────────────────────────────────────────────────────────
    // Emit updated copies so Widget.qml can assign them back to its properties.
    signal priceDataReady(var newPriceData)
    signal graphDataReady(var newGraphData)
    signal fetchTimesUpdated(var newTimes)
    signal refreshedTimesUpdated(var newTimes)
    // New market data of this symbol was stored (from a provider): it is worth saving.
    signal symbolStored(string uid)
    signal pendingFetchesUpdated(var newPending)
    // Result of the latest pull of one kind (a FetchType) for one symbol:
    // `record` is null when it succeeded, otherwise the ErrorRecord.
    signal symbolErrorChanged(string uid, string fetchType, var record)

    // ── Calling the providers ─────────────────────────────────────────────────
    // Every provider is reached through its ProviderHandler (from ProvidersManager), which runs the
    // request, retries transient failures, and reports each call's final result. The loading state
    // is the sum of what all handlers have pending.
    property var _connected: []

    // Subscribe to the current provider handlers and detach the old ones.
    function _connectHandlers() {
        _connected.forEach(function(handler) {
            handler.pendingChanged.disconnect(_publishPending)
            handler.finished.disconnect(_onResponse)
        })
        _connected = ProvidersManager.types.map(function(type) { return ProvidersManager.handlerFor(type) })
        _connected.forEach(function(handler) {
            handler.pendingChanged.connect(_publishPending)
            handler.finished.connect(_onResponse)
        })
    }

    // Combine pending request counts from all provider handlers.
    function _publishPending() {
        let total = {}
        _connected.forEach(function(handler) {
            for (let uid in handler.pending) total[uid] = (total[uid] || 0) + handler.pending[uid]
        })
        pendingFetchesUpdated(total)
    }

    Connections {
        target: ProvidersManager
        // Reconnect when the provider manager replaces its handlers.
        function onHandlersChanged() { root._connectHandlers() }
    }

    Component { id: contextType; FetchContext {} }
    Component { id: priceType;   PriceInfo {} }

    // ── Polling timer ─────────────────────────────────────────────────────────
    Timer {
        id: checkTimer
        interval: JsConstants.POLL_INTERVAL_MS
        running: root.symbols.length > 0
        repeat: true
        onTriggered: _checkAndFetch()
    }

    // Apply the current credentials through each provider facade.
    function _syncProviderCredentials() {
        for (let providerId in providerCredentials) {
            let handler = ProvidersManager.handlerFromId(providerId)
            if (handler) handler.setCredential(providerCredentials[providerId])
            Logger.debug("fetcher", "credential for " + providerId + ": " + (providerCredentials[providerId] ? "set" : "empty"))
        }
    }

    // Each pull is due once its own resolution has elapsed since the last one.
    function _checkAndFetch() {
        let now      = Date.now()
        let newTimes = Helpers.copyOf(lastFetchTimes)

        for (let i = 0; i < symbols.length; i++) {
            let symbol = symbols[i]
            if (!symbol.uid) continue

            let selection           = _selectionFor(symbol)
            let priceKey      = FetchType.timeKey(symbol.uid, FetchType.Values.PRICE)
            if (now - (newTimes[priceKey] || 0) >= Helpers.resolutionToMs(selection.priceResolution)) {
                doFetch(symbol, FetchType.Values.PRICE, selection)
                newTimes[priceKey] = now
            }

            let changeKey     = FetchType.timeKey(symbol.uid, FetchType.Values.CHANGE)
            if (now - (newTimes[changeKey] || 0) >= SelectionPolicy.changeRefreshMs(selection.changeResolution)) {
                doFetch(symbol, FetchType.Values.CHANGE, selection)
                newTimes[changeKey] = now
            }

            let graphKey      = FetchType.timeKey(symbol.uid, FetchType.Values.GRAPH)
            if (now - (newTimes[graphKey] || 0) >= Helpers.resolutionToMs(selection.chartResolution)) {
                doFetch(symbol, FetchType.Values.GRAPH, selection)
                newTimes[graphKey] = now
            }
        }
        fetchTimesUpdated(newTimes)
    }

    // Saved symbols are migrated on load (see DataStorage.migrate); this is the same
    // resolution applied defensively to any symbol not yet migrated.
    function _selectionFor(symbol) {
        let handler = ProvidersManager.handlerFromId(symbol.provider || ProvidersManager.defaultId)
        return handler ? handler.clampSelection(symbol) : symbol   // an unavailable provider is reported by doFetch
    }

    // Recheck at delivery too: shared handlers can report calls started by another widget.
    function _isLive(callContext) {
        let symbol = _findSymbol(callContext.uid)
        return symbol !== null && (!callContext.signature
                || callContext.signature === Helpers.symbolFetchSignature(symbol, ProvidersManager.defaultId))
    }

    // Find the current saved symbol by its internal handle.
    function _findSymbol(uid) {
        for (let i = 0; i < symbols.length; i++)
            if (symbols[i].uid === uid) return symbols[i]
        return null
    }

    // ── Public: start a fetch ─────────────────────────────────────────────────
    // `selection` (optional) is the symbol's clamped selection when the caller already has it.
    function doFetch(symbol, fetchType, knownSelection) {
        if (!symbol.uid) {
            Logger.debug("fetcher", "skipped a symbol without an id (not migrated yet): " + symbol.name + " " + fetchType)
            return
        }
        Logger.debug("fetcher", "fetch " + symbol.ticker + " " + fetchType)
        let providerId = symbol.provider || ProvidersManager.defaultId
        let selection = knownSelection || _selectionFor(symbol)

        // A request that cannot be made (provider unavailable or disabled, credential missing, symbol or
        // selection not acceptable) is not silently dropped: the reason goes to the symbol's card.
        // A `false` result means this very call is already in flight: nothing to do.
        try {
            let handler = ProvidersManager.requireFromId(providerId)
            let context = contextType.createObject(null, { uid: symbol.uid, ticker: symbol.ticker, providerId: providerId, fetchType: fetchType,
                                                           chartRange: selection.chartRange, chartResolution: selection.chartResolution,
                                                           signature: Helpers.symbolFetchSignature(symbol, ProvidersManager.defaultId) })
            if (fetchType === FetchType.Values.PRICE)
                handler.fetchPrice(symbol.ticker, selection.priceResolution, context, _isLive)
            else if (fetchType === FetchType.Values.CHANGE)
                handler.fetchChange(symbol.ticker, selection.changeResolution, context, _isLive)
            else
                handler.fetchChart(symbol.ticker, selection.chartResolution, selection.chartRange, context, _isLive)
        } catch (caughtError) {
            Logger.debug("fetcher", "cannot fetch " + symbol.ticker + " " + fetchType + ": " + String(caughtError && caughtError.message))
            _reportSymbolError(symbol.uid, fetchType, caughtError)
        }
    }

    // ── The final result of a call ────────────────────────────────────────────
    // Failed responses become the symbol's error; successful ones arrive already parsed by the
    // provider handler (only the candles that were asked for) and are stored. Anything unexpected is
    // reported the same way.
    function _onResponse(context, response, series) {
        if (!_isLive(context)) return
        try {
            if (!response.ok) {
                _reportSymbolError(context.uid, context.fetchType, response.error)
                return
            }
            _store(context.uid, context.providerId, context.fetchType, series)
        } catch (caughtError) {
            _reportSymbolError(context.uid, context.fetchType, caughtError)
        }
    }

    // ── Error reporting ───────────────────────────────────────────────────────
    // Logs (devMode), records and publishes the error for the symbol's card. Only errors
    // the user must act on (credentials) also raise a toast; the rest are shown on the card.
    // A failed change pull is only logged: the price still shows, with the change of its own candle.
    function _reportSymbolError(uid, fetchType, error) {
        let symbol = _findSymbol(uid)
        let wrapped = PluginError.from(error)
        if (fetchType === FetchType.Values.CHANGE) {
            ErrorHandler.handle("fetcher", wrapped, { context: (symbol ? symbol.ticker : uid) + " " + fetchType, notify: false })
            return
        }
        let record = ErrorHandler.handle("fetcher", wrapped, {
            context: symbol ? symbol.ticker + " " + fetchType : fetchType,
            notify: wrapped.code === PluginError.Code.CREDENTIAL
        })
        symbolErrorChanged(uid, fetchType, record)
    }

    // ── Store a successful result ─────────────────────────────────────────────
    // `series` holds the newest validated plain candles the pull asked for, so nothing is trimmed here.
    // Throws PluginError (NO_DATA) for an answer without any candle.
    function _store(symbolId, providerName, fetchType, series) {
        let invert = Helpers.isInverted(symbols, symbolId)
        let name   = ProvidersManager.nameOf(providerName)

        if (fetchType === FetchType.Values.PRICE) {
            if (series.length === 0)
                throw new PluginError.PluginError(PluginError.Code.NO_DATA, name + " has no price for this symbol.", "empty price answer")

            // The newest candle, together with the one before it (see PriceRules), as 1/x when the symbol asks for it,
            // becomes the price shown.
            let latest = series[series.length - 1]
            let previous = series.length > 1 ? series[series.length - 2] : null
            if (invert) {
                latest = SeriesRules.transform(latest, Helpers.inv)
                if (previous) previous = SeriesRules.transform(previous, Helpers.inv)
            }

            priceDataReady(Helpers.withEntry(priceData, symbolId, priceType.createObject(null, PriceRules.priceFrom(latest, previous, _referenceOf(symbolId, invert)))))
            Logger.debug("fetcher", "stored price of " + symbolId + ": " + latest.close + (invert ? " (inverted)" : ""))

        } else if (fetchType === FetchType.Values.CHANGE) {
            // `series` is the reference close (a number). The price shown so far is measured against it.
            _references = Helpers.withEntry(_references, symbolId, series)
            let shown = priceData[symbolId]
            if (shown)
                priceDataReady(Helpers.withEntry(priceData, symbolId, priceType.createObject(null, PriceRules.priceFrom(shown, null, _referenceOf(symbolId, invert)))))
            Logger.debug("fetcher", "stored change reference of " + symbolId + ": " + series)

        } else {
            if (series.length === 0)
                throw new PluginError.PluginError(PluginError.Code.NO_DATA, name + " has no chart data for this symbol.", "empty history answer")

            graphDataReady(Helpers.withEntry(graphData, symbolId, series.map(function(candle) {
                return invert ? SeriesRules.transform(candle, Helpers.inv) : candle
            })))
            Logger.debug("fetcher", "stored " + series.length + " chart candles of " + symbolId + (invert ? " (inverted)" : ""))
        }
        let now = Date.now()
        fetchTimesUpdated(Helpers.withEntry(lastFetchTimes, FetchType.timeKey(symbolId, fetchType), now))   // this pull is now fresh
        refreshedTimesUpdated(Helpers.withEntry(refreshedTimes, FetchType.timeKey(symbolId, fetchType), now))
        symbolStored(symbolId)
        symbolErrorChanged(symbolId, fetchType, null)   // this pull succeeded: clear any earlier error
    }

    // The stored reference close of a symbol, inverted like its prices when the symbol is; null if none yet.
    function _referenceOf(symbolId, invert) {
        let reference = _references[symbolId]
        if (typeof reference !== "number") return null
        return invert ? Helpers.inv(reference) : reference
    }

    // Drops everything held for a symbol (its settings changed: what it shows would be wrong until the next answer).
    function forget(uid) {
        let timeKeys = [FetchType.Values.PRICE, FetchType.Values.CHANGE, FetchType.Values.GRAPH].map(function(fetchType) { return FetchType.timeKey(uid, fetchType) })
        if (priceData[uid] !== undefined) priceDataReady(Helpers.withoutEntry(priceData, uid))
        if (graphData[uid] !== undefined) graphDataReady(Helpers.withoutEntry(graphData, uid))
        _references = Helpers.withoutEntry(_references, uid)
        let started = lastFetchTimes
        timeKeys.forEach(function(key) { if (started[key] !== undefined) started = Helpers.withoutEntry(started, key) })
        if (started !== lastFetchTimes) fetchTimesUpdated(started)
        _initialGraphQueue = _initialGraphQueue.filter(function(symbol) { return symbol.uid !== uid })
        let refreshed = refreshedTimes
        timeKeys.forEach(function(key) { if (refreshed[key] !== undefined) refreshed = Helpers.withoutEntry(refreshed, key) })
        if (refreshed !== refreshedTimes) refreshedTimesUpdated(refreshed)
    }

    // ── Saved market data ─────────────────────────────────────────────────────
    // What of a symbol is worth keeping on disk (plain data, see MarketCache), or null when it has nothing yet.
    readonly property var _priceFields: ["open", "high", "low", "close", "date", "time", "change", "changePercent"]
    readonly property var _candleFields: ["date", "time", "open", "high", "low", "close", "volume"]

    // Copy the requested fields into plain snapshot data.
    function _plain(object, fields) {
        let plain = {}
        fields.forEach(function(field) { plain[field] = object[field] })
        return plain
    }

    // Capture the latest price, reference, chart and successful fetch times.
    function snapshotOf(uid) {
        let price = priceData[uid], graph = graphData[uid]
        if (!price && !graph) return null
        let reference = _references[uid]
        return {
            price: price ? _plain(price, _priceFields) : null,
            reference: typeof reference === "number" ? reference : null,
            graph: graph ? graph.map(function(candle) { return _plain(candle, _candleFields) }) : null,
            refreshedAt: {
                price:  refreshedTimes[FetchType.timeKey(uid, FetchType.Values.PRICE)]  || null,
                change: refreshedTimes[FetchType.timeKey(uid, FetchType.Values.CHANGE)] || null,
                graph:  refreshedTimes[FetchType.timeKey(uid, FetchType.Values.GRAPH)]  || null
            }
        }
    }

    // Accept only finite JavaScript numbers from saved market data.
    function _isNumber(value) { return typeof value === "number" && isFinite(value) }

    // A saved price, or null when it is not a complete, sane one.
    function _restoredPrice(saved) {
        if (!saved || typeof saved !== "object") return null
        let numbers = ["open", "high", "low", "close", "change", "changePercent"]
        for (let i = 0; i < numbers.length; i++) if (!_isNumber(saved[numbers[i]])) return null
        if (typeof saved.date !== "string" || typeof saved.time !== "string" || !(saved.close > 0)) return null
        return priceType.createObject(null, _plain(saved, _priceFields))
    }

    // A saved chart, or null when it is not a non-empty list of valid candles.
    function _restoredChart(saved) {
        if (!Array.isArray(saved) || saved.length === 0) return null
        let points = []
        for (let i = 0; i < saved.length; i++) {
            let candle = saved[i]
            if (!candle || typeof candle !== "object") return null
            for (let j = 2; j < root._candleFields.length; j++) if (!_isNumber(candle[root._candleFields[j]])) return null
            if (typeof candle.date !== "string" || !SeriesRules.DATE_PATTERN.test(candle.date)
                    || typeof candle.time !== "string" || !SeriesRules.TIME_PATTERN.test(candle.time)) return null
            points.push(SeriesRules.candle(_plain(candle, _candleFields)))
        }
        return points
    }

    // Shows a symbol's saved data (see MarketCache) until its first pull from a provider arrives: only what is valid
    // is used, and nothing newer is ever overwritten. `signature` must match what the saved data was fetched for.
    // Returns whether anything was restored. Never throws.
    function restore(uid, record, signature) {
        try {
            if (!record || record.signature !== signature) {
                Logger.debug("fetcher", "saved data of " + uid + " ignored: " + (record ? "the symbol's settings changed" : "none"))
                return false
            }
            let restored = false
            let refreshed = Helpers.copyOf(refreshedTimes)
            let saved = record.refreshedAt || {}
            let price = priceData[uid] ? null : _restoredPrice(record.price)
            if (price) {
                priceDataReady(Helpers.withEntry(priceData, uid, price))
                restored = true
                if (_isNumber(record.reference) && record.reference !== 0 && _references[uid] === undefined)
                    _references = Helpers.withEntry(_references, uid, record.reference)
            }
            let chart = graphData[uid] ? null : _restoredChart(record.graph)
            if (chart) {
                graphDataReady(Helpers.withEntry(graphData, uid, chart))
                restored = true
            }
            let started = Helpers.copyOf(lastFetchTimes)
            let available = { price: !!price, graph: !!chart, change: !!price && typeof _references[uid] === "number" }
            let now = Date.now()
            ;[FetchType.Values.PRICE, FetchType.Values.CHANGE, FetchType.Values.GRAPH].forEach(function(fetchType) {
                let key = FetchType.timeKey(uid, fetchType)
                let timestamp = saved[fetchType]
                if (available[fetchType] && _isNumber(timestamp) && timestamp > 0 && timestamp <= now) {
                    if (!refreshed[key]) refreshed[key] = timestamp
                    if (!started[key]) started[key] = timestamp
                }
            })
            if (restored) {
                refreshedTimesUpdated(refreshed)
                fetchTimesUpdated(started)
            }
            Logger.debug("fetcher", "restored the saved data of " + uid + ": " + (price ? "price " : "") + (chart ? chart.length + " candles" : ""))
            return restored
        } catch (caughtError) {
            ErrorHandler.handle("fetcher", PluginError.from(caughtError), { context: "restoring saved data of " + uid, notify: false })
            return false
        }
    }

    // ── Public: force-refresh a single symbol ─────────────────────────────────
    function forceRefreshSymbol(uid) {
        Logger.debug("fetcher", "refresh " + uid)
        let symbol = _findSymbol(uid)
        if (!symbol) return
        doFetch(symbol, FetchType.Values.PRICE)
        doFetch(symbol, FetchType.Values.CHANGE)
        doFetch(symbol, FetchType.Values.GRAPH)
    }

    // ── Public: force-refresh every symbol ────────────────────────────────────
    function forceRefreshAll() {
        Logger.debug("fetcher", "refresh all " + symbols.length + " symbols")
        for (let i = 0; i < symbols.length; i++) {
            doFetch(symbols[i], FetchType.Values.PRICE)
            doFetch(symbols[i], FetchType.Values.CHANGE)
            doFetch(symbols[i], FetchType.Values.GRAPH)
        }
    }

    // ── Initial stagger queue ─────────────────────────────────────────────────
    property var _initialGraphQueue: []

    Timer {
        id: initialGraphTimer
        interval: JsConstants.INITIAL_GRAPH_STAGGER_MS
        repeat: false
        onTriggered: _processInitialGraphQueue()
    }

    // Start the next staggered initial chart request.
    function _processInitialGraphQueue() {
        if (_initialGraphQueue.length === 0) return
        let remaining = _initialGraphQueue.slice()
        let symbol    = remaining.shift()
        _initialGraphQueue = remaining
        let current = _findSymbol(symbol.uid)
        if (current && Helpers.symbolFetchSignature(current, ProvidersManager.defaultId)
                === Helpers.symbolFetchSignature(symbol, ProvidersManager.defaultId)) doFetch(current, FetchType.Values.GRAPH)
        if (remaining.length > 0) initialGraphTimer.restart()
    }

    // Cached successes keep their normal refresh cadence across reloads; manual refresh bypasses this check.
    function _isDue(symbol, fetchType, now, times) {
        let selection = _selectionFor(symbol)
        let interval = fetchType === FetchType.Values.CHANGE ? SelectionPolicy.changeRefreshMs(selection.changeResolution)
            : Helpers.resolutionToMs(fetchType === FetchType.Values.PRICE ? selection.priceResolution : selection.chartResolution)
        return now - (times[FetchType.timeKey(symbol.uid, fetchType)] || 0) >= interval
    }

    // ── Public: kick off due initial fetches ─────────────────────────────────
    function startInitialFetches(symbolList) {
        Logger.debug("fetcher", "initial fetches for " + symbolList.length + " symbols")
        let now = Date.now()
        let newTimes = Helpers.copyOf(lastFetchTimes)
        let queue = []
        for (let symbol of symbolList) {
            if (!symbol.uid) continue
            for (let fetchType of FetchType.ORDER) {
                if (!_isDue(symbol, fetchType, now, newTimes)) continue
                if (fetchType === FetchType.Values.GRAPH) queue.push(symbol)
                else doFetch(symbol, fetchType)
                newTimes[FetchType.timeKey(symbol.uid, fetchType)] = now
            }
        }
        fetchTimesUpdated(newTimes)
        _initialGraphQueue = queue
        initialGraphTimer.interval = JsConstants.INITIAL_GRAPH_DELAY_MS
        if (queue.length) initialGraphTimer.restart()
        else initialGraphTimer.stop()
    }

    // ── Public: fetch newly-added symbols ─────────────────────────────────────
    function fetchNewSymbols(newSymbolList, knownIds) {
        let now      = Date.now()
        let newTimes = Helpers.copyOf(lastFetchTimes)
        let hasNew   = false

        for (let i = 0; i < newSymbolList.length; i++) {
            let symbol = newSymbolList[i]
            if (knownIds.indexOf(symbol.uid) === -1) {
                for (let fetchType of FetchType.ORDER) {
                    if (!_isDue(symbol, fetchType, now, newTimes)) continue
                    doFetch(symbol, fetchType)
                    newTimes[FetchType.timeKey(symbol.uid, fetchType)] = now
                }
                hasNew = true
            }
        }
        if (hasNew) fetchTimesUpdated(newTimes)
    }
}
