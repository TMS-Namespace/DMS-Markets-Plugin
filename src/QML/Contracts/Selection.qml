// Selection.qml - contract: the three range choices of a symbol.
//
//   priceResolution   how often, and in what candle size, the live price is pulled
//   changeResolution  the change is measured against the close of the previous period of this size
//   chartResolution   candle size of the chart
//   chartRange        how much history the chart shows
// What a provider can serve, and the closest choice to a wish, is SelectionPolicy.clamp.
import QtQml
import "../../JS/Contracts/ChartSpan.js" as ChartSpan
import "../../JS/Contracts/Resolution.js" as Resolution

QtObject {
    property string changeResolution: ""
    readonly property bool changeResolutionValid: Resolution.isValid(changeResolution)
    property string chartRange: ""
    readonly property bool chartRangeValid: ChartSpan.isValid(chartRange)
    property string chartResolution: ""
    readonly property bool chartResolutionValid: Resolution.isValid(chartResolution)
    property string priceResolution: ""
    readonly property bool priceResolutionValid: Resolution.isValid(priceResolution)
}
