// PriceChart.qml - Sparkline / area chart (view only)
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
    property string providerAlias: ""     // the provider's three-letter alias (e.g. YHF)
    property bool   showProviderName: true
    property bool   isLoading:     false
    property real   cornerRadius:  0      // the chart is clipped to a rounded rectangle of this radius (SymbolRow passes the theme's)

    // Colors - Widget.qml always overrides these; C.* act as safe fallbacks.
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
    onCornerRadiusChanged: requestPaint()

    // Rounded corners: Canvas clip paths and effect masks are not reliable (a threaded canvas ignores a clip), so the drawing
    // itself stays inside the rounded rectangle: the fill is drawn as one-pixel columns between the line and the bottom, each
    // limited by the corner arcs, and the line's points are kept inside the arcs.
    function _cornerInset(x) {
        var radius = Math.min(cornerRadius, width / 2, height / 2)
        if (!(radius > 0)) return 0
        var beyond = x < radius ? radius - x : (x > width - radius ? x - (width - radius) : 0)
        return radius - Math.sqrt(Math.max(0, radius * radius - beyond * beyond))
    }

    // The line's height at x (the points are ordered by x).
    function _lineY(points, x) {
        if (x <= points[0].x) return points[0].y
        for (var i = 1; i < points.length; i++) {
            if (x <= points[i].x) {
                var span = points[i].x - points[i - 1].x
                return span > 0 ? points[i - 1].y + (points[i].y - points[i - 1].y) * (x - points[i - 1].x) / span : points[i].y
            }
        }
        return points[points.length - 1].y
    }

    onPaint: {
        var canvasContext = getContext("2d")
        canvasContext.reset()

        var points = processor.normalizedPoints(width, height, constants.chartPadding)
        if (points.length < 2) return

        var bottom = height - constants.chartPadding

        // ── Filled area ───────────────────────────────────────────────────
        canvasContext.fillStyle = fillColor.toString()
        if (cornerRadius > 0) {
            for (var column = Math.floor(points[0].x); column < Math.ceil(points[points.length - 1].x); column++) {
                var centre = column + 0.5
                var top = Math.max(_lineY(points, centre), _cornerInset(centre))
                var floor = Math.min(bottom, height - _cornerInset(centre))
                if (floor > top) canvasContext.fillRect(column, top, 1, floor - top)
            }
        } else {
            canvasContext.beginPath()
            canvasContext.moveTo(points[0].x, bottom)
            for (var i = 0; i < points.length; i++) canvasContext.lineTo(points[i].x, points[i].y)
            canvasContext.lineTo(points[points.length - 1].x, bottom)
            canvasContext.closePath()
            canvasContext.fill()
        }

        // ── Line ──────────────────────────────────────────────────────────
        canvasContext.beginPath()
        for (var j = 0; j < points.length; j++) {
            var lineTop = _cornerInset(points[j].x)
            var lineY = Math.min(Math.max(points[j].y, lineTop), height - lineTop)     // inside the rounded corners
            if (j === 0) canvasContext.moveTo(points[j].x, lineY)
            else         canvasContext.lineTo(points[j].x, lineY)
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
        text:           ChartSpan.shortLabel(chart.chartRange)
        font.pixelSize: Theme.fontSizeSmall + constants.chartLabelFontSizeDelta
        color:          Theme.surfaceVariantText
        opacity:        constants.chartLabelOpacity
    }

    // ── Provider alias label (bottom-left corner) ──────────────────────────────
    StyledText {
        visible: chart.showProviderName && chart.providerAlias !== ""
                 && processor.closes.length >= 2
        anchors.left:         parent.left
        anchors.bottom:       parent.bottom
        anchors.leftMargin:   constants.chartLabelLeftMargin
        anchors.bottomMargin: constants.chartLabelBottomMargin
        text:           chart.providerAlias
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
