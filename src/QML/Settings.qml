// Settings.qml - DMS settings entry point. Composes views and connects them to a per-page controller.
pragma ComponentBehavior: Bound
import QtQuick
import "./Helpers"
import "./Services"
import "./Views"
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.Widgets

PluginSettings {
    id: root

    readonly property bool _errorHandlerReady: _configureErrorHandler()
    readonly property alias controller: settingsController
    readonly property int popoutRowsValue: displaySettings.popoutRowsValue

    // Connect the shared error handler to the host's notifications before reading saved settings.
    function _configureErrorHandler() {
        Logger.configure({
            devMode: constants.devMode
        });
        ErrorHandler.configure({
            notify: function (message, details, category) {
                ToastService.showError("Markets: " + message, details, "", category);
            }
        });
        return true;
    }

    // DMS setting controls locate these storage methods through the visual parent chain.
    function loadValue(key, defaultValue) {
        return root.controller.loadValue(key, defaultValue);
    }

    // Return the storage outcome so host controls can distinguish a failed save.
    function saveValue(key, value) {
        return root.controller.saveValue(key, value);
    }

    pluginId: "markets"

    Constants {
        id: constants
    }
    SettingsController {
        id: settingsController

        formState: symbolEditor.formState
        pluginId: root.pluginId
        pluginService: root.pluginService

        onDraftRequested: draft => symbolEditor.applyDraft(draft)
        onErrorRequested: message => ToastService.showError("Markets", message)
        onInfoRequested: message => ToastService.showInfo("Markets", message)
        onSelectionRequested: selection => symbolEditor.applySelection(selection)
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  HEADER
    // ═══════════════════════════════════════════════════════════════════════

    StyledText {
        color: Theme.surfaceText
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        text: "Markets Plugin"
        width: parent.width
    }
    StyledText {
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall
        text: constants.pluginSubtitle
        width: parent.width
        wrapMode: Text.WordWrap
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  CHART COLORS
    // ═══════════════════════════════════════════════════════════════════════

    Column {
        id: settingsBody

        spacing: Theme.spacingS
        width: parent.width

        DisplaySettings {
            id: displaySettings

            width: parent.width
        }
        Rectangle {
            color: Theme.outlineVariant
            height: 1
            width: parent.width
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  SYMBOL LOOKUP + ADD/EDIT
        // ═══════════════════════════════════════════════════════════════════════

        SymbolEditor {
            id: symbolEditor

            changeResolutionOptions: root.controller.changeResolutionOptions
            chartRangeAvailable: root.controller.chartRangeAvailable
            chartRangeOptions: root.controller.chartRangeOptions
            chartRangeStatus: root.controller.chartRangeStatus
            chartResolutionOptions: root.controller.chartResolutionOptions
            editIndex: root.controller.editIndex
            formUnlocked: root.controller.formUnlocked
            nameText: root.controller.nameText
            nameValidation: root.controller.nameValidation
            priceResolutionOptions: root.controller.priceResolutionOptions
            providerLoadErrors: root.controller.providerLoadErrors
            selectedProvider: root.controller.selectedProvider
            selectedProviderDisabled: root.controller.selectedProviderDisabled
            tickerText: root.controller.tickerText
            tickerValidation: root.controller.tickerValidation
            width: parent.width

            onCancelRequested: root.controller.cancelEdit()
            onChartResolutionEdited: Qt.callLater(root.controller.syncSelections)
            onDraftFieldEdited: (field, value) => root.controller.saveDraftField(field, value)
            onFlagsEdited: root.controller.saveEditedSymbolFlags()
            onSaveRequested: root.controller.addOrUpdateSymbol()
        }
        Rectangle {
            color: Theme.outlineVariant
            height: 1
            width: parent.width
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  CONFIGURED SYMBOLS LIST
        // ═══════════════════════════════════════════════════════════════════════

        StyledText {
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
            text: "Configured Symbols"
            topPadding: Theme.spacingS
            width: parent.width
        }
        Repeater {
            model: root.controller.symbolsList

            delegate: ConfiguredSymbol {
                required property int index
                required property var modelData

                isEditing: root.controller.editIndex === index
                isFirst: index === 0
                isLast: index === root.controller.symbolsList.length - 1
                symbolData: modelData
                width: root.width

                onClicked: root.controller.editSymbol(index)
                onMovedDown: root.controller.moveSymbol(index, 1)
                onMovedUp: root.controller.moveSymbol(index, -1)
                onRemoved: root.controller.removeSymbolAt(index)
            }
        }
    } // settingsBody
}
