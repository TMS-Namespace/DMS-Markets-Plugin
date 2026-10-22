// PriceChart.qml - Sparkline / area chart (view only)
//
// Draws a compact line+fill chart from an array of OHLC data points.
// All data processing (min/max, coordinate normalisation) is delegated to
// QML/Helpers/ChartDataProcessor.qml; this file contains only rendering code.
//
// ROUNDED CORNERS - how they work, and what did not (read before changing the drawing or the clipping)
//
// The chart is a plain rectangle; the card that holds it (SymbolRow) rounds it by putting it inside Quickshell's
// ClippingRectangle with the theme's corner radius, the item DMS itself uses for its rounded wallpaper, artwork and avatar
// images. That works with a Canvas child, also a threaded one (checked in a real window on the GPU). Two things are
// needed for the corners to actually show:
//   1. The FILL must run out to the canvas edges (left, right, bottom). It used to stop at the padding (3px inside), which
//      put its corners just inside a radius-10 curve, so the clip had nothing to cut and the corners looked square for
//      many attempts. Only the LINE is inset by the padding.
//   2. The radius is concentric with the card: the theme's corner radius less the gap between card and chart, so the two curves
//      run parallel. (The same radius on a rectangle inset by the gap looks different from the card's curve.)
// Earlier attempts (a clip path in the canvas, erasing the corners with the "destination-out" composite mode, drawing the
// fill in columns limited by the corner arcs, a MultiEffect mask) all looked like failures, but the real cause was the
// inset fill in point 1, which every one of them shared. They were removed as unnecessary: do not bring them back. The
// offscreen test harness cannot render ClippingRectangle, so only a real DMS shows the result.

import QtQuick
import "../../JS/Contracts/ChartSpan.js" as ChartSpan
import "../Helpers"
import qs.Common
import qs.DCommon.Widgets

Canvas {
    id: chart

    property string chartRange: ""

    // ── Public API ────────────────────────────────────────────────────────────
    property var dataPoints: []
    property color fillColor: processor.isPositive ? Qt.rgba(positiveColor.r, positiveColor.g, positiveColor.b, constants.chartFillOpacity) : Qt.rgba(negativeColor.r, negativeColor.g, negativeColor.b, constants.chartFillOpacity)
    property bool isLoading: false

    // ── Derived colors ────────────────────────────────────────────────────────
    property color lineColor: processor.isPositive ? positiveColor : negativeColor
    property color negativeColor: constants.defaultDownColor

    // Colors - Widget.qml always overrides these; C.* act as safe fallbacks.
    property color positiveColor: constants.defaultUpColor
    property string providerAlias: ""     // the provider's three-letter alias (e.g. YHF)
    property bool showProviderName: true
    property bool showRangeLabel: true

    // ── Rendering ─────────────────────────────────────────────────────────────
    renderStrategy: Canvas.Threaded

    onDataPointsChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        let canvasContext = getContext("2d");
        canvasContext.reset();

        let points = processor.normalizedPoints(width, height, constants.chartPadding);
        if (points.length < 2)
            return;

        // ── Filled area ───────────────────────────────────────────────────
        // The fill runs out to the chart's own edges (the line stays inset by the padding), so the card's rounded clip
        // (SymbolRow) cuts its corners; a fill inset by the padding would sit just inside the curve and look square.
        canvasContext.beginPath();
        canvasContext.moveTo(0, height);
        canvasContext.lineTo(0, points[0].y);
        for (let i = 0; i < points.length; i++)
            canvasContext.lineTo(points[i].x, points[i].y);
        canvasContext.lineTo(width, points[points.length - 1].y);
        canvasContext.lineTo(width, height);
        canvasContext.closePath();
        canvasContext.fillStyle = fillColor.toString();
        canvasContext.fill();

        // ── Line ──────────────────────────────────────────────────────────
        canvasContext.beginPath();
        for (let j = 0; j < points.length; j++) {
            if (j === 0)
                canvasContext.moveTo(points[j].x, points[j].y);
            else
                canvasContext.lineTo(points[j].x, points[j].y);
        }
        canvasContext.strokeStyle = lineColor.toString();
        canvasContext.lineWidth = constants.chartLineWidth;
        canvasContext.lineJoin = "round";
        canvasContext.stroke();
    }
    onWidthChanged: requestPaint()

    Constants {
        id: constants
    }

    // ── Data processor ────────────────────────────────────────────────────────
    ChartDataProcessor {
        id: processor

        dataPoints: chart.dataPoints
    }

    // ── Chart range label (top-left corner) ───────────────────────────────────
    StyledText {
        anchors.left: parent.left
        anchors.leftMargin: constants.chartLabelLeftMargin
        anchors.top: parent.top
        anchors.topMargin: constants.chartLabelTopMargin
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall + constants.chartLabelFontSizeDelta
        opacity: constants.chartLabelOpacity
        text: ChartSpan.shortLabel(chart.chartRange)
        visible: chart.showRangeLabel && chart.chartRange !== "" && processor.closes.length >= 2
    }

    // ── Provider alias label (bottom-left corner) ──────────────────────────────
    StyledText {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: constants.chartLabelBottomMargin
        anchors.left: parent.left
        anchors.leftMargin: constants.chartLabelLeftMargin
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall + constants.chartLabelFontSizeDelta
        opacity: constants.chartLabelOpacity
        text: chart.providerAlias
        visible: chart.showProviderName && chart.providerAlias !== "" && processor.closes.length >= 2
    }

    // ── Status labels ─────────────────────────────────────────────────────────
    StyledText {
        id: loadingLabel

        anchors.centerIn: parent
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall + constants.chartStatusFontSizeDelta
        text: "Loading…"
        visible: processor.closes.length < 2 && chart.isLoading

        SequentialAnimation on opacity {
            loops: Animation.Infinite
            running: loadingLabel.visible

            NumberAnimation {
                duration: constants.chartLoadingAnimMs
                to: 0.3
            }
            NumberAnimation {
                duration: constants.chartLoadingAnimMs
                to: 1.0
            }
        }
    }
    StyledText {
        anchors.centerIn: parent
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall + constants.chartStatusFontSizeDelta
        text: "No chart data"
        visible: processor.closes.length < 2 && !chart.isLoading
    }
}
