// Widget.qml - DMS bar and popup composition. Market state and lifecycle belong to WidgetController.
pragma ComponentBehavior: Bound
import QtQuick
import "./Helpers"
import "./Services"
import "./Views"
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins
import qs.Services

PluginComponent {
    id: root

    readonly property bool _errorHandlerReady: _configureErrorHandler()
    property alias _pendingFetches: widgetController._pendingFetches
    property alias cacheDirectory: widgetController.cacheDirectory
    property alias canFetchAnySymbol: widgetController.canFetchAnySymbol
    readonly property alias controller: widgetController
    property alias downColor: widgetController.downColor
    property alias graphData: widgetController.graphData
    property alias lastFetchTimes: widgetController.lastFetchTimes
    property alias marketCache: widgetController.marketCache
    property alias popoutRows: widgetController.popoutRows
    property alias priceData: widgetController.priceData
    property alias providerCredentials: widgetController.providerCredentials
    property alias refreshedTimes: widgetController.refreshedTimes
    readonly property bool showBarWidget: symbols.length === 0 || canFetchAnySymbol
    property alias showChartRange: widgetController.showChartRange
    property alias showPriceChange: widgetController.showPriceChange
    property alias showProviderName: widgetController.showProviderName
    property alias showRefreshedSince: widgetController.showRefreshedSince
    property alias showTicker: widgetController.showTicker
    property alias symbolErrors: widgetController.symbolErrors
    property alias symbols: widgetController.symbols
    property alias upColor: widgetController.upColor

    // Connect error reporting to DMS before the controller starts reading saved data.
    function _configureErrorHandler() {
        Logger.configure({
            isDevMode: constants.isDevMode
        });
        ErrorHandler.configure({
            // DMS's own toast: short message as the title, technical details expandable.
            notify: function (message, details, category) {
                ToastService.showError("Markets: " + message, details, "", category);
            }
        });
        return true;
    }

    layerNamespacePlugin: "markets"
    popoutWidth: constants.popoutWidth

    // ═══════════════════════════════════════════════════════════════════════
    //  BAR PILLS
    // ═══════════════════════════════════════════════════════════════════════

    horizontalBarPill: Component {
        HorizontalBarPill {
            displayText: root.controller.barDisplayText
            iconSize: root.iconSize
            textSize: root.textSize
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  POPOUT
    // ═══════════════════════════════════════════════════════════════════════

    popoutContent: Component {
        Item {
            id: popupContent

            property alias closePopout: popout.closePopout
            readonly property real paddingAdjustment: Math.max(0, PopoutMetrics.contentPadding - Theme.spacingS)
            property alias parentPopout: popout.parentPopout

            // Dux adds its own outer padding. Expand the inner column into it on every side.
            implicitHeight: Math.max(0, popout.implicitHeight - 2 * paddingAdjustment)

            PopoutComponent {
                id: popout

                headerText: constants.barDefaultLabel
                width: popupContent.width + 2 * popupContent.paddingAdjustment
                x: -popupContent.paddingAdjustment
                y: -popupContent.paddingAdjustment

                // Own the summary label so its theme size can be set without changing Dux's internal controls.
                StyledText {
                    id: popoutSummary

                    bottomPadding: Theme.spacingS
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    leftPadding: Theme.spacingS
                    objectName: "marketsSummary"
                    text: root.controller.popoutDetailsText
                    width: parent.width
                    wrapMode: Text.WordWrap
                }
                PopoutPanel {
                    downColor: root.downColor
                    graphData: root.graphData
                    headerOffset: popout.headerHeight + popoutSummary.height
                    lastFetchTimes: root.refreshedTimes
                    pendingFetches: root._pendingFetches
                    popoutRows: root.popoutRows
                    priceData: root.priceData
                    showChartRange: root.showChartRange
                    showPriceChange: root.showPriceChange
                    showProviderName: root.showProviderName
                    showRefreshedSince: root.showRefreshedSince
                    showTicker: root.showTicker
                    symbolErrors: root.symbolErrors
                    symbols: root.symbols
                    upColor: root.upColor
                    width: parent.width

                    onClosePopout: root.closePopout()
                    onOpenSettings: {
                        root.closePopout();
                        PopoutService.openSettingsWithTab(SettingsTabs.pluginPrefix + root.pluginId);
                    }
                    onRefreshAll: root.controller.refreshAll()
                    onRefreshSymbol: function (uid) {
                        root.controller.refreshSymbol(uid);
                    }
                    onRemoveSymbol: function (uid) {
                        root.controller.removeSymbol(uid);
                    }
                    onTogglePin: function (uid) {
                        root.controller.togglePin(uid);
                    }
                }
            }
        }
    }
    verticalBarPill: Component {
        VerticalBarPill {
            iconSize: root.iconSize
            shortLabel: root.controller.pinnedSymbols.length > 0 ? root.controller.pinnedSymbols[0].name : "MKT"
            textSize: root.textSize
        }
    }

    Component.onCompleted: {
        root.controller.initialize();
        setVisibilityOverride(showBarWidget);
    }
    onShowBarWidgetChanged: setVisibilityOverride(showBarWidget)

    Constants {
        id: constants
    }
    WidgetController {
        id: widgetController

        pluginData: root.pluginData
        pluginId: root.pluginId
        pluginService: root.pluginService
    }
}
