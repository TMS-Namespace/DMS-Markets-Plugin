// PopoutPanel.qml — Popout content area for the Markets plugin
//
// Contains the symbol list, header hover buttons (refresh all + close),
// custom scroll indicator, and empty-state placeholder.
// Moved from QML/ to QML/Views/ so all view-layer components live together.

import QtQuick
import qs.Common
import qs.Widgets
import "../Helpers"

Item {
    id: panel

    Constants { id: c }

    // ── Data inputs (bound from Widget.qml) ──────────────────────────────────
    property var  symbols:        []
    property var  priceData:      ({})
    property var  graphData:      ({})
    property var  pendingFetches: ({})
    property var  lastFetchTimes: ({})

    // ── Display settings (Widget.qml always binds all of these) ──────────────
    property color upColor
    property color downColor
    property bool  showTicker:         true
    property bool  showPriceRange:     true
    property bool  showChartRange:     true
    property bool  showRefreshedSince: true
    property int   popoutRows:         c.defaultPopoutRows

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
        anchors.right:       parent.right
        anchors.rightMargin: Theme.spacingS
        y:       -panel.headerOffset + Theme.spacingS
        spacing: c.headerButtonSpacing
        visible: headerHoverArea.containsMouse
                 || refreshAllArea.containsMouse
                 || closePopoutArea.containsMouse
                 || panel._anyLoading
        z: 101

        // ── Refresh-all button ───────────────────────────────────────────
        Rectangle {
            width: c.headerButtonSize; height: c.headerButtonSize; radius: c.headerButtonRadius
            color: refreshAllArea.containsMouse
                   ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, c.buttonHoverAlpha)
                   : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, c.actionButtonBgOpacity)

            MouseArea {
                id: refreshAllArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape:  Qt.PointingHandCursor
                enabled:      !panel._anyLoading
                onClicked:    panel.refreshAll()
            }

            DankIcon {
                id: headerRefreshIcon
                anchors.centerIn: parent
                name:  "refresh"
                size:  c.headerIconSize
                color: panel._anyLoading ? Theme.primary : Theme.surfaceText

                RotationAnimation on rotation {
                    running:  panel._anyLoading
                    from: 0; to: 360
                    duration: c.headerAnimDurationMs
                    loops:    Animation.Infinite
                }

                Connections {
                    target: panel
                    function on_AnyLoadingChanged() {
                        if (!panel._anyLoading) headerRefreshIcon.rotation = 0
                    }
                }
            }
        }

        // ── Close popup button ───────────────────────────────────────────
        Rectangle {
            width: c.headerButtonSize; height: c.headerButtonSize; radius: c.headerButtonRadius
            color: closePopoutArea.containsMouse
                   ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, c.buttonHoverAlpha)
                   : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, c.actionButtonBgOpacity)

            MouseArea {
                id: closePopoutArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape:  Qt.PointingHandCursor
                onClicked:    panel.closePopout()
            }

            DankIcon {
                anchors.centerIn: parent
                name:  "close"
                size:  c.headerIconSize
                color: closePopoutArea.containsMouse ? Theme.error : Theme.surfaceText
            }
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
            priceInfo:     panel.priceData[modelData.id]  || ({})
            chartData:     panel.graphData[modelData.id]  || []
            isLoading:     (panel.pendingFetches[modelData.id] || 0) > 0
            lastFetchTime: panel.lastFetchTimes[modelData.id + "_price"] || 0
            upColor:       panel.upColor
            downColor:     panel.downColor
            showTicker:          panel.showTicker
            showPriceRange:      panel.showPriceRange
            showChartRange:      panel.showChartRange
            showRefreshedSince:  panel.showRefreshedSince

            onTogglePin:     panel.togglePin(modelData.id)
            onRemoveSymbol:  panel.removeSymbol(modelData.id)
            onRefreshSymbol: panel.refreshSymbol(modelData.id)
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
        width:  c.scrollBarWidth
        color:  "transparent"

        Rectangle {
            width:   parent.width
            radius:  c.scrollBarRadius
            color:   Theme.outlineVariant
            opacity: symbolList.moving ? c.scrollOpacityActive : c.scrollOpacityIdle

            property real ratio: symbolList.height / symbolList.contentHeight
            height: Math.max(c.scrollThumbMin, parent.height * ratio)
            y: symbolList.contentHeight > symbolList.height
               ? (symbolList.contentY / (symbolList.contentHeight - symbolList.height)) * (parent.height - height)
               : 0

            Behavior on opacity { NumberAnimation { duration: c.scrollAnimDurationMs } }
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
            size:  c.emptyStateIconSize
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
