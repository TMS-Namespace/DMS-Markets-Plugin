// Selection.qml — contract: the three range choices of a symbol.
//
//   priceResolution   how often, and in what candle size, the live price is pulled
//   changeResolution  the change is measured against the close of the previous period of this size
//   chartResolution   candle size of the chart
//   chartRange        how much history the chart shows
// What a provider can serve, and the closest choice to a wish, is SelectionPolicy.clamp.
import QtQml
import "../../JS/Contracts/Resolution.js" as Resolution
import "../../JS/Contracts/ChartSpan.js" as ChartSpan

QtObject {
    property string priceResolution: ""
    property string changeResolution: ""
    property string chartResolution: ""
    property string chartRange: ""

    readonly property bool priceResolutionValid: Resolution.isValid(priceResolution)
    readonly property bool changeResolutionValid: Resolution.isValid(changeResolution)
    readonly property bool chartResolutionValid: Resolution.isValid(chartResolution)
    readonly property bool chartRangeValid: ChartSpan.isValid(chartRange)
}
