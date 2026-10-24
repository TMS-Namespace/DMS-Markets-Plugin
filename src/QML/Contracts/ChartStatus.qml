// ChartStatus.qml - contract: how well a chart resolution fits a chart range (ChartRules.evaluate).
//
//   level     "ok" | "warn" | "block"        reason   "" | "tooBig" | "tooSmall"
//   candles   how many candles fit           message  short user-facing text, "" when level is ok
import QtQml

QtObject {
    readonly property bool blocked: level === "block"
    property real candles: 0
    property string level: "ok"
    property string message: ""
    property string reason: ""
    readonly property bool warned: level === "warn"
}
