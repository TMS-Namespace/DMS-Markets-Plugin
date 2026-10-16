// PriceInfo.qml — contract: what the widget shows for a symbol's live price (PriceRules.priceFrom).
//
//   open, high, low, close   numbers          date, time   UTC, as in DataPoint
//   change                   close - open     changePercent   change / open * 100, 0 when open is 0
import QtQml

QtObject {
    property real open: 0
    property real high: 0
    property real low: 0
    property real close: 0
    property string date: ""
    property string time: ""
    property real change: 0
    property real changePercent: 0
}
