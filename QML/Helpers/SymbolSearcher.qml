// SymbolSearcher.qml — Provider-agnostic symbol search logic
//
// Handles the XHR request to search for symbols via the configured provider.
// Exposes results and loading state as output properties.
// Views/SymbolSearch.qml instantiates this item and drives its inputs.

import QtQuick
import qs.Services
import "../../JS/ProviderInterface.js" as Providers

Item {

    // ── QML constants ─────────────────────────────────────────────────────────
    Constants { id: c }

    // ── Inputs ────────────────────────────────────────────────────────────────
    property string providerId: ""

    // ── Outputs ───────────────────────────────────────────────────────────────
    property var  results:     []
    property bool isSearching: false

    // ── Signal (re-emitted by the view) ───────────────────────────────────────
    signal symbolSelected(string symbolId, string symbolName)

    // ── Public API ────────────────────────────────────────────────────────────
    function search(query) {
        if (query.length < 2) return
        if (c.devMode) console.log("[Markets/Searcher] search:", query)
        isSearching = true
        results = []

        var url = Providers.buildSearchUrl(searcher.providerId, query)
        if (!url) { isSearching = false; return }

        var req = new XMLHttpRequest()
        req.onreadystatechange = function() {
            if (req.readyState !== XMLHttpRequest.DONE) return
            isSearching = false
            if (req.status === 200 && req.responseText) {
                if (Providers.isApiKeyError(req.responseText)) {
                    ToastService.showError("Markets", "API key missing or invalid — check plugin settings")
                    return
                }
                var found = Providers.parseSearchResponse(searcher.providerId, req.responseText)
                results = found
                if (c.devMode) console.log("[Markets/Searcher] results:", found.length, "for", query)
                if (found.length === 0)
                    ToastService.showInfo("Markets", "No results for '" + query + "'")
            } else {
                if (c.devMode) console.warn("[Markets/Searcher] search failed — status", req.status)
                ToastService.showError("Markets", "Search failed — check connection")
            }
        }
        req.open("GET", url)
        req.send()
    }

    // ── Internal alias (keeps JS closures from capturing a stale `this`) ──────
    readonly property var searcher: this
}
