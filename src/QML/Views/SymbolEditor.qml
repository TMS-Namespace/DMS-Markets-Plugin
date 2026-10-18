// SymbolEditor.qml - Add/edit symbol controls. The page supplies validation and persists edits through signals.
pragma ComponentBehavior: Bound
import QtQuick
import "../../JS/Helpers/Constants.js" as JsConstants
import "../Helpers"
import "../Services"
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

Column {
    id: root

    property alias changeResolution: changeResolutionSelect.value
    required property var changeResolutionOptions
    property alias chartRange: chartRangeSelect.value
    required property bool chartRangeAvailable
    required property var chartRangeOptions
    required property var chartRangeStatus
    property alias chartResolution: chartResolutionSelect.value
    required property var chartResolutionOptions
    property alias displayName: nameInput.value
    required property int editIndex
    readonly property var formState: ({
            ticker: ticker,
            name: displayName,
            provider: providerId,
            priceResolution: priceResolution,
            changeResolution: changeResolution,
            chartResolution: chartResolution,
            chartRange: chartRange,
            showChange: showChange,
            invert: invert
        })
    required property bool formUnlocked
    property alias invert: invertToggle.value
    required property string nameText
    required property var nameValidation
    property alias priceResolution: priceResolutionSelect.value
    required property var priceResolutionOptions
    property alias providerId: providerSelect.value
    required property var providerLoadErrors
    required property var selectedProvider
    required property bool selectedProviderDisabled
    property alias showChange: showChangeToggle.value
    property alias ticker: tickerInput.value
    required property string tickerText
    required property var tickerValidation

    signal cancelRequested
    signal chartResolutionEdited

    // Request page actions without letting this view access storage.
    signal draftFieldEdited(string field, string value)
    signal flagsEdited
    signal saveRequested

    // Display an already validated draft without making storage or provider decisions.
    function applyDraft(draft) {
        ticker = draft.ticker;
        displayName = draft.name;
        providerId = draft.provider;
        applySelection(draft);
        showChange = draft.showChange;
        invert = draft.invert;
    }

    // Update only fields affected by provider selection rules.
    function applySelection(selection) {
        if (priceResolution !== selection.priceResolution)
            priceResolution = selection.priceResolution;
        if (changeResolution !== selection.changeResolution)
            changeResolution = selection.changeResolution;
        if (chartResolution !== selection.chartResolution)
            chartResolution = selection.chartResolution;
        if (chartRange !== selection.chartRange)
            chartRange = selection.chartRange;
    }

    spacing: Theme.spacingS

    Constants {
        id: constants
    }
    StyledText {
        color: Theme.surfaceText
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        text: root.editIndex >= 0 ? "Edit Symbol" : "Add New Symbol"
        topPadding: Theme.spacingM
        width: parent.width
    }
    SelectionRow {
        id: providerSelect

        defaultValue: ProvidersManager.defaultId
        description: "Source for price data"
        label: "Data Provider"
        options: ProvidersManager.options()
        settingKey: JsConstants.DRAFT_KEYS.provider
        visible: ProvidersManager.types.length > 1
    }
    Column {
        id: providerInfo

        spacing: Theme.spacingXS
        visible: root.selectedProvider.description !== undefined && (root.selectedProvider.description || "") !== ""
        width: parent.width

        StyledText {
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
            text: root.selectedProvider.description || ""
            width: parent.width
            wrapMode: Text.WordWrap
        }
    }

    // Providers that could not be loaded; the others keep working.
    Repeater {
        model: root.providerLoadErrors

        delegate: StyledText {
            required property var modelData

            color: Theme.error
            font.pixelSize: Theme.fontSizeSmall
            text: modelData.userMessage
            width: parent.width
            wrapMode: Text.WordWrap
        }
    }
    StyledText {
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall
        text: root.selectedProvider.disabledMessage
        visible: root.selectedProviderDisabled
        width: parent.width
        wrapMode: Text.WordWrap
    }
    Column {
        id: tickerInput

        property alias value: tickerField.text

        height: visible ? implicitHeight : 0
        spacing: Theme.spacingS
        visible: !root.selectedProviderDisabled
        width: parent.width

        StyledText {
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            text: "Symbol Ticker"
        }
        StyledText {
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
            text: root.selectedProvider.symbolHelpText
            width: parent.width
            wrapMode: Text.WordWrap
        }

        // Format and length come from the provider's declared symbol rules.
        StyledText {
            color: Theme.error
            font.pixelSize: Theme.fontSizeSmall
            text: root.tickerValidation.message
            visible: root.tickerText !== "" && !root.tickerValidation.valid
            width: parent.width
            wrapMode: Text.WordWrap
        }
        Row {
            height: constants.compactRowHeight
            spacing: Theme.spacingS
            width: parent.width

            DankTextField {
                id: tickerField

                placeholderText: root.selectedProvider.symbolPlaceholder
                width: parent.width - providerSearchButton.width - Theme.spacingS

                onEditingFinished: root.draftFieldEdited("ticker", text.trim())
            }
            Rectangle {
                id: providerSearchButton

                border.color: Theme.primary
                border.width: 1
                color: providerSearchMouseArea.containsMouse ? Theme.primary : Theme.surfaceContainerHighest
                height: parent.height
                radius: Theme.cornerRadius
                width: Math.min(constants.symbolSearchButtonWidth, Math.round(parent.width * 0.48))

                Row {
                    spacing: Theme.spacingXS

                    anchors {
                        left: parent.left
                        leftMargin: constants.symbolSearchButtonPadding
                        right: parent.right
                        rightMargin: constants.symbolSearchButtonPadding
                        verticalCenter: parent.verticalCenter
                    }
                    DankIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        color: providerSearchMouseArea.containsMouse ? Theme.surfaceContainer : Theme.primary
                        name: "open_in_new"
                        size: Theme.fontSizeMedium
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        color: providerSearchMouseArea.containsMouse ? Theme.surfaceContainer : Theme.primary
                        elide: Text.ElideRight
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        text: "Open symbols search..."
                        width: parent.width - x
                    }
                }
                MouseArea {
                    id: providerSearchMouseArea

                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true

                    onClicked: {
                        let provider = root.selectedProvider;
                        if (provider.symbolSearchUrl)
                            Qt.openUrlExternally(provider.symbolSearchUrl);
                    }
                }
            }
        }
    }
    Column {
        id: nameInput

        property alias value: nameField.text

        height: visible ? implicitHeight : 0
        spacing: Theme.spacingS
        visible: !root.selectedProviderDisabled
        width: parent.width

        StyledText {
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            text: "Display Name"
        }
        StyledText {
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
            text: "Short label shown for the symbol (max " + JsConstants.DISPLAY_NAME_MAX_LENGTH + " char.)"
            width: parent.width
            wrapMode: Text.WordWrap
        }
        DankTextField {
            id: nameField

            maximumLength: JsConstants.DISPLAY_NAME_MAX_LENGTH
            placeholderText: "Gold"
            width: parent.width

            onEditingFinished: root.draftFieldEdited("name", text.trim())
        }
        StyledText {
            color: Theme.error
            font.pixelSize: Theme.fontSizeSmall
            text: root.nameValidation.message
            visible: root.nameText !== "" && !root.nameValidation.valid
            width: parent.width
            wrapMode: Text.WordWrap
        }
    }
    SelectionRow {
        id: priceResolutionSelect

        defaultValue: JsConstants.DEFAULT_PRICE_RESOLUTION
        description: "Candle size for the live price, also sets how often it is refreshed"
        enabled: root.formUnlocked
        label: "Price Resolution"
        opacity: enabled ? 1.0 : 0.5
        options: root.priceResolutionOptions
        settingKey: JsConstants.DRAFT_KEYS.priceResolution
        visible: !root.selectedProviderDisabled
    }
    SelectionRow {
        id: changeResolutionSelect

        defaultValue: JsConstants.DEFAULT_CHANGE_RESOLUTION
        description: "The price change is calculated against the close of the previous period of this size"
        enabled: root.formUnlocked
        label: "Price Change Resolution"
        opacity: enabled ? 1.0 : 0.5
        options: root.changeResolutionOptions
        settingKey: JsConstants.DRAFT_KEYS.changeResolution
        visible: !root.selectedProviderDisabled
    }
    SelectionRow {
        id: chartResolutionSelect

        defaultValue: JsConstants.DEFAULT_CHART_RESOLUTION
        description: "Candle size of the charts"
        enabled: root.formUnlocked
        label: "Chart Resolution"
        opacity: enabled ? 1.0 : 0.5
        options: root.chartResolutionOptions
        settingKey: JsConstants.DRAFT_KEYS.chartResolution
        visible: !root.selectedProviderDisabled

        // Keep the chart range valid for the newly chosen resolution.
        onValueChanged: root.chartResolutionEdited()
    }
    SelectionRow {
        id: chartRangeSelect

        defaultValue: JsConstants.DEFAULT_CHART_SPAN
        description: root.chartRangeAvailable ? "How much historical data to show in the charts" : "Choose a chart resolution first"
        enabled: root.formUnlocked && root.chartRangeAvailable
        label: "Chart Range"
        opacity: enabled ? 1.0 : 0.5
        options: root.chartRangeOptions
        settingKey: JsConstants.DRAFT_KEYS.chartRange
        visible: !root.selectedProviderDisabled
    }

    // Non-blocking note: the chosen resolution gives very few / very many candles.
    // (Combinations that would be far off are not offered at all.)
    StyledText {
        color: Theme.warning
        font.pixelSize: Theme.fontSizeSmall
        text: root.chartRangeStatus.message
        visible: !root.selectedProviderDisabled && root.chartRangeAvailable && root.chartRangeStatus.level === "warn"
        width: parent.width
        wrapMode: Text.WordWrap
    }
    ToggleSetting {
        id: showChangeToggle

        defaultValue: false
        description: "Display price change in the bar when this symbol is pinned"
        enabled: root.formUnlocked
        label: "Show Price Change When Pinned"
        opacity: enabled ? 1.0 : 0.5
        settingKey: JsConstants.DRAFT_KEYS.showChange
        visible: !root.selectedProviderDisabled

        onValueChanged: {
            if (!isInitialized)
                return;
            root.flagsEdited();
        }
    }
    ToggleSetting {
        id: invertToggle

        defaultValue: false
        description: "Show the reciprocal of the price and chart (e.g., USD/EUR instead of EUR/USD)"
        enabled: root.formUnlocked
        label: "Invert Prices (1/x)"
        opacity: enabled ? 1.0 : 0.5
        settingKey: JsConstants.DRAFT_KEYS.invert
        visible: !root.selectedProviderDisabled

        onValueChanged: {
            if (!isInitialized)
                return;
            root.flagsEdited();
        }
    }

    // ── Add / Update / Cancel buttons ────────────────────────────────────────
    Item {
        height: visible ? constants.compactRowHeight : 0
        visible: !root.selectedProviderDisabled
        width: parent.width

        Row {
            anchors.fill: parent
            spacing: Theme.spacingS

            Rectangle {
                id: addButton

                property bool canAdd: {
                    return root.tickerValidation.valid && root.nameValidation.valid && !root.selectedProviderDisabled;
                }

                border.color: canAdd ? Theme.primary : Theme.outlineVariant
                border.width: 1
                color: canAdd ? (addButtonMouseArea.containsMouse ? Theme.primary : Theme.surfaceContainerHighest) : Theme.surfaceContainerHigh
                height: parent.height
                opacity: canAdd ? 1.0 : 0.5
                radius: Theme.cornerRadius
                width: root.editIndex >= 0 ? parent.width - cancelButton.width - Theme.spacingS : parent.width

                StyledText {
                    anchors.centerIn: parent
                    color: addButton.canAdd ? (addButtonMouseArea.containsMouse ? Theme.surfaceContainer : Theme.primary) : Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    text: root.editIndex >= 0 ? "Update Symbol" : "Add Symbol"
                }
                MouseArea {
                    id: addButtonMouseArea

                    anchors.fill: parent
                    cursorShape: addButton.canAdd ? Qt.PointingHandCursor : Qt.ArrowCursor
                    enabled: addButton.canAdd
                    hoverEnabled: true

                    onClicked: root.saveRequested()
                }
            }
            Rectangle {
                id: cancelButton

                border.color: Theme.error
                border.width: 1
                color: cancelButtonMouseArea.containsMouse ? Theme.error : Theme.surfaceContainerHighest
                height: parent.height
                radius: Theme.cornerRadius
                visible: root.editIndex >= 0
                width: constants.smallButtonWidth

                StyledText {
                    anchors.centerIn: parent
                    color: cancelButtonMouseArea.containsMouse ? Theme.surfaceContainer : Theme.error
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    text: "Cancel"
                }
                MouseArea {
                    id: cancelButtonMouseArea

                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true

                    onClicked: root.cancelRequested()
                }
            }
        }
    }
}
