// SymbolRow.qml — Single symbol card for the popout list
//
// Layout:
// ┌──────────────────────────────────────────────────────┐
// │  USDX          104.50  ╱╲ sparkline ╱╲   [📌] [✕]  │
// │  dx.f • 1h     +0.30                (on hover)      │
// │                (+0.29%)                              │
// └──────────────────────────────────────────────────────┘
//
// Moved from QML/ to QML/Views/ to keep all view-layer components together.

import QtQuick
import qs.Common
import qs.Widgets
import "../Helpers"
import "../../JS/ProviderInterface.js" as Providers
import "../../JS/Helpers.js" as Helpers

Item {
    id: symbolRow

    Constants { id: c }

    // ── Public properties ────────────────────────────────────────────────────
    property var  symbolData:    ({})   // { id, name, provider, priceInterval, graphInterval, pinned }
    property var  priceInfo:     ({})   // { open, high, low, close, change, changePercent, date, time }
    property var  chartData:     []     // DataPoint[] for sparkline
    property bool isLoading:     false  // true while fetching
    property real lastFetchTime: 0      // epoch ms of last price fetch
    property int  _agoTick:      0      // bumped by timer to refresh "ago" text

    signal togglePin()
    signal removeSymbol()
    signal refreshSymbol()

    // ── "X sec ago" refresh timer ─────────────────────────────────────────────
    Timer {
        interval: c.agoTickMs
        running:  lastFetchTime > 0
        repeat:   true
        onTriggered: symbolRow._agoTick++
    }

    // ── Derived ──────────────────────────────────────────────────────────────
    property bool  isPinned:   symbolData.pinned || false
    property real  price:      (priceInfo.close       !== undefined && !isNaN(priceInfo.close))       ? priceInfo.close       : 0
    property real  change:     (priceInfo.change      !== undefined && !isNaN(priceInfo.change))      ? priceInfo.change      : 0
    property real  changePct:  (priceInfo.changePercent !== undefined && !isNaN(priceInfo.changePercent)) ? priceInfo.changePercent : 0
    property bool  isPositive: change >= 0
    property bool  hasData:    price > 0

    // Configurable colors — Widget.qml always supplies these via PopoutPanel
    property color upColor
    property color downColor
    property color changeColor: isPositive ? upColor : downColor

    // Display toggles — Widget.qml always supplies these via PopoutPanel
    property bool showTicker:         true
    property bool showPriceRange:     true
    property bool showChartRange:     true
    property bool showRefreshedSince: true

    // ── Internal helpers ─────────────────────────────────────────────────────
    function formatNumber(n, decimals) { return Helpers.formatNumber(n, decimals) }
    function _timeAgo(epochMs)         { return Helpers.timeAgo(epochMs) }

    height: c.symbolRowHeight

    // ── Background card ──────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color:  Theme.surfaceContainerHigh
    }

    // ── Name column ──────────────────────────────────────────────────────────
    Column {
        id: nameColumn
        width:   c.symbolNameColumnW
        anchors.left:            parent.left
        anchors.leftMargin:      Theme.spacingS
        anchors.verticalCenter:  parent.verticalCenter
        spacing: c.symbolColSpacing

        StyledText {
            text:           symbolData.name || symbolData.id || "—"
            font.pixelSize: Theme.fontSizeMedium
            font.weight:    Font.Bold
            color:          Theme.surfaceText
            elide: Text.ElideRight
            width: parent.width
        }

        StyledText {
            visible:        symbolRow.showTicker
            text:           (symbolData.id || "") + " • " + (symbolData.priceInterval || "1d")
            font.pixelSize: Theme.fontSizeSmall
            color:          Theme.surfaceVariantText
            elide:          Text.ElideRight
            width:          parent.width
        }

        StyledText {
            visible:        symbolRow.showRefreshedSince && (lastFetchTime > 0 || isLoading)
            text:           { void _agoTick; return isLoading ? "refreshing…" : _timeAgo(lastFetchTime) }
            font.pixelSize: c.smallFontSize
            color:          isLoading ? Theme.primary : Theme.surfaceVariantText
        }
    }

    // ── Price column ─────────────────────────────────────────────────────────
    Column {
        id: priceColumn
        width:   c.symbolPriceColumnW
        anchors.left:           nameColumn.right
        anchors.leftMargin:     Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        StyledText {
            text:           hasData ? formatNumber(price) : (isLoading ? "Loading…" : "—")
            font.pixelSize: Theme.fontSizeMedium
            font.weight:    Font.Medium
            color:          Theme.surfaceText
        }

        StyledText {
            visible:        hasData && symbolRow.showPriceRange
            text:           (isPositive ? "+" : "") + formatNumber(change)
            font.pixelSize: c.smallFontSize
            color:          changeColor
        }

        StyledText {
            visible:        hasData && symbolRow.showPriceRange
            text:           "(" + (isPositive ? "+" : "") + changePct.toFixed(2) + "%)"
            font.pixelSize: c.smallFontSize
            color:          changeColor
        }
    }

    // ── Chart area (fills remaining space) ───────────────────────────────────
    Item {
        id: chartArea
        anchors.left:        priceColumn.right
        anchors.leftMargin:  Theme.spacingS
        anchors.right:       parent.right
        anchors.rightMargin: Theme.spacingS
        anchors.top:         parent.top
        anchors.topMargin:   Theme.spacingS
        anchors.bottom:      parent.bottom
        anchors.bottomMargin: Theme.spacingS

        PriceChart {
            anchors.fill:   parent
            dataPoints:     symbolRow.chartData
            isLoading:      symbolRow.isLoading
            graphInterval:  symbolData.graphInterval || "1M"
            showRangeLabel: symbolRow.showChartRange
            positiveColor:  symbolRow.upColor
            negativeColor:  symbolRow.downColor
        }

        // ── Chart click → open symbol page ───────────────────────────────
        MouseArea {
            id: chartMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape:  Qt.PointingHandCursor
            onClicked: {
                var url = Providers.buildSymbolPageUrl(
                    symbolData.provider || Providers.getDefaultProviderId(),
                    symbolData.id || ""
                )
                if (url) Qt.openUrlExternally(url)
            }
        }

        // ── Hover action buttons (overlay) ───────────────────────────────
        Row {
            anchors.right:       parent.right
            anchors.top:         parent.top
            anchors.rightMargin: c.chartPadding
            anchors.topMargin:   c.chartPadding
            spacing: c.actionButtonSpacing
            visible: chartMouseArea.containsMouse
                     || refreshBtnMouse.containsMouse
                     || pinBtnMouse.containsMouse
                     || removeBtnMouse.containsMouse
                     || symbolRow.isLoading
            z: 10

            // Refresh button
            Rectangle {
                width: c.actionButtonSize; height: c.actionButtonSize; radius: c.actionButtonRadius
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, c.actionButtonBgOpacity)

                MouseArea {
                    id: refreshBtnMouse
                    anchors.fill: parent
                    cursorShape:  Qt.PointingHandCursor
                    hoverEnabled: true
                    enabled:      !symbolRow.isLoading
                    onClicked:    symbolRow.refreshSymbol()
                }

                DankIcon {
                    id: refreshIcon
                    anchors.centerIn: parent
                    name:  "refresh"
                    size:  c.actionIconSize
                    color: symbolRow.isLoading ? Theme.primary : Theme.surfaceVariantText

                    RotationAnimation on rotation {
                        running:  symbolRow.isLoading
                        from: 0; to: 360
                        duration: c.headerAnimDurationMs
                        loops:    Animation.Infinite
                    }

                    Connections {
                        target: symbolRow
                        function onIsLoadingChanged() {
                            if (!symbolRow.isLoading) refreshIcon.rotation = 0
                        }
                    }
                }
            }

            // Pin button
            Rectangle {
                width: c.actionButtonSize; height: c.actionButtonSize; radius: c.actionButtonRadius
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, c.actionButtonBgOpacity)

                MouseArea {
                    id: pinBtnMouse
                    anchors.fill: parent
                    cursorShape:  Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked:    symbolRow.togglePin()
                }

                DankIcon {
                    anchors.centerIn: parent
                    name:     "push_pin"
                    size:     c.actionIconSize
                    color:    isPinned ? Theme.primary : Theme.surfaceVariantText
                    rotation: isPinned ? 0 : 45
                }
            }

            // Remove button
            Rectangle {
                width: c.actionButtonSize; height: c.actionButtonSize; radius: c.actionButtonRadius
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, c.actionButtonBgOpacity)

                MouseArea {
                    id: removeBtnMouse
                    anchors.fill: parent
                    cursorShape:  Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked:    symbolRow.removeSymbol()
                }

                DankIcon {
                    anchors.centerIn: parent
                    name:  "close"
                    size:  c.actionCloseIconSize
                    color: removeBtnMouse.containsMouse ? Theme.error : Theme.surfaceVariantText
                }
            }
        }
    }
}
