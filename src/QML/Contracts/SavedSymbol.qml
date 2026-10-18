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
import "../../JS/Contracts/ChartSpan.js" as ChartSpan
import "../../JS/Contracts/Resolution.js" as Resolution
import "../../JS/Helpers/Helpers.js" as Helpers

QtObject {
    property string changeResolution: ""
    readonly property bool changeResolutionValid: Resolution.isValid(changeResolution)
    property string chartRange: ""
    readonly property bool chartRangeValid: ChartSpan.isValid(chartRange)
    property string chartResolution: ""
    readonly property bool chartResolutionValid: Resolution.isValid(chartResolution)
    property bool invert: false
    property string name: ""
    property bool pinned: false
    property string priceResolution: ""
    readonly property bool priceResolutionValid: Resolution.isValid(priceResolution)
    property string provider: ""
    readonly property bool providerValid: provider !== ""
    property bool showChangeWhenPinned: false
    property string ticker: ""
    readonly property bool tickerValid: ticker !== ""
    property string uid: ""
    readonly property bool uidValid: Helpers.isUuid(uid)
}
