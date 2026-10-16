// PriceChart.qml — Sparkline / area chart (view only)
//
// Draws a compact line+fill chart from an array of OHLC data points.
// All data processing (min/max, coordinate normalisation) is delegated to
// QML/Helpers/ChartDataProcessor.qml; this file contains only rendering code.

import QtQuick
import qs.Common
import qs.Widgets
import "../Helpers"
import "../../JS/Contracts/ChartSpan.js" as ChartSpan
Canvas {
    id: chart

    Constants { id: constants }

    // ── Public API ────────────────────────────────────────────────────────────
    property var    dataPoints:    []
    property string chartRange: ""
    property bool   showRangeLabel: true
    property string providerName:  ""
    property bool   showProviderName: true
    property bool   isLoading:     false

    // Colors — Widget.qml always overrides these; C.* act as safe fallbacks.
    property color positiveColor: constants.defaultUpColor
    property color negativeColor: constants.defaultDownColor

    // ── Data processor ────────────────────────────────────────────────────────
    ChartDataProcessor {
        id: processor
        dataPoints: chart.dataPoints
    }

    // ── Derived colors ────────────────────────────────────────────────────────
    property color lineColor:         processor.isPositive ? positiveColor : negativeColor
    property color fillColor:         processor.isPositive
                                      ? Qt.rgba(positiveColor.r, positiveColor.g, positiveColor.b, constants.chartFillOpacity)
                                      : Qt.rgba(negativeColor.r, negativeColor.g, negativeColor.b, constants.chartFillOpacity)

    // ── Rendering ─────────────────────────────────────────────────────────────
    renderStrategy: Canvas.Threaded

    onDataPointsChanged: requestPaint()
    onWidthChanged:      requestPaint()
    onHeightChanged:     requestPaint()

    onPaint: {
        var canvasContext = getContext("2d")
        canvasContext.reset()

        var points = processor.normalizedPoints(width, height, constants.chartPadding)
        if (points.length < 2) return

        var bottom = height - constants.chartPadding

        // ── Filled area ───────────────────────────────────────────────────
        canvasContext.beginPath()
        canvasContext.moveTo(points[0].x, bottom)
        for (var i = 0; i < points.length; i++) canvasContext.lineTo(points[i].x, points[i].y)
        canvasContext.lineTo(points[points.length - 1].x, bottom)
        canvasContext.closePath()
        canvasContext.fillStyle = fillColor.toString()
        canvasContext.fill()

        // ── Line ──────────────────────────────────────────────────────────
        canvasContext.beginPath()
        for (var j = 0; j < points.length; j++) {
            if (j === 0) canvasContext.moveTo(points[j].x, points[j].y)
            else         canvasContext.lineTo(points[j].x, points[j].y)
        }
        canvasContext.strokeStyle = lineColor.toString()
        canvasContext.lineWidth   = constants.chartLineWidth
        canvasContext.lineJoin    = "round"
        canvasContext.stroke()
    }

    // ── Chart range label (top-left corner) ───────────────────────────────────
    StyledText {
        visible: chart.showRangeLabel && chart.chartRange !== ""
                 && processor.closes.length >= 2
        anchors.left:       parent.left
        anchors.top:        parent.top
        anchors.leftMargin: constants.chartLabelLeftMargin
        anchors.topMargin:  constants.chartLabelTopMargin
        text:           ChartSpan.label(chart.chartRange)
        font.pixelSize: Theme.fontSizeSmall + constants.chartLabelFontSizeDelta
        color:          Theme.surfaceVariantText
        opacity:        constants.chartLabelOpacity
    }

    // ── Provider name label (bottom-left corner) ──────────────────────────────
    StyledText {
        visible: chart.showProviderName && chart.providerName !== ""
                 && processor.closes.length >= 2
        anchors.left:         parent.left
        anchors.bottom:       parent.bottom
        anchors.leftMargin:   constants.chartLabelLeftMargin
        anchors.bottomMargin: constants.chartLabelBottomMargin
        text:           chart.providerName
        font.pixelSize: Theme.fontSizeSmall + constants.chartLabelFontSizeDelta
        color:          Theme.surfaceVariantText
        opacity:        constants.chartLabelOpacity
    }

    // ── Status labels ─────────────────────────────────────────────────────────
    StyledText {
        id: loadingLabel
        visible: processor.closes.length < 2 && chart.isLoading
        anchors.centerIn: parent
        text:           "Loading…"
        font.pixelSize: Theme.fontSizeSmall + constants.chartStatusFontSizeDelta
        color:          Theme.surfaceVariantText

        SequentialAnimation on opacity {
            running: loadingLabel.visible
            loops:   Animation.Infinite
            NumberAnimation { to: 0.3; duration: constants.chartLoadingAnimMs }
            NumberAnimation { to: 1.0; duration: constants.chartLoadingAnimMs }
        }
    }

    StyledText {
        visible: processor.closes.length < 2 && !chart.isLoading
        anchors.centerIn: parent
        text:           "No chart data"
        font.pixelSize: Theme.fontSizeSmall + constants.chartStatusFontSizeDelta
        color:          Theme.surfaceVariantText
    }
}
