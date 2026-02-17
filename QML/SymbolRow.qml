// SymbolRow.qml — Single symbol card for the popout list
//
// Layout:
// ┌──────────────────────────────────────────────────────┐
// │  USDX          104.50  ╱╲ sparkline ╱╲   [📌] [✕]  │
// │  dx.f • 1h     +0.30                (on hover)      │
// │                (+0.29%)                              │
// └──────────────────────────────────────────────────────┘

import QtQuick
import qs.Common
import qs.Widgets
import "../JS/ProviderInterface.js" as Providers
import "../JS/StooqProvider.js" as StooqProvider

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

    // Configurable up/down colors (passed from widget)
    property color upColor:   "#4CAF50"
    property color downColor: "#F44336"
    property color changeColor: isPositive ? upColor : downColor

    // ── Number formatting with thousands separator ───────────────────────────
    function formatNumber(num, decimals) {
        if (isNaN(num)) return "—"
        var fixed = num.toFixed(decimals !== undefined ? decimals : 2)
        var parts = fixed.split(".")
        parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",")
        return parts.join(".")
    }

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
            text: hasData ? formatNumber(price) : (isLoading ? "Loading…" : "—")
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        StyledText {
            visible: hasData
            text: (isPositive ? "+" : "") + formatNumber(change)
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

    // ── Mini chart (fills remaining space) ───────────────────────────────────
    Item {
        id: chartArea
        anchors.left: priceCol.right
        anchors.leftMargin: Theme.spacingS
        anchors.right: parent.right
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
            positiveColor: symbolRow.upColor
            negativeColor: symbolRow.downColor
        }

        MouseArea {
            id: chartMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                var url = Providers.buildSymbolPageUrl(symbolData.provider || Providers.getDefaultProviderId(), symbolData.id || "")
                if (url) Qt.openUrlExternally(url)
            }
        }

        // ── Hover action buttons (overlay) ───────────────────────────────
        Row {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: 2
            anchors.topMargin: 2
            spacing: 4
            visible: chartMouseArea.containsMouse
            z: 10

            Rectangle {
                width: 22; height: 22; radius: 11
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.85)

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: symbolRow.togglePin()
                }

                DankIcon {
                    anchors.centerIn: parent
                    name: "push_pin"
                    size: 14
                    color: isPinned ? Theme.primary : Theme.surfaceVariantText
                    rotation: isPinned ? 0 : 45
                }
            }

            Rectangle {
                width: 22; height: 22; radius: 11
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.85)

                MouseArea {
                    id: removeBtnMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: symbolRow.removeSymbol()
                }

                DankIcon {
                    anchors.centerIn: parent
                    name: "close"
                    size: 12
                    color: removeBtnMouse.containsMouse ? Theme.error : Theme.surfaceVariantText
                }
            }
        }
    }
}
