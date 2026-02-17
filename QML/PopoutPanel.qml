// PopoutPanel.qml — Popout content area for the Markets plugin
//
// Contains the symbol list, header hover buttons (refresh all + close),
// custom scroll indicator, and empty-state placeholder.
// Extracted from Widget.qml to reduce file size.

import QtQuick
import qs.Common
import qs.Widgets
import "../JS/ProviderInterface.js" as Providers
import "../JS/StooqProvider.js" as StooqProvider

Item {
    id: panel

    // ── Data inputs (bound from Widget.qml) ──────────────────────────────────
    property var  symbols:        []
    property var  priceData:      ({})
    property var  graphData:      ({})
    property var  pendingFetches: ({})
    property var  lastFetchTimes: ({})

    // ── Display settings ─────────────────────────────────────────────────────
    property color upColor:           "#4CAF50"
    property color downColor:         "#F44336"
    property bool  showTicker:        true
    property bool  showPriceRange:    true
    property bool  showChartRange:    true
    property bool  showRefreshedSince: true
    property int   popoutRows:        5

    // ── Header geometry (for positioning overlay buttons) ─────────────────────
    property real  headerOffset: 0    // headerHeight + detailsHeight

    // ── Signals (forwarded to Widget.qml) ────────────────────────────────────
    signal togglePin(string symbolId)
    signal removeSymbol(string symbolId)
    signal refreshSymbol(string symbolId)
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
        z: 100
    }

    Row {
        id: headerButtons
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingS
        y: -panel.headerOffset + Math.round((panel.headerOffset - 28) / 2)
        spacing: 6
        visible: headerHoverArea.containsMouse
                 || refreshAllArea.containsMouse
                 || closePopoutArea.containsMouse
                 || panel._anyLoading
        z: 101

        // ── Refresh-all button ───────────────────────────────────────
        Rectangle {
            width: 28; height: 28; radius: 14
            color: refreshAllArea.containsMouse
                   ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                   : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.85)

            MouseArea {
                id: refreshAllArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: !panel._anyLoading
                onClicked: panel.refreshAll()
            }

            DankIcon {
                id: headerRefreshIcon
                anchors.centerIn: parent
                name: "refresh"
                size: 18
                color: panel._anyLoading ? Theme.primary : Theme.surfaceText

                RotationAnimation on rotation {
                    running: panel._anyLoading
                    from: 0; to: 360
                    duration: 800
                    loops: Animation.Infinite
                }

                Connections {
                    target: panel
                    function on_AnyLoadingChanged() {
                        if (!panel._anyLoading)
                            headerRefreshIcon.rotation = 0
                    }
                }
            }
        }

        // ── Close popup button ───────────────────────────────────────
        Rectangle {
            width: 28; height: 28; radius: 14
            color: closePopoutArea.containsMouse
                   ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.15)
                   : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.85)

            MouseArea {
                id: closePopoutArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.closePopout()
            }

            DankIcon {
                anchors.centerIn: parent
                name: "close"
                size: 18
                color: closePopoutArea.containsMouse ? Theme.error : Theme.surfaceText
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  SYMBOL LIST
    // ═════════════════════════════════════════════════════════════════════════

    ListView {
        id: symbolList
        anchors.left: parent.left
        anchors.right: scrollIndicator.visible ? scrollIndicator.left : parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: Theme.spacingS
        clip: true
        model: panel.symbols
        boundsBehavior: Flickable.StopAtBounds

        delegate: SymbolRow {
            width: symbolList.width
            symbolData: modelData
            priceInfo:  panel.priceData[modelData.id]  || ({})
            chartData:  panel.graphData[modelData.id]  || []
            isLoading:  (panel.pendingFetches[modelData.id] || 0) > 0
            lastFetchTime: panel.lastFetchTimes[modelData.id + "_price"] || 0
            upColor:    panel.upColor
            downColor:  panel.downColor
            showTicker:         panel.showTicker
            showPriceRange:     panel.showPriceRange
            showChartRange:     panel.showChartRange
            showRefreshedSince: panel.showRefreshedSince

            onTogglePin:    panel.togglePin(modelData.id)
            onRemoveSymbol: panel.removeSymbol(modelData.id)
            onRefreshSymbol: panel.refreshSymbol(modelData.id)
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  CUSTOM SCROLL INDICATOR
    // ═════════════════════════════════════════════════════════════════════════

    Rectangle {
        id: scrollIndicator
        visible: panel.symbols.length > panel.popoutRows
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 4
        color: "transparent"

        Rectangle {
            width: parent.width
            radius: 2
            color: Theme.outlineVariant
            opacity: symbolList.moving ? 0.8 : 0.4

            property real ratio: symbolList.height / symbolList.contentHeight
            height: Math.max(20, parent.height * ratio)
            y: symbolList.contentHeight > symbolList.height
               ? (symbolList.contentY / (symbolList.contentHeight - symbolList.height)) * (parent.height - height)
               : 0

            Behavior on opacity { NumberAnimation { duration: 200 } }
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  EMPTY STATE
    // ═════════════════════════════════════════════════════════════════════════

    Column {
        visible: panel.symbols.length === 0
        anchors.centerIn: parent
        spacing: Theme.spacingM

        DankIcon {
            name: "add_chart"
            size: 48
            color: Theme.surfaceVariantText
            anchors.horizontalCenter: parent.horizontalCenter
        }

        StyledText {
            text: "No symbols added"
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceVariantText
            anchors.horizontalCenter: parent.horizontalCenter
        }

        StyledText {
            text: "Open Settings → Markets to add symbols"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}
