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
import "../../JS/Contracts/Resolution.js" as Resolution
import "../../JS/Helpers/Helpers.js" as Helpers
import "../../JS/Helpers/SymbolErrorMap.js" as SymbolErrors
import "../Helpers"
import "../Services"
import qs.Common
import qs.Widgets

Item {
    id: symbolRow

    property int _agoTick: 0      // bumped by timer to refresh "ago" text

    property real change: (priceInfo.change !== undefined && !isNaN(priceInfo.change)) ? priceInfo.change : 0
    property color changeColor: isPositive ? upColor : downColor
    property real changePct: (priceInfo.changePercent !== undefined && !isNaN(priceInfo.changePercent)) ? priceInfo.changePercent : 0
    property var chartData: []     // DataPoint[] for the sparkline
    readonly property bool chartFailed: SymbolErrors.chartFailed(symbolError) && !hasChart

    // The chart is rounded concentrically with the card: the theme's corner radius less the gap between card and chart, so the two
    // curves run parallel with a constant gap (the same radius on a rectangle inset by the gap looks different from the card's).
    // By the ClippingRectangle below; see the notes on rounded corners at the top of PriceChart.qml.
    readonly property real chartRadius: Math.max(0, Theme.cornerRadius - constants.chartAreaMargin)
    property color downColor
    readonly property string errorDetails: SymbolErrors.details(symbolError)
    readonly property string errorMessage: priceFailed ? SymbolErrors.message(symbolError) : (chartFailed ? SymbolErrors.message({
            graph: symbolError.graph
        }) : "")

    // A failed pull replaces the information it would have shown with a short message
    // (see SymbolErrorMap.js): a failed price replaces the price and the chart, a failed
    // chart only the chart.
    // A failed refresh never hides what was already loaded: the old price and chart stay (dimmed, "stale")
    // and the message only appears for information that was never loaded.
    readonly property bool hasChart: chartData && chartData.length > 0
    property bool hasData: price > 0
    property bool isLoading: false  // true while fetching

    // ── Derived ──────────────────────────────────────────────────────────────
    property bool isPinned: symbolData.pinned || false
    property bool isPositive: change >= 0
    property real lastFetchTime: 0      // epoch ms of last price fetch
    property real price: (priceInfo.close !== undefined && !isNaN(priceInfo.close)) ? priceInfo.close : 0
    readonly property bool priceFailed: SymbolErrors.priceFailed(symbolError) && !hasData
    property var priceInfo: ({})   // a PriceInfo (empty until the first price arrived)
    readonly property bool refreshFailed: SymbolErrors.priceFailed(symbolError) || SymbolErrors.chartFailed(symbolError)
    property bool showChartRange: true
    property bool showPriceChange: true
    property bool showProviderName: true
    property bool showRefreshedSince: true

    // Display toggles - Widget.qml always supplies these via PopoutPanel
    property bool showTicker: true
    readonly property bool stale: refreshFailed && !priceFailed && !chartFailed

    // ── Public properties ────────────────────────────────────────────────────
    property var symbolData: ({})   // a SavedSymbol
    property var symbolError: ({})   // this symbol's entry of the SymbolErrors map: { price?, graph? } (empty = fine)

    // Configurable colors - Widget.qml always supplies these via PopoutPanel
    property color upColor

    signal refreshSymbol
    signal removeSymbol
    signal togglePin

    // Format elapsed time using the shared relative-time helper.
    function _timeAgo(epochMs) {
        return Helpers.timeAgo(epochMs);
    }

    // ── Internal helpers ─────────────────────────────────────────────────────
    function formatNumber(value, decimals) {
        return Helpers.formatNumber(value, decimals);
    }

    height: constants.symbolRowHeight

    Component.onCompleted: Logger.debug("view", symbolData.ticker + ": chart corner radius " + chartRadius + " (theme " + Theme.cornerRadius + ")")

    Constants {
        id: constants
    }

    // ── "X sec ago" refresh timer ─────────────────────────────────────────────
    Timer {
        interval: constants.agoTickMs
        repeat: true
        running: symbolRow.lastFetchTime > 0

        onTriggered: symbolRow._agoTick++
    }

    // ── Background card ──────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        border.color: Theme.outlineMedium
        border.width: 1
        color: Theme.nestedSurface
        radius: Theme.cornerRadius
    }

    // ── Name column ──────────────────────────────────────────────────────────
    Column {
        id: nameColumn

        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        spacing: constants.symbolColSpacing
        width: constants.symbolNameColumnW

        StyledText {
            color: Theme.surfaceText
            elide: Text.ElideRight
            font.pixelSize: Theme.fontSizeMedium + constants.symbolNameFontSizeDelta
            font.weight: Font.Bold
            text: symbolRow.symbolData.name || symbolRow.symbolData.ticker || "-"
            width: parent.width
            wrapMode: Text.NoWrap
        }
        StyledText {
            color: Theme.surfaceVariantText
            elide: Text.ElideRight
            font.pixelSize: Theme.fontSizeSmall + constants.symbolTickerFontSizeDelta
            text: (symbolRow.symbolData.ticker || "") + " • " + Resolution.shortLabel(symbolRow.symbolData.priceResolution)
            visible: symbolRow.showTicker
            width: parent.width
            wrapMode: Text.NoWrap
        }
        StyledText {
            color: symbolRow.isLoading ? Theme.primary : Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall + constants.smallFontSizeDelta
            text: {
                void symbolRow._agoTick;
                return symbolRow.isLoading ? "refreshing…" : symbolRow._timeAgo(symbolRow.lastFetchTime);
            }
            visible: symbolRow.showRefreshedSince && (symbolRow.lastFetchTime > 0 || symbolRow.isLoading)
        }
    }

    // ── Price column ─────────────────────────────────────────────────────────
    Column {
        id: priceColumn

        anchors.left: nameColumn.right
        anchors.leftMargin: Theme.spacingS + constants.symbolPriceColumnShift
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1
        visible: !symbolRow.priceFailed
        width: constants.symbolPriceColumnW

        StyledText {
            color: symbolRow.stale ? Theme.surfaceVariantText : Theme.surfaceText
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            text: symbolRow.hasData ? symbolRow.formatNumber(symbolRow.price) : (symbolRow.isLoading ? "Loading…" : "-")
        }
        StyledText {
            color: symbolRow.changeColor
            font.pixelSize: Theme.fontSizeSmall + constants.smallFontSizeDelta
            text: (symbolRow.isPositive ? "+" : "") + symbolRow.formatNumber(symbolRow.change)
            visible: symbolRow.hasData && symbolRow.showPriceChange
        }
        StyledText {
            color: symbolRow.changeColor
            font.pixelSize: Theme.fontSizeSmall + constants.smallFontSizeDelta
            text: "(" + (symbolRow.isPositive ? "+" : "") + symbolRow.changePct.toFixed(2) + "%)"
            visible: symbolRow.hasData && symbolRow.showPriceChange
        }
    }

    // ── Chart area (fills remaining space) ───────────────────────────────────
    Item {
        id: chartArea

        anchors.bottom: parent.bottom
        anchors.bottomMargin: constants.chartAreaMargin
        anchors.left: symbolRow.priceFailed ? nameColumn.right : priceColumn.right
        anchors.leftMargin: constants.chartAreaMargin
        anchors.right: parent.right
        anchors.rightMargin: constants.chartAreaMargin
        anchors.top: parent.top
        anchors.topMargin: constants.chartAreaMargin

        // Clipped by Quickshell's ClippingRectangle, the item DMS itself uses for its rounded wallpaper, artwork and avatar
        // images (checked on a real GPU window: it clips a canvas child to the rounded shape).
        ClippingRectangle {
            anchors.fill: parent
            color: "transparent"
            radius: symbolRow.chartRadius
            visible: !symbolRow.priceFailed && !symbolRow.chartFailed

            PriceChart {
                anchors.fill: parent
                chartRange: symbolRow.symbolData.chartRange || ""
                dataPoints: symbolRow.chartData
                isLoading: symbolRow.isLoading
                negativeColor: symbolRow.downColor
                positiveColor: symbolRow.upColor
                providerAlias: ProvidersManager.aliasOf(symbolRow.symbolData.provider || ProvidersManager.defaultId)
                showProviderName: symbolRow.showProviderName
                showRangeLabel: symbolRow.showChartRange
                visible: !symbolRow.priceFailed && !symbolRow.chartFailed
            }
        }

        // ── Error message (instead of the information that could not be loaded) ──
        Row {
            id: errorBlock

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.rightMargin: constants.actionButtonSize * 3 + constants.actionButtonSpacing * 3   // keep clear of the hover buttons
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXS
            visible: symbolRow.errorMessage !== ""

            DankIcon {
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.error
                name: "error"
                size: constants.actionIconSize
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.error
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSizeSmall
                maximumLineCount: 3
                text: symbolRow.errorMessage
                width: parent.width - constants.actionIconSize - Theme.spacingXS
                wrapMode: Text.WordWrap
            }
        }

        // ── Chart click → open symbol page ───────────────────────────────
        MouseArea {
            id: chartMouseArea

            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true

            onClicked: {
                // A damaged saved symbol raises INVALID_SYMBOL here instead of opening a broken URL.
                let opened = ErrorHandler.guard("symbol-row", function () {
                    let url = ProvidersManager.requireFromId(symbolRow.symbolData.provider || ProvidersManager.defaultId).symbolPageUrl(symbolRow.symbolData.ticker || "");
                    if (url)
                        Qt.openUrlExternally(url);
                }, {
                    context: symbolRow.symbolData.ticker
                });
            }
        }

        // ── Hover action buttons (overlay) ───────────────────────────────
        Row {
            anchors.right: parent.right
            anchors.rightMargin: constants.chartPadding
            anchors.top: parent.top
            anchors.topMargin: constants.chartPadding
            spacing: constants.actionButtonSpacing
            visible: chartMouseArea.containsMouse || refreshButton.hovered || pinButton.hovered || removeButton.hovered || symbolRow.isLoading
            z: constants.overlayZ

            IconButton {
                id: refreshButton

                iconColor: symbolRow.isLoading ? Theme.primary : Theme.surfaceVariantText
                iconName: "refresh"
                pressable: !symbolRow.isLoading
                spinning: symbolRow.isLoading

                onClicked: symbolRow.refreshSymbol()
            }
            IconButton {
                id: pinButton

                iconColor: symbolRow.isPinned ? Theme.primary : Theme.surfaceVariantText
                iconName: "push_pin"
                iconRotation: symbolRow.isPinned ? 0 : constants.unpinnedRotationDeg

                onClicked: symbolRow.togglePin()
            }
            IconButton {
                id: removeButton

                iconColor: removeButton.hovered ? Theme.error : Theme.surfaceVariantText
                iconName: "close"
                iconSize: constants.actionCloseIconSize

                onClicked: symbolRow.removeSymbol()
            }
        }
    }
}
