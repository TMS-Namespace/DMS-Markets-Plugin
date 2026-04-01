// SymbolManager.qml — Symbol list management and bar-text logic
//
// Handles all mutations to the persisted symbol list (pin, remove, reorder)
// and computes the bar display text from pinned symbols + live price data.
// Widget.qml instantiates this item and binds its inputs; results are read
// back through the item's output properties and signals.

import QtQuick
import qs.Services
import "../../JS/Helpers.js" as Helpers

Item {

    // ── Inputs (bound from Widget.qml) ────────────────────────────────────────
    property string pluginId:   ""
    property var    pluginService: null
    property var    symbols:       []
    property var    priceData:     ({})

    // ── Computed outputs ─────────────────────────────────────────────────────
    readonly property var pinnedSymbols: {
        var result = []
        for (var i = 0; i < symbols.length; i++)
            if (symbols[i].pinned) result.push(symbols[i])
        return result
    }

    readonly property string barDisplayText: {
        if (pinnedSymbols.length === 0)
            return c.barDefaultLabel

        var parts = []
        for (var i = 0; i < pinnedSymbols.length; i++) {
            var sym = pinnedSymbols[i]
            var pd  = priceData[sym.id]
            if (pd && pd.close !== undefined && !isNaN(pd.close)) {
                var label = sym.name + " " + Helpers.formatNumber(pd.close)
                if (sym.showChangeWhenPinned) {
                    var chg  = pd.change || 0
                    label += " " + (chg >= 0 ? "+" : "") + Helpers.formatNumber(chg)
                }
                parts.push(label)
            } else {
                parts.push(sym.name + " …")
            }
        }
        return parts.join(c.barSeparator)
    }

    // ── QML constants (used for bar strings) ─────────────────────────────────
    Constants { id: c }

    // ── Symbol mutation ───────────────────────────────────────────────────────
    function togglePin(symbolId) {
        if (c.devMode) console.log("[Markets/SymbolManager] togglePin", symbolId)
        var list = JSON.parse(JSON.stringify(symbols))
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === symbolId) {
                list[i].pinned = !list[i].pinned
                break
            }
        }
        _save(list)
    }

    function removeSymbol(symbolId) {
        if (c.devMode) console.log("[Markets/SymbolManager] removeSymbol", symbolId)
        var list = []
        for (var i = 0; i < symbols.length; i++)
            if (symbols[i].id !== symbolId) list.push(symbols[i])
        _save(list)
    }

    function _save(list) {
        if (c.devMode) console.log("[Markets/SymbolManager] saving", list.length, "symbols")
        if (pluginService)
            pluginService.savePluginData(pluginId, "symbols", JSON.stringify(list))
    }
}
