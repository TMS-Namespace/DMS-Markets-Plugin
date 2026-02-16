// SymbolRow.qml — Single symbol card for the popout list
//
// Layout:
// ┌──────────────────────────────────────────────────────┐
// │  USDX          104.50  ╱╲ sparkline ╱╲    📌   ✕   │
// │  dx.f • 1h     +0.30 (+0.29%)                       │
// └──────────────────────────────────────────────────────┘

import QtQuick
import qs.Common
import qs.Widgets

Item {
    id: symbolRow

    // ── Public properties ────────────────────────────────────────────────────
    property var  symbolData: ({})       // { id, name, provider, priceInterval, graphInterval, pinned }
    property var  priceInfo:  ({})       // { open, high, low, close, change, changePercent, date, time }
    property var  chartData:  []         // DataPoint[] for sparkline
    property bool isLoading:  false      // True while fetching data

    signal togglePin()
    signal removeSymbol()

    // ── Derived ──────────────────────────────────────────────────────────────
    property bool  isPinned:    symbolData.pinned || false
    property real  price:       (priceInfo.close !== undefined && !isNaN(priceInfo.close)) ? priceInfo.close : 0
    property real  change:      (priceInfo.change !== undefined && !isNaN(priceInfo.change)) ? priceInfo.change : 0
    property real  changePct:   (priceInfo.changePercent !== undefined && !isNaN(priceInfo.changePercent)) ? priceInfo.changePercent : 0
    property bool  isPositive:  change >= 0
    property bool  hasData:     price > 0
    property color changeColor: isPositive ? "#4CAF50" : "#F44336"

    height: 76

    // ── Background card ──────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh
    }

    // ── Name column (left-anchored) ──────────────────────────────────────────
    Column {
        id: nameCol
        width: 90
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        StyledText {
            text: symbolData.name || symbolData.id || "—"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Bold
            color: Theme.surfaceText
            elide: Text.ElideRight
            width: parent.width
        }

        StyledText {
            text: (symbolData.id || "") + " • " + (symbolData.priceInterval || "1d")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            elide: Text.ElideRight
            width: parent.width
        }
    }

    // ── Price column ─────────────────────────────────────────────────────────
    Column {
        id: priceCol
        width: 86
        anchors.left: nameCol.right
        anchors.leftMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        StyledText {
            text: hasData ? price.toFixed(2) : (isLoading ? "Loading…" : "—")
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        StyledText {
            visible: hasData
            text: (isPositive ? "+" : "") + change.toFixed(2)
            font.pixelSize: 10
            color: changeColor
        }

        StyledText {
            visible: hasData
            text: "(" + (isPositive ? "+" : "") + changePct.toFixed(2) + "%)"
            font.pixelSize: 10
            color: changeColor
        }
    }

    // ── Actions (right-anchored) ─────────────────────────────────────────────
    Column {
        id: actionsCol
        width: 28
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingS

        // Pin button
        MouseArea {
            width: 24
            height: 24
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onClicked: symbolRow.togglePin()

            DankIcon {
                anchors.centerIn: parent
                name: "push_pin"
                size: 18
                color: isPinned ? Theme.primary : Theme.surfaceVariantText
                rotation: isPinned ? 0 : 45
            }
        }

        // Remove button
        MouseArea {
            width: 24
            height: 24
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onClicked: symbolRow.removeSymbol()

            DankIcon {
                anchors.centerIn: parent
                name: "close"
                size: 16
                color: parent.containsMouse ? Theme.error : Theme.surfaceVariantText
            }
        }
    }

    // ── Mini chart (fills remaining space) ───────────────────────────────────
    Item {
        id: chartArea
        anchors.left: priceCol.right
        anchors.leftMargin: Theme.spacingS
        anchors.right: actionsCol.left
        anchors.rightMargin: Theme.spacingS
        anchors.top: parent.top
        anchors.topMargin: Theme.spacingS
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.spacingS

        PriceChart {
            id: miniChart
            anchors.fill: parent
            dataPoints: symbolRow.chartData
            isLoading: symbolRow.isLoading
            graphInterval: symbolData.graphInterval || "1M"
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Qt.openUrlExternally("https://stooq.com/q/?s=" + encodeURIComponent(symbolData.id || ""))
        }
    }
}
