// ChartStatus.qml — contract: how well a chart resolution fits a chart range (ChartRules.evaluate).
//
//   level     "ok" | "warn" | "block"        reason   "" | "tooBig" | "tooSmall"
//   candles   how many candles fit           message  short user-facing text, "" when level is ok
import QtQml

QtObject {
    property string level: "ok"
    property string reason: ""
    property real candles: 0
    property string message: ""

    readonly property bool blocked: level === "block"
    readonly property bool warned: level === "warn"
}
