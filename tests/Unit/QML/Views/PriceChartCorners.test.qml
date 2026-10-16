// The chart's corners are really rounded: the chart is painted in a real (offscreen) window and its pixels are read back.
import QtQuick
import QtQuick.Window
import "../../../Helpers"
import "../../../../src/QML/Views"

TestSuite {
    property Component windowType: Component {
        Window {
            id: root
            property alias chart: chartItem
            property real radius: 0
            width: 100; height: 60; visible: true
            PriceChart {
                id: chartItem
                anchors.fill: parent
                cornerRadius: root.radius
                // High at both ends, so the fill reaches all four corners.
                dataPoints: [{ date: "2026-01-01", time: "", open: 2, high: 2, low: 2, close: 2, volume: 0 },
                             { date: "2026-01-02", time: "", open: 1, high: 1, low: 1, close: 1, volume: 0 },
                             { date: "2026-01-03", time: "", open: 2, high: 2, low: 2, close: 2, volume: 0 }]
            }
        }
    }
    property var win: null
    function teardown() { if (win) { win.destroy(); win = null } }

    // Alpha (0-255) of four pixels that are filled in a square chart and lie in the corner pieces a radius of 25 erases, plus one inside.
    function alphas(radius, done) {
        win = windowType.createObject(null, { radius: radius })
        waitUntil(function() { return win.chart.available }, function(problem) {
            if (problem) { done(null, problem); return }
            win.chart.requestPaint()
            waitUntil(function() { return false }, function() {
                var context = win.chart.getContext("2d")
                function alpha(x, y) { return context.getImageData(x, y, 1, 1).data[3] }
                done({ topLeft: alpha(4, 6), topRight: alpha(96, 6), bottomLeft: alpha(4, 52), bottomRight: alpha(96, 52), middle: alpha(10, 30) }, "")
            }, 400)
        }, 5000)
    }

    function async_a_square_chart_paints_into_its_corners(done) {
        alphas(0, function(result, problem) {
            if (problem) { done(problem); return }
            done(result.topLeft > 0 && result.topRight > 0 && result.bottomLeft > 0 && result.bottomRight > 0 ? "" : "the corners are empty without a radius: " + JSON.stringify(result))
        })
    }
    function async_a_rounded_chart_leaves_all_four_corners_empty_and_the_rest_drawn(done) {
        alphas(25, function(result, problem) {
            if (problem) { done(problem); return }
            var corners = [result.topLeft, result.topRight, result.bottomLeft, result.bottomRight]
            done(corners.every(function(value) { return value === 0 }) && result.middle > 0 ? "" : "corners / middle: " + JSON.stringify(result))
        })
    }
    function async_a_radius_larger_than_the_chart_does_not_break_it(done) {
        alphas(500, function(result, problem) {
            done(problem || (result.middle > 0 ? "" : "nothing is left of the chart: " + JSON.stringify(result)))
        })
    }
}
