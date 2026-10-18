// DataPoint.qml - contract: one candle, as stored for the chart. A data holder: building a consistent
// candle from raw numbers is SeriesRules.candle; this type carries the result and answers whether each
// field is individually well-formed. A chart holds only as many as its range has at its resolution.
//
//   date    "YYYY-MM-DD" UTC calendar date          time  "HH:MM:SS" UTC, "" for date-only data
//   open, high, low, close   numbers                volume  non-negative integer, 0 when unknown
import QtQml

QtObject {
    property real close: 0
    property string date: ""
    readonly property bool dateValid: /^\d{4}-\d{2}-\d{2}$/.test(date)
    property real high: 0
    property real low: 0
    property real open: 0
    property string time: ""
    readonly property bool timeValid: /^(\d{2}:\d{2}:\d{2})?$/.test(time)
    property real volume: 0
}
