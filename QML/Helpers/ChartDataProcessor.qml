// ChartDataProcessor.qml — Pure data processing for sparkline charts
//
// Consumes a raw dataPoints array (from the Stooq provider) and exposes
// all derived values needed to paint the chart: cleaned close prices,
// direction, value range, and a coordinate-mapping function.
// Views/PriceChart.qml instantiates this item and uses its outputs.

import QtQuick

Item {

    // ── Input ─────────────────────────────────────────────────────────────────
    property var dataPoints: []

    // ── Derived close-prices (invalid entries dropped) ────────────────────────
    readonly property var closes: {
        var arr = []
        for (var i = 0; i < dataPoints.length; i++) {
            var v = dataPoints[i].close
            if (v !== undefined && !isNaN(v)) arr.push(v)
        }
        return arr
    }

    // ── Direction (last vs first close) ───────────────────────────────────────
    readonly property bool isPositive: {
        if (closes.length < 2) return true
        return closes[closes.length - 1] >= closes[0]
    }

    // ── Range ─────────────────────────────────────────────────────────────────
    readonly property real minValue: {
        if (closes.length === 0) return 0
        var m = closes[0]
        for (var i = 1; i < closes.length; i++) if (closes[i] < m) m = closes[i]
        return m
    }

    readonly property real maxValue: {
        if (closes.length === 0) return 1
        var m = closes[0]
        for (var i = 1; i < closes.length; i++) if (closes[i] > m) m = closes[i]
        return m
    }

    readonly property real valueRange: maxValue - minValue > 0 ? maxValue - minValue : 1

    // ── Coordinate mapping ────────────────────────────────────────────────────
    // Returns an array of { x, y } canvas pixel coordinates for the given
    // canvas dimensions and padding. Returns [] when fewer than 2 closes.
    function normalizedPoints(canvasWidth, canvasHeight, padding) {
        if (closes.length < 2) return []
        var pts = []
        var cw  = canvasWidth  - padding * 2
        var ch  = canvasHeight - padding * 2
        for (var i = 0; i < closes.length; i++) {
            pts.push({
                x: padding + (i / (closes.length - 1)) * cw,
                y: padding + (1 - (closes[i] - minValue) / valueRange) * ch
            })
        }
        return pts
    }
}
