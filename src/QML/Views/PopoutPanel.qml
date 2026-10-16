// PopoutPanel.qml — Popout content area for the Markets plugin
//
// Contains the symbol list, header hover buttons (refresh all + close),
// custom scroll indicator, and empty-state placeholder.
// Moved from QML/ to QML/Views/ so all view-layer components live together.

import QtQuick
import qs.Common
import qs.Widgets
import "../Helpers"
import "../../JS/Contracts/FetchType.js" as FetchType

Item {
    id: panel

    Constants { id: constants }

    // ── Data inputs (bound from Widget.qml) ──────────────────────────────────
    property var  symbols:        []
    property var  priceData:      ({})
    property var  graphData:      ({})
    property var  pendingFetches: ({})
    property var  lastFetchTimes: ({})
    property var  symbolErrors:   ({})   // { uid: { price, graph } }

    // ── Display settings (Widget.qml always binds all of these) ──────────────
    property color upColor
    property color downColor
    property bool  showTicker:         true
    property bool  showPriceChange:     true
    property bool  showChartRange:     true
    property bool  showProviderName:   true
    property bool  showRefreshedSince: true
    property int   popoutRows:         constants.defaultPopoutRows

    // ── Header geometry (for positioning overlay buttons) ─────────────────────
    property real  headerOffset: 0    // headerHeight + detailsHeight

    // ── Signals (forwarded to Widget.qml) ────────────────────────────────────
    signal togglePin(string uid)
    signal removeSymbol(string uid)
    signal refreshSymbol(string uid)
    signal refreshAll()
    signal closePopout()

    // ── Computed ─────────────────────────────────────────────────────────────
    property bool _anyLoading: {
        for (var key in pendingFetches)
            if (pendingFetches[key] > 0) return true
        return false
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  HEADER HOVER BUTTONS (positioned over header via negative y offset)
    // ═════════════════════════════════════════════════════════════════════════

    MouseArea {
        id: headerHoverArea
        x: 0; width: parent.width
        y: -panel.headerOffset
        height: panel.headerOffset
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        z: constants.headerHoverZ
    }

    Row {
        id: headerButtons
        anchors.right:       parent.right
        anchors.rightMargin: Theme.spacingS
        y:       -panel.headerOffset + Theme.spacingS
        spacing: constants.headerButtonSpacing
        visible: headerHoverArea.containsMouse
                 || refreshAllButton.hovered
                 || closePopoutButton.hovered
                 || panel._anyLoading
        z: constants.headerButtonZ

        IconButton {
            id: refreshAllButton
            buttonSize: constants.headerButtonSize; buttonRadius: constants.headerButtonRadius
            iconName:   "refresh"
            iconSize:   constants.headerIconSize
            iconColor:  panel._anyLoading ? Theme.primary : Theme.surfaceText
            hoverTint:  Theme.primary
            spinning:   panel._anyLoading
            pressable:  !panel._anyLoading
            onClicked:  panel.refreshAll()
        }

        IconButton {
            id: closePopoutButton
            buttonSize: constants.headerButtonSize; buttonRadius: constants.headerButtonRadius
            iconName:   "close"
            iconSize:   constants.headerIconSize
            iconColor:  closePopoutButton.hovered ? Theme.error : Theme.surfaceText
            hoverTint:  Theme.error
            onClicked:  panel.closePopout()
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  SYMBOL LIST
    // ═════════════════════════════════════════════════════════════════════════

    ListView {
        id: symbolList
        anchors.left:   parent.left
        anchors.right:  scrollIndicator.visible ? scrollIndicator.left : parent.right
        anchors.top:    parent.top
        anchors.bottom: parent.bottom
        spacing:        Theme.spacingS
        clip:           true
        model:          panel.symbols
        boundsBehavior: Flickable.StopAtBounds

        delegate: SymbolRow {
            width:         symbolList.width
            symbolData:    modelData
            priceInfo:     panel.priceData[modelData.uid]  || ({})
            chartData:     panel.graphData[modelData.uid]  || []
            isLoading:     (panel.pendingFetches[modelData.uid] || 0) > 0
            lastFetchTime: panel.lastFetchTimes[FetchType.timeKey(modelData.uid, FetchType.Values.PRICE)] || 0
            symbolError:   panel.symbolErrors[modelData.uid] || ({})
            upColor:       panel.upColor
            downColor:     panel.downColor
            showTicker:          panel.showTicker
            showPriceChange:      panel.showPriceChange
            showChartRange:      panel.showChartRange
            showProviderName:    panel.showProviderName
            showRefreshedSince:  panel.showRefreshedSince

            onTogglePin:     panel.togglePin(modelData.uid)
            onRemoveSymbol:  panel.removeSymbol(modelData.uid)
            onRefreshSymbol: panel.refreshSymbol(modelData.uid)
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  CUSTOM SCROLL INDICATOR
    // ═════════════════════════════════════════════════════════════════════════

    Rectangle {
        id: scrollIndicator
        visible:        panel.symbols.length > panel.popoutRows
        anchors.right:  parent.right
        anchors.top:    parent.top
        anchors.bottom: parent.bottom
        width:  constants.scrollBarWidth
        color:  "transparent"

        Rectangle {
            width:   parent.width
            radius:  constants.scrollBarRadius
            color:   Theme.outlineVariant
            opacity: symbolList.moving ? constants.scrollOpacityActive : constants.scrollOpacityIdle

            property real ratio: symbolList.height / symbolList.contentHeight
            height: Math.max(constants.scrollThumbMin, parent.height * ratio)
            y: symbolList.contentHeight > symbolList.height
               ? (symbolList.contentY / (symbolList.contentHeight - symbolList.height)) * (parent.height - height)
               : 0

            Behavior on opacity { NumberAnimation { duration: constants.scrollAnimDurationMs } }
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  EMPTY STATE
    // ═════════════════════════════════════════════════════════════════════════

    Column {
        visible:          panel.symbols.length === 0
        anchors.centerIn: parent
        spacing:          Theme.spacingM

        DankIcon {
            name:  "add_chart"
            size:  constants.emptyStateIconSize
            color: Theme.surfaceVariantText
            anchors.horizontalCenter: parent.horizontalCenter
        }

        StyledText {
            text:           "No symbols added"
            font.pixelSize: Theme.fontSizeMedium
            color:          Theme.surfaceVariantText
            anchors.horizontalCenter: parent.horizontalCenter
        }

        StyledText {
            text:           "Open Settings → Markets to add symbols"
            font.pixelSize: Theme.fontSizeSmall
            color:          Theme.surfaceVariantText
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}
