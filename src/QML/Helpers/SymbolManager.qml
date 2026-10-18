// SymbolManager.qml - Symbol list management and bar-text logic
//
// Names the symbol actions (pin, remove) for the widget and computes the bar display
// text from pinned symbols + live price data. Saving is DataStorage's job.
// Widget.qml instantiates this item and binds its inputs; results are read
// back through the item's output properties and signals.

import QtQuick
import "../Services"
import "../../JS/Helpers/Helpers.js" as Helpers

Item {

    // ── Inputs (bound from Widget.qml) ────────────────────────────────────────
    property var    storage:       null   // the widget's DataStorage
    property var    symbols:       []
    property var    priceData:     ({})

    // ── Computed outputs ─────────────────────────────────────────────────────
    readonly property var pinnedSymbols: {
        let result = []
        for (let i = 0; i < symbols.length; i++)
            if (symbols[i].pinned) result.push(symbols[i])
        return result
    }

    readonly property string barDisplayText: {
        if (pinnedSymbols.length === 0)
            return constants.barDefaultLabel

        let parts = []
        for (let i = 0; i < pinnedSymbols.length; i++) {
            let symbol = pinnedSymbols[i]
            let priceInfo  = priceData[symbol.uid]
            if (priceInfo && priceInfo.close !== undefined && !isNaN(priceInfo.close)) {
                let label = symbol.name + " " + Helpers.formatNumber(priceInfo.close)
                if (Helpers.boolValue(symbol.showChangeWhenPinned, false)) {
                    let change  = priceInfo.change || 0
                    label += " " + (change >= 0 ? "+" : "") + Helpers.formatNumber(change)
                }
                parts.push(label)
            } else {
                parts.push(symbol.name + " …")
            }
        }
        return parts.join(constants.barSeparator)
    }

    // ── QML constants (used for bar strings) ─────────────────────────────────
    Constants { id: constants }

    // ── Symbol mutation ───────────────────────────────────────────────────────
    // Persistence belongs to DataStorage (checked, reported saves); these only name the action.
    function togglePin(uid) {
        Logger.debug("symbols", "toggle pin " + uid)
        return storage.togglePin(symbols, uid)
    }

    // Remove the symbol through the checked storage boundary.
    function removeSymbol(uid) {
        Logger.debug("symbols", "remove " + uid)
        return storage.removeSymbol(symbols, uid)
    }
}
