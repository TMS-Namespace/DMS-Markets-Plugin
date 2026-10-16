// SymbolRow.qml - Single symbol card for the popout list
//
// Layout:
// ┌──────────────────────────────────────────────────────┐
// │  EUR/USD       1.16    ╱╲ sparkline ╱╲   [📌] [✕]  │
// │  symbol • 1h   +0.01                (on hover)      │
// │                (+0.29%)                              │
// └──────────────────────────────────────────────────────┘
//
// Moved from QML/ to QML/Views/ to keep all view-layer components together.

import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Widgets
import "../Helpers"
import "../Services"
import "../../JS/Helpers/Helpers.js" as Helpers
import "../../JS/Helpers/SymbolErrorMap.js" as SymbolErrors
import "../../JS/Contracts/Resolution.js" as Resolution

Item {
    id: symbolRow

    Constants { id: constants }

    // ── Public properties ────────────────────────────────────────────────────
    property var  symbolData:    ({})   // a SavedSymbol
    property var  priceInfo:     ({})   // a PriceInfo (empty until the first price arrived)
    property var  chartData:     []     // DataPoint[] for the sparkline
    property bool isLoading:     false  // true while fetching
    property real lastFetchTime: 0      // epoch ms of last price fetch
    property var  symbolError:   ({})   // this symbol's entry of the SymbolErrors map: { price?, graph? } (empty = fine)
    property int  _agoTick:      0      // bumped by timer to refresh "ago" text

    signal togglePin()
    signal removeSymbol()
    signal refreshSymbol()

    // ── "X sec ago" refresh timer ─────────────────────────────────────────────
    Timer {
        interval: constants.agoTickMs
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

    // A failed pull replaces the information it would have shown with a short message
    // (see SymbolErrorMap.js): a failed price replaces the price and the chart, a failed
    // chart only the chart.
    // A failed refresh never hides what was already loaded: the old price and chart stay (dimmed, "stale")
    // and the message only appears for information that was never loaded.
    readonly property bool   hasChart:      chartData && chartData.length > 0
    readonly property bool   refreshFailed: SymbolErrors.priceFailed(symbolError) || SymbolErrors.chartFailed(symbolError)
    readonly property bool   priceFailed:   SymbolErrors.priceFailed(symbolError) && !hasData
    readonly property bool   chartFailed:   SymbolErrors.chartFailed(symbolError) && !hasChart
    readonly property bool   stale:         refreshFailed && !priceFailed && !chartFailed
    readonly property string errorMessage:  priceFailed ? SymbolErrors.message(symbolError) : (chartFailed ? SymbolErrors.message({ graph: symbolError.graph }) : "")
    readonly property string errorDetails:  SymbolErrors.details(symbolError)

    // Configurable colors - Widget.qml always supplies these via PopoutPanel
    property color upColor
    property color downColor
    property color changeColor: isPositive ? upColor : downColor

    // Display toggles - Widget.qml always supplies these via PopoutPanel
    property bool showTicker:         true
    property bool showPriceChange:     true
    property bool showChartRange:     true
    property bool showProviderName:   true
    property bool showRefreshedSince: true

    // ── Internal helpers ─────────────────────────────────────────────────────
    function formatNumber(value, decimals) { return Helpers.formatNumber(value, decimals) }
    // Format elapsed time using the shared relative-time helper.
    function _timeAgo(epochMs)         { return Helpers.timeAgo(epochMs) }

    height: constants.symbolRowHeight

    // The chart is rounded concentrically with the card: the theme's corner radius less the gap between card and chart, so the two
    // curves run parallel with a constant gap (the same radius on a rectangle inset by the gap looks different from the card's).
    // By the ClippingRectangle below; see the notes on rounded corners at the top of PriceChart.qml.
    readonly property real chartRadius: Math.max(0, Theme.cornerRadius - constants.chartAreaMargin)
    Component.onCompleted: Logger.debug("view", symbolData.ticker + ": chart corner radius " + chartRadius + " (theme " + Theme.cornerRadius + ")")

    // ── Background card ──────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        radius:       Theme.cornerRadius
        color:        Theme.nestedSurface
        border.color: Theme.outlineMedium
        border.width: 1
    }

    // ── Name column ──────────────────────────────────────────────────────────
    Column {
        id: nameColumn
        width:   constants.symbolNameColumnW
        anchors.left:            parent.left
        anchors.leftMargin:      Theme.spacingS
        anchors.verticalCenter:  parent.verticalCenter
        spacing: constants.symbolColSpacing

        StyledText {
            text:           symbolData.name || symbolData.ticker || "-"
            font.pixelSize: Theme.fontSizeMedium + constants.symbolNameFontSizeDelta
            font.weight:    Font.Bold
            color:          Theme.surfaceText
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            width: parent.width
        }

        StyledText {
            visible:        symbolRow.showTicker
            text:           (symbolData.ticker || "") + " • " + Resolution.shortLabel(symbolData.priceResolution)
            font.pixelSize: Theme.fontSizeSmall + constants.symbolTickerFontSizeDelta
            color:          Theme.surfaceVariantText
            elide:          Text.ElideRight
            wrapMode:       Text.NoWrap
            width:          parent.width
        }

        StyledText {
            visible:        symbolRow.showRefreshedSince && (lastFetchTime > 0 || isLoading)
            text:           { void _agoTick; return isLoading ? "refreshing…" : _timeAgo(lastFetchTime) }
            font.pixelSize: Theme.fontSizeSmall + constants.smallFontSizeDelta
            color:          isLoading ? Theme.primary : Theme.surfaceVariantText
        }
    }

    // ── Price column ─────────────────────────────────────────────────────────
    Column {
        id: priceColumn
        width:   constants.symbolPriceColumnW
        anchors.left:           nameColumn.right
        anchors.leftMargin:     Theme.spacingS + constants.symbolPriceColumnShift
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1
        visible: !symbolRow.priceFailed

        StyledText {
            text:           hasData ? formatNumber(price) : (isLoading ? "Loading…" : "-")
            font.pixelSize: Theme.fontSizeMedium
            font.weight:    Font.Medium
            color:          symbolRow.stale ? Theme.surfaceVariantText : Theme.surfaceText
        }

        StyledText {
            visible:        hasData && symbolRow.showPriceChange
            text:           (isPositive ? "+" : "") + formatNumber(change)
            font.pixelSize: Theme.fontSizeSmall + constants.smallFontSizeDelta
            color:          changeColor
        }

        StyledText {
            visible:        hasData && symbolRow.showPriceChange
            text:           "(" + (isPositive ? "+" : "") + changePct.toFixed(2) + "%)"
            font.pixelSize: Theme.fontSizeSmall + constants.smallFontSizeDelta
            color:          changeColor
        }
    }

    // ── Chart area (fills remaining space) ───────────────────────────────────
    Item {
        id: chartArea
        anchors.left:        symbolRow.priceFailed ? nameColumn.right : priceColumn.right
        anchors.leftMargin:  constants.chartAreaMargin
        anchors.right:       parent.right
        anchors.rightMargin: constants.chartAreaMargin
        anchors.top:         parent.top
        anchors.topMargin:   constants.chartAreaMargin
        anchors.bottom:      parent.bottom
        anchors.bottomMargin: constants.chartAreaMargin

        // Clipped by Quickshell's ClippingRectangle, the item DMS itself uses for its rounded wallpaper, artwork and avatar
        // images (checked on a real GPU window: it clips a canvas child to the rounded shape).
        ClippingRectangle {
            anchors.fill: parent
            radius:       symbolRow.chartRadius
            color:        "transparent"
            visible:      !symbolRow.priceFailed && !symbolRow.chartFailed

            PriceChart {
                anchors.fill:   parent
                visible:        !symbolRow.priceFailed && !symbolRow.chartFailed
                dataPoints:     symbolRow.chartData
                isLoading:      symbolRow.isLoading
                chartRange:     symbolData.chartRange || ""
                showRangeLabel: symbolRow.showChartRange
                showProviderName: symbolRow.showProviderName
                providerAlias:  ProvidersManager.aliasOf(symbolData.provider || ProvidersManager.defaultId)
                positiveColor:  symbolRow.upColor
                negativeColor:  symbolRow.downColor
            }
        }

        // ── Error message (instead of the information that could not be loaded) ──
        Row {
            id: errorBlock
            visible: symbolRow.errorMessage !== ""
            anchors.left:           parent.left
            anchors.right:          parent.right
            anchors.rightMargin:    constants.actionButtonSize * 3 + constants.actionButtonSpacing * 3   // keep clear of the hover buttons
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXS

            DankIcon {
                name:  "error"
                size:  constants.actionIconSize
                color: Theme.error
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                width: parent.width - constants.actionIconSize - Theme.spacingXS
                text:  symbolRow.errorMessage
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.error
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // ── Chart click → open symbol page ───────────────────────────────
        MouseArea {
            id: chartMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape:  Qt.PointingHandCursor
            onClicked: {
                // A damaged saved symbol raises INVALID_SYMBOL here instead of opening a broken URL.
                var opened = ErrorHandler.guard("symbol-row", function() {
                    var url = ProvidersManager.requireFromId(symbolData.provider || ProvidersManager.defaultId)
                                  .symbolPageUrl(symbolData.ticker || "")
                    if (url) Qt.openUrlExternally(url)
                }, { context: symbolData.ticker })
            }
        }

        // ── Hover action buttons (overlay) ───────────────────────────────
        Row {
            anchors.right:       parent.right
            anchors.top:         parent.top
            anchors.rightMargin: constants.chartPadding
            anchors.topMargin:   constants.chartPadding
            spacing: constants.actionButtonSpacing
            visible: chartMouseArea.containsMouse
                     || refreshButton.hovered
                     || pinButton.hovered
                     || removeButton.hovered
                     || symbolRow.isLoading
            z: constants.overlayZ

            IconButton {
                id: refreshButton
                iconName:  "refresh"
                iconColor: symbolRow.isLoading ? Theme.primary : Theme.surfaceVariantText
                spinning:  symbolRow.isLoading
                pressable: !symbolRow.isLoading
                onClicked: symbolRow.refreshSymbol()
            }

            IconButton {
                id: pinButton
                iconName:     "push_pin"
                iconColor:    isPinned ? Theme.primary : Theme.surfaceVariantText
                iconRotation: isPinned ? 0 : constants.unpinnedRotationDeg
                onClicked:    symbolRow.togglePin()
            }

            IconButton {
                id: removeButton
                iconName:  "close"
                iconSize:  constants.actionCloseIconSize
                iconColor: removeButton.hovered ? Theme.error : Theme.surfaceVariantText
                onClicked: symbolRow.removeSymbol()
            }
        }
    }
}
