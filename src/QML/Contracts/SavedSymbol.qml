// SavedSymbol.qml - contract: one symbol as saved in the plugin's data (always the current format;
// older formats are SymbolMigration's business, and are gone before anything creates one of these).
//
//   uid                    unique internal handle (UUID), never shown, the key of all runtime state
//   ticker                 the provider's symbol text        name   display name
//   provider               provider id
//   priceResolution, changeResolution, chartResolution, chartRange   see Selection
//   showChangeWhenPinned, invert (show 1/x), pinned          flags
//
// Each `…Valid` flag checks its own field only; whether a field suits the provider is SymbolRules
// and SelectionPolicy; storage owns serialization.
import QtQml
import "../../JS/Helpers/Helpers.js" as Helpers
import "../../JS/Contracts/Resolution.js" as Resolution
import "../../JS/Contracts/ChartSpan.js" as ChartSpan

QtObject {
    property string uid: ""
    property string ticker: ""
    property string name: ""
    property string provider: ""
    property string priceResolution: ""
    property string changeResolution: ""
    property string chartResolution: ""
    property string chartRange: ""
    property bool showChangeWhenPinned: false
    property bool invert: false
    property bool pinned: false

    readonly property bool uidValid: Helpers.isUuid(uid)
    readonly property bool tickerValid: ticker !== ""
    readonly property bool providerValid: provider !== ""
    readonly property bool priceResolutionValid: Resolution.isValid(priceResolution)
    readonly property bool changeResolutionValid: Resolution.isValid(changeResolution)
    readonly property bool chartResolutionValid: Resolution.isValid(chartResolution)
    readonly property bool chartRangeValid: ChartSpan.isValid(chartRange)
}
