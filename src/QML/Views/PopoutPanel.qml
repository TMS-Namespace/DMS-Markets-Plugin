// PopoutPanel.qml - Popout content area for the Markets plugin
//
// Contains the symbol list, header hover buttons (refresh all, settings and close),
// custom scroll indicator, and empty-state placeholder.
// Moved from QML/ to QML/Views/ so all view-layer components live together.

pragma ComponentBehavior: Bound
import QtQuick
import "../../JS/Contracts/FetchType.js" as FetchType
import "../../JS/Helpers/SymbolErrorMap.js" as SymbolErrors
import "../Helpers"
import qs.Common
import qs.DCommon.Widgets

Item {
    id: panel

    // ── Computed ─────────────────────────────────────────────────────────────
    property bool _anyLoading: {
        for (let key in pendingFetches)
            if (pendingFetches[key] > 0)
                return true;
        return false;
    }
    property color downColor
    readonly property string errorSummary: SymbolErrors.summary(symbolErrors, symbols)
    property var graphData: ({})
    readonly property bool hasErrors: errorSummary !== ""
    readonly property bool headerHovered: headerHoverArea.containsMouse || refreshAllButton.hovered || settingsButton.hovered || closePopoutButton.hovered

    // ── Header geometry (for positioning overlay buttons) ─────────────────────
    property real headerOffset: 0    // headerHeight + detailsHeight

    property var lastFetchTimes: ({})
    property var pendingFetches: ({})
    property int popoutRows: constants.defaultPopoutRows
    property var priceData: ({})
    property bool showChartRange: true
    property bool showPriceChange: true
    property bool showProviderName: true
    property bool showRefreshedSince: true
    property bool showTicker: true
    property var symbolErrors: ({})   // { uid: { price, graph } }

    // ── Data inputs (bound from Widget.qml) ──────────────────────────────────
    property var symbols: []

    // ── Display settings (Widget.qml always binds all of these) ──────────────
    property color upColor
    readonly property int visibleRows: Math.min(symbols.length, Math.max(1, popoutRows))

    signal closePopout
    signal openSettings
    signal refreshAll
    signal refreshSymbol(string uid)
    signal removeSymbol(string uid)

    // ── Signals (forwarded to Widget.qml) ────────────────────────────────────
    signal togglePin(string uid)

    // Match the cards exactly; the host adds the header and outer padding separately.
    implicitHeight: symbols.length > 0 ? visibleRows * constants.symbolRowHeight + (visibleRows - 1) * symbolList.spacing : emptyState.implicitHeight

    Constants {
        id: constants
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  HEADER HOVER BUTTONS (positioned over header via negative y offset)
    // ═════════════════════════════════════════════════════════════════════════

    MouseArea {
        id: headerHoverArea

        acceptedButtons: Qt.NoButton
        height: panel.headerOffset
        hoverEnabled: true
        width: parent.width
        x: 0
        y: -panel.headerOffset
        z: constants.headerHoverZ
    }
    Row {
        id: headerButtons

        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingS
        spacing: constants.headerButtonSpacing
        visible: panel.headerHovered || panel._anyLoading || panel.hasErrors
        y: -panel.headerOffset + Theme.spacingS
        z: constants.headerButtonZ

        IconButton {
            id: refreshAllButton

            buttonRadius: constants.headerButtonRadius
            buttonSize: constants.headerButtonSize
            hoverTint: Theme.primary
            iconColor: panel._anyLoading ? Theme.primary : Theme.surfaceText
            iconName: "refresh"
            iconSize: constants.headerIconSize
            pressable: !panel._anyLoading
            spinning: panel._anyLoading
            tooltipText: panel.hasErrors ? "Unable to refresh:\n" + panel.errorSummary : "Refresh all symbols"
            warning: panel.hasErrors

            onClicked: panel.refreshAll()
        }
        IconButton {
            id: settingsButton

            buttonRadius: constants.headerButtonRadius
            buttonSize: constants.headerButtonSize
            enabled: panel.headerHovered || panel._anyLoading
            hoverTint: Theme.primary
            iconColor: Theme.surfaceText
            iconName: "settings"
            iconSize: constants.headerIconSize
            opacity: enabled ? 1 : 0
            tooltipText: "Open Markets settings"

            onClicked: panel.openSettings()
        }
        IconButton {
            id: closePopoutButton

            buttonRadius: constants.headerButtonRadius
            buttonSize: constants.headerButtonSize
            enabled: panel.headerHovered || panel._anyLoading
            hoverTint: Theme.error
            iconColor: closePopoutButton.hovered ? Theme.error : Theme.surfaceText
            iconName: "close"
            iconSize: constants.headerIconSize
            opacity: enabled ? 1 : 0

            onClicked: panel.closePopout()
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  SYMBOL LIST
    // ═════════════════════════════════════════════════════════════════════════

    ListView {
        id: symbolList

        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        model: panel.symbols
        spacing: Theme.spacingS

        delegate: SymbolRow {
            required property var modelData

            chartData: panel.graphData[modelData.uid] || []
            downColor: panel.downColor
            isLoading: (panel.pendingFetches[modelData.uid] || 0) > 0
            lastFetchTime: panel.lastFetchTimes[FetchType.timeKey(modelData.uid, FetchType.Values.PRICE)] || 0
            priceInfo: panel.priceData[modelData.uid] || ({})
            showChartRange: panel.showChartRange
            showPriceChange: panel.showPriceChange
            showProviderName: panel.showProviderName
            showRefreshedSince: panel.showRefreshedSince
            showTicker: panel.showTicker
            symbolData: modelData
            symbolError: panel.symbolErrors[modelData.uid] || ({})
            upColor: panel.upColor
            width: symbolList.width

            onRefreshSymbol: panel.refreshSymbol(modelData.uid)
            onRemoveSymbol: panel.removeSymbol(modelData.uid)
            onTogglePin: panel.togglePin(modelData.uid)
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  CUSTOM SCROLL INDICATOR
    // ═════════════════════════════════════════════════════════════════════════

    Rectangle {
        id: scrollIndicator

        anchors.bottom: parent.bottom
        anchors.top: parent.top
        color: "transparent"
        visible: panel.symbols.length > panel.popoutRows
        width: constants.scrollBarWidth
        // Use the outer gutter so scrolling never narrows only the right side of the cards.
        x: panel.width + (Theme.spacingS - width) / 2

        Rectangle {
            property real ratio: symbolList.height / symbolList.contentHeight

            color: Theme.outlineVariant
            height: Math.max(constants.scrollThumbMin, parent.height * ratio)
            opacity: symbolList.moving ? constants.scrollOpacityActive : constants.scrollOpacityIdle
            radius: constants.scrollBarRadius
            width: parent.width
            y: symbolList.contentHeight > symbolList.height ? (symbolList.contentY / (symbolList.contentHeight - symbolList.height)) * (parent.height - height) : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: constants.scrollAnimDurationMs
                }
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  EMPTY STATE
    // ═════════════════════════════════════════════════════════════════════════

    Column {
        id: emptyState

        anchors.centerIn: parent
        spacing: Theme.spacingM
        visible: panel.symbols.length === 0
        width: parent.width

        DIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.surfaceVariantText
            name: "add_chart"
            size: constants.emptyStateIconSize
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeMedium
            horizontalAlignment: Text.AlignHCenter
            text: "Add symbols to start…"
            width: parent.width
            wrapMode: Text.WordWrap
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignHCenter
            text: "Open Markets settings → Per Symbol Settings to add symbols."
            width: parent.width
            wrapMode: Text.WordWrap
        }
    }
}
