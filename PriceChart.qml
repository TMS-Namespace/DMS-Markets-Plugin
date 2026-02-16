// PriceChart.qml — Sparkline / area chart for market data
//
// Draws a compact line+fill chart from an array of OHLC data points.
// Automatically adapts colors based on whether the overall move is positive or
// negative (first close vs last close).

import QtQuick

Canvas {
    id: chart

    // ── Public API ───────────────────────────────────────────────────────────
    // Array of objects with at least a `close` numeric field.
    property var  dataPoints: []

    // Override automatic direction detection
    property bool isPositive: {
        if (!dataPoints || dataPoints.length < 2) return true
        var first = dataPoints[0].close
        var last  = dataPoints[dataPoints.length - 1].close
        return last >= first
    }

    // Colors
    property color positiveColor:     "#4CAF50"
    property color negativeColor:     "#F44336"
    property color lineColor:         isPositive ? positiveColor : negativeColor
    property color fillColorPositive: Qt.rgba(0.298, 0.686, 0.314, 0.25)
    property color fillColorNegative: Qt.rgba(0.957, 0.263, 0.212, 0.25)
    property color fillColor:         isPositive ? fillColorPositive : fillColorNegative

    // ── Rendering ────────────────────────────────────────────────────────────
    renderStrategy: Canvas.Threaded

    onDataPointsChanged: requestPaint()
    onWidthChanged:      requestPaint()
    onHeightChanged:     requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()

        if (!dataPoints || dataPoints.length < 2) return

        // Extract valid close prices
        var closes = []
        for (var i = 0; i < dataPoints.length; i++) {
            var c = dataPoints[i].close
            if (c !== undefined && !isNaN(c))
                closes.push(c)
        }
        if (closes.length < 2) return

        var min   = closes[0]
        var max   = closes[0]
        for (var m = 1; m < closes.length; m++) {
            if (closes[m] < min) min = closes[m]
            if (closes[m] > max) max = closes[m]
        }
        var range = max - min
        if (range === 0) range = 1          // flat line guard

        var pad = 2
        var w   = width  - pad * 2
        var h   = height - pad * 2

        // ── Filled area ──────────────────────────────────────────────────
        ctx.beginPath()
        ctx.moveTo(pad, height - pad)       // bottom-left anchor
        for (var j = 0; j < closes.length; j++) {
            var x = pad + (j / (closes.length - 1)) * w
            var y = pad + (1 - (closes[j] - min) / range) * h
            ctx.lineTo(x, y)
        }
        ctx.lineTo(pad + w, height - pad)   // bottom-right anchor
        ctx.closePath()
        ctx.fillStyle = fillColor.toString()
        ctx.fill()

        // ── Line ─────────────────────────────────────────────────────────
        ctx.beginPath()
        for (var k = 0; k < closes.length; k++) {
            var lx = pad + (k / (closes.length - 1)) * w
            var ly = pad + (1 - (closes[k] - min) / range) * h
            if (k === 0) ctx.moveTo(lx, ly)
            else         ctx.lineTo(lx, ly)
        }
        ctx.strokeStyle = lineColor.toString()
        ctx.lineWidth   = 1.5
        ctx.lineJoin    = "round"
        ctx.stroke()
    }

    // ── Status text when chart cannot draw ─────────────────────────────
    property bool isLoading: false

    Text {
        visible: (!chart.dataPoints || chart.dataPoints.length < 2) && chart.isLoading
        anchors.centerIn: parent
        text: "Loading…"
        font.pixelSize: 10
        color: "#888888"

        SequentialAnimation on opacity {
            running: true
            loops: Animation.Infinite
            NumberAnimation { to: 0.3; duration: 600 }
            NumberAnimation { to: 1.0; duration: 600 }
        }
    }

    Text {
        visible: (!chart.dataPoints || chart.dataPoints.length < 2) && !chart.isLoading
        anchors.centerIn: parent
        text: "No chart data"
        font.pixelSize: 10
        color: "#888888"
    }
}
