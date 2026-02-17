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

    // Chart range label displayed in the top-left corner
    property string graphInterval: ""
    property bool showRangeLabel: true

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
    property color fillColorPositive: Qt.rgba(positiveColor.r, positiveColor.g, positiveColor.b, 0.25)
    property color fillColorNegative: Qt.rgba(negativeColor.r, negativeColor.g, negativeColor.b, 0.25)
    property color fillColor:         isPositive ? fillColorPositive : fillColorNegative

    // ── Rendering ────────────────────────────────────────────────────────────
    renderStrategy: Canvas.Threaded

    onDataPointsChanged: requestPaint()
    onWidthChanged:      requestPaint()
    onHeightChanged:     requestPaint()

    onPaint: {
        var context = getContext("2d")
        context.reset()

        if (!dataPoints || dataPoints.length < 2) return

        // Extract valid close prices
        var closes = []
        for (var dataIndex = 0; dataIndex < dataPoints.length; dataIndex++) {
            var closeValue = dataPoints[dataIndex].close
            if (closeValue !== undefined && !isNaN(closeValue))
                closes.push(closeValue)
        }
        if (closes.length < 2) return

        var min   = closes[0]
        var max   = closes[0]
        for (var scanIndex = 1; scanIndex < closes.length; scanIndex++) {
            if (closes[scanIndex] < min) min = closes[scanIndex]
            if (closes[scanIndex] > max) max = closes[scanIndex]
        }
        var range = max - min
        if (range === 0) range = 1          // flat line guard

        var padding     = 2
        var chartWidth  = width  - padding * 2
        var chartHeight = height - padding * 2

        // ── Filled area ──────────────────────────────────────────────────
        context.beginPath()
        context.moveTo(padding, height - padding)       // bottom-left anchor
        for (var fillIndex = 0; fillIndex < closes.length; fillIndex++) {
            var pointX = padding + (fillIndex / (closes.length - 1)) * chartWidth
            var pointY = padding + (1 - (closes[fillIndex] - min) / range) * chartHeight
            context.lineTo(pointX, pointY)
        }
        context.lineTo(padding + chartWidth, height - padding)   // bottom-right anchor
        context.closePath()
        context.fillStyle = fillColor.toString()
        context.fill()

        // ── Line ─────────────────────────────────────────────────────────
        context.beginPath()
        for (var lineIndex = 0; lineIndex < closes.length; lineIndex++) {
            var lineX = padding + (lineIndex / (closes.length - 1)) * chartWidth
            var lineY = padding + (1 - (closes[lineIndex] - min) / range) * chartHeight
            if (lineIndex === 0) context.moveTo(lineX, lineY)
            else                 context.lineTo(lineX, lineY)
        }
        context.strokeStyle = lineColor.toString()
        context.lineWidth   = 1.5
        context.lineJoin    = "round"
        context.stroke()
    }

    // ── Chart range label (top-left corner) ──────────────────────────────
    Text {
        visible: chart.showRangeLabel && chart.graphInterval !== "" && chart.dataPoints && chart.dataPoints.length >= 2
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: 4
        anchors.topMargin: 2
        text: chart.graphInterval
        font.pixelSize: 9
        color: "#888888"
        opacity: 0.8
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
