// Widget.qml - DMS bar and popup composition. Market state and lifecycle belong to WidgetController.
pragma ComponentBehavior: Bound
import QtQuick
import "./Helpers"
import "./Services"
import "./Views"
import qs.Common
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
            devMode: constants.devMode
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
    popoutHeight: {
        let visible = Math.min(popoutRows, symbols.length);
        let totalRows = visible > 0 ? visible : popoutRows;
        return Math.max(constants.popoutMinHeight, totalRows * constants.rowHeight + (totalRows - 1) * Theme.spacingS + constants.popoutPadding);
    }
    popoutWidth: constants.popoutWidth

    // ═══════════════════════════════════════════════════════════════════════
    //  BAR PILLS
    // ═══════════════════════════════════════════════════════════════════════

    horizontalBarPill: Component {
        HorizontalBarPill {
            displayText: root.controller.barDisplayText
            iconSize: root.iconSize
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  POPOUT
    // ═══════════════════════════════════════════════════════════════════════

    popoutContent: Component {
        PopoutComponent {
            id: popout

            detailsText: root.symbols.length > 0 ? root.symbols.length + " symbol" + (root.symbols.length !== 1 ? "s" : "") + " tracked" : "Add symbols in Settings"
            headerText: constants.barDefaultLabel
            showCloseButton: false

            PopoutPanel {
                downColor: root.downColor
                graphData: root.graphData
                headerOffset: popout.headerHeight + popout.detailsHeight
                implicitHeight: root.popoutHeight - popout.headerHeight - popout.detailsHeight - Theme.spacingXL
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
    verticalBarPill: Component {
        VerticalBarPill {
            iconSize: root.iconSize
            shortLabel: root.controller.pinnedSymbols.length > 0 ? root.controller.pinnedSymbols[0].name : "MKT"
        }
    }

    Component.onCompleted: {
        root.controller.initialize();
        setVisibilityOverride(canFetchAnySymbol);
    }
    onCanFetchAnySymbolChanged: setVisibilityOverride(canFetchAnySymbol)

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
