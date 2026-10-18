// ChartDataProcessor.qml - Pure data processing for sparkline charts
//
// Consumes a raw dataPoints array from a market data provider and exposes
// all derived values needed to paint the chart: cleaned close prices,
// direction, value range, and a coordinate-mapping function.
// Views/PriceChart.qml instantiates this item and uses its outputs.

import QtQuick

Item {

    // ── Derived close-prices (invalid entries dropped) ────────────────────────
    readonly property var closes: {
        let validCloses = [];
        for (let i = 0; i < dataPoints.length; i++) {
            let point = dataPoints[i];
            let closeValue = point ? point.close : undefined;
            if (typeof closeValue === "number" && isFinite(closeValue))
                validCloses.push(closeValue);
        }
        return validCloses;
    }

    // ── Input ─────────────────────────────────────────────────────────────────
    property var dataPoints: []

    // ── Direction (last vs first close) ───────────────────────────────────────
    readonly property bool isPositive: {
        if (closes.length < 2)
            return true;
        return closes[closes.length - 1] >= closes[0];
    }
    readonly property real maxValue: {
        if (closes.length === 0)
            return 1;
        let highest = closes[0];
        for (let i = 1; i < closes.length; i++)
            if (closes[i] > highest)
                highest = closes[i];
        return highest;
    }

    // ── Range ─────────────────────────────────────────────────────────────────
    readonly property real minValue: {
        if (closes.length === 0)
            return 0;
        let lowest = closes[0];
        for (let i = 1; i < closes.length; i++)
            if (closes[i] < lowest)
                lowest = closes[i];
        return lowest;
    }
    readonly property real valueRange: maxValue - minValue > 0 ? maxValue - minValue : 1

    // ── Coordinate mapping ────────────────────────────────────────────────────
    // Returns an array of { x, y } canvas pixel coordinates for the given
    // canvas dimensions and padding. Returns [] when fewer than 2 closes.
    function normalizedPoints(canvasWidth, canvasHeight, padding) {
        if (closes.length < 2)
            return [];
        let points = [];
        let drawableWidth = canvasWidth - padding * 2;
        let drawableHeight = canvasHeight - padding * 2;
        for (let i = 0; i < closes.length; i++) {
            points.push({
                x: padding + (i / (closes.length - 1)) * drawableWidth,
                y: padding + (1 - (closes[i] - minValue) / valueRange) * drawableHeight
            });
        }
        return points;
    }
}
