// PriceChart.qml — Sparkline / area chart (view only)
//
// Draws a compact line+fill chart from an array of OHLC data points.
// All data processing (min/max, coordinate normalisation) is delegated to
// QML/Helpers/ChartDataProcessor.qml; this file contains only rendering code.

import QtQuick
import "../Helpers"

Canvas {
    id: chart

    Constants { id: c }

    // ── Public API ────────────────────────────────────────────────────────────
    property var    dataPoints:    []
    property string graphInterval: ""
    property bool   showRangeLabel: true
    property bool   isLoading:     false

    // Colors — Widget.qml always overrides these; C.* act as safe fallbacks.
    property color positiveColor: c.defaultUpColor
    property color negativeColor: c.defaultDownColor

    // ── Data processor ────────────────────────────────────────────────────────
    ChartDataProcessor {
        id: processor
        dataPoints: chart.dataPoints
    }

    // ── Derived colors ────────────────────────────────────────────────────────
    property color lineColor:         processor.isPositive ? positiveColor : negativeColor
    property color fillColor:         processor.isPositive
                                      ? Qt.rgba(positiveColor.r, positiveColor.g, positiveColor.b, c.chartFillOpacity)
                                      : Qt.rgba(negativeColor.r, negativeColor.g, negativeColor.b, c.chartFillOpacity)

    // ── Rendering ─────────────────────────────────────────────────────────────
    renderStrategy: Canvas.Threaded

    onDataPointsChanged: requestPaint()
    onWidthChanged:      requestPaint()
    onHeightChanged:     requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()

        var pts = processor.normalizedPoints(width, height, c.chartPadding)
        if (pts.length < 2) return

        var bottom = height - c.chartPadding

        // ── Filled area ───────────────────────────────────────────────────
        ctx.beginPath()
        ctx.moveTo(pts[0].x, bottom)
        for (var i = 0; i < pts.length; i++) ctx.lineTo(pts[i].x, pts[i].y)
        ctx.lineTo(pts[pts.length - 1].x, bottom)
        ctx.closePath()
        ctx.fillStyle = fillColor.toString()
        ctx.fill()

        // ── Line ──────────────────────────────────────────────────────────
        ctx.beginPath()
        for (var j = 0; j < pts.length; j++) {
            if (j === 0) ctx.moveTo(pts[j].x, pts[j].y)
            else         ctx.lineTo(pts[j].x, pts[j].y)
        }
        ctx.strokeStyle = lineColor.toString()
        ctx.lineWidth   = c.chartLineWidth
        ctx.lineJoin    = "round"
        ctx.stroke()
    }

    // ── Chart range label (top-left corner) ───────────────────────────────────
    Text {
        visible: chart.showRangeLabel && chart.graphInterval !== ""
                 && processor.closes.length >= 2
        anchors.left:       parent.left
        anchors.top:        parent.top
        anchors.leftMargin: c.chartLabelLeftMargin
        anchors.topMargin:  c.chartLabelTopMargin
        text:           chart.graphInterval
        font.pixelSize: c.chartLabelFontSize
        color:          c.chartLabelColor
        opacity:        c.chartLabelOpacity
    }

    // ── Status labels ─────────────────────────────────────────────────────────
    Text {
        visible: processor.closes.length < 2 && chart.isLoading
        anchors.centerIn: parent
        text:           "Loading…"
        font.pixelSize: c.chartStatusFontSize
        color:          c.chartLabelColor

        SequentialAnimation on opacity {
            running: true
            loops:   Animation.Infinite
            NumberAnimation { to: 0.3; duration: c.chartLoadingAnimMs }
            NumberAnimation { to: 1.0; duration: c.chartLoadingAnimMs }
        }
    }

    Text {
        visible: processor.closes.length < 2 && !chart.isLoading
        anchors.centerIn: parent
        text:           "No chart data"
        font.pixelSize: c.chartStatusFontSize
        color:          c.chartLabelColor
    }
}
