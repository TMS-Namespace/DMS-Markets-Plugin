// Settings.qml - Plugin settings page
//
// Provides the configuration interface for the Markets plugin:
// - Chart colors (up/down)
// - Popup layout (visible rows slider)
// - Add/edit symbol form
// - Configured symbols list (via ConfiguredSymbol component)

import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Plugins
import qs.Widgets
import "../JS/Helpers/Helpers.js" as Helpers
import "../JS/Helpers/Constants.js" as JsK
import "../JS/Helpers/SymbolDraft.js" as SymbolDraft
import "../JS/Helpers/SymbolRules.js" as SymbolRules
import "./Helpers"
import "./Services"
import "./Views"

PluginSettings {
    id: root
    pluginId: "markets"

    Constants { id: constants }

    property var  symbolsList:  []
    property int  editIndex:    -1    // -1 = adding new, >= 0 = editing existing
    readonly property string selectedProviderId: providerSelect.value || ProvidersManager.defaultId
    // Every question about a provider goes to its ProviderHandler (null only when no provider started).
    readonly property var selectedHandler: ProvidersManager.handlerFromId(selectedProviderId)
    readonly property bool selectedProviderDisabled: !!(selectedHandler && selectedHandler.properties.disabled)
    // Dropdown options come from the selected provider's declared properties.
    readonly property var priceResolutionOptions:       selectedHandler ? selectedHandler.priceResolutionOptions() : []
    readonly property var changeResolutionOptions:      selectedHandler ? selectedHandler.changeResolutionOptions() : []
    readonly property var chartResolutionOptions:  selectedHandler ? selectedHandler.chartResolutionOptions() : []
    readonly property var chartRangeOptions:       selectedHandler ? selectedHandler.chartSpanOptions(chartResolutionSelect.value) : []
    readonly property bool chartRangeAvailable:    chartRangeOptions.length > 0
    readonly property var selectedProvider:        selectedHandler ? selectedHandler.properties : ({})
    // The ticker is checked against the selected provider's declared format and length.
    readonly property string tickerText:           (tickerInput.value || "").trim()
    readonly property var tickerValidation:        selectedHandler ? selectedHandler.validateSymbol(tickerText) : ({ valid: false, message: "No data provider is available." })
    // The display name: at most a few characters from a fixed set (see SymbolRules.validateName).
    readonly property string nameText:             (nameInput.value || "").trim()
    readonly property var nameValidation:          SymbolRules.validateName(nameText)
    // Candle-count validation of the chosen resolution vs chart range (non-blocking notes).
    readonly property var chartRangeStatus:        selectedHandler ? selectedHandler.chartRangeStatus(chartResolutionSelect.value, chartRangeSelect.value) : ({ level: "ok", message: "" })

    onSelectedProviderIdChanged: Qt.callLater(syncSelections)

    // ── Error handling ───────────────────────────────────────────────────────
    // Errors are logged (devMode) and shown through DMS's toast; see Services/ErrorHandler.qml.
    function _configureErrorHandler() {
        Logger.configure({ devMode: constants.devMode })
        ErrorHandler.configure({
            notify: function(message, details, category) {
                ToastService.showError("Markets: " + message, details, "", category)
            }
        })
        return true
    }
    readonly property bool _errorHandlerReady: _configureErrorHandler()

    // Providers that failed to load (the others keep working); shown next to the provider list.
    readonly property var providerLoadErrors: ProvidersManager.loadErrors

    // ── Saved data ───────────────────────────────────────────────────────────
    // Everything that reads or writes plugin data goes through DataStorage. DMS's setting
    // controls call saveValue/loadValue on this item, so they are kept and delegate to it.
    DataStorage {
        id: storage
        pluginId:      root.pluginId
        pluginService: root.pluginService
        // DMS creates this page first and attaches the service afterwards: the list can only be read from then on.
        onPluginServiceChanged: {
            Logger.debug("settings", "plugin service " + (pluginService ? "attached" : "detached"))
            if (pluginService) root.refreshSymbolsList()
        }
    }

    // Plugin data changes elsewhere too (the widget saves the migrated list, DMS delivers data late): follow it.
    Connections {
        target: root.pluginService
        enabled: root.pluginService !== null
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === root.pluginId) root.refreshSymbolsList()
        }
    }

    // Returns whether the value was really saved; a failure is reported by the storage.
    function saveValue(key, value) { return storage.save(key, value) }
    function loadValue(key, defaultValue) { return storage.load(key, defaultValue) }

    // Reads, migrates (and persists the migration of) the saved symbols; damaged data is
    // reported and backed up by the storage.
    function refreshSymbolsList() {
        symbolsList = storage.loadSymbols()
        Logger.debug("settings", "symbols list: " + symbolsList.length + " symbols")
    }

    // Snap the three range dropdowns to values the selected provider supports
    // (e.g. after switching provider, or when loading an old saved symbol).
    function syncSelections() {
        if (!selectedHandler) return
        var selection = selectedHandler.clampSelection({
            priceResolution: priceResolutionSelect.value, changeResolution: changeResolutionSelect.value, chartResolution: chartResolutionSelect.value, chartRange: chartRangeSelect.value })
        if (priceResolutionSelect.value !== selection.priceResolution)         priceResolutionSelect.value = selection.priceResolution
        if (changeResolutionSelect.value !== selection.changeResolution)       changeResolutionSelect.value = selection.changeResolution
        if (chartResolutionSelect.value !== selection.chartResolution)  chartResolutionSelect.value = selection.chartResolution
        if (chartRangeSelect.value !== selection.chartRange)         chartRangeSelect.value = selection.chartRange
        Logger.debug("settings", "selection for " + selectedProviderId + ": price " + selection.priceResolution
                           + ", chart " + selection.chartResolution + " over " + selection.chartRange)
    }

    Component.onCompleted: {
        Logger.debug("settings", "page created: " + ProvidersManager.types.length + " providers, plugin service " + (pluginService ? "present" : "not set yet"))
        refreshSymbolsList()
        Logger.debug("settings", "page ready: " + symbolsList.length + " symbols, height " + implicitHeight)
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  HEADER
    // ═══════════════════════════════════════════════════════════════════════

    StyledText {
        width: parent.width
        text: "Markets Plugin"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: constants.pluginSubtitle
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  CHART COLORS
    // ═══════════════════════════════════════════════════════════════════════

    Column {
        id: settingsBody
        width: parent.width
        spacing: Theme.spacingS

    StyledText {
        width: parent.width
        text: "Chart Colors"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingM
    }

    ColorSettingRow {
        settingKey: "upColor"
        label: "Up / Positive Color"
        description: "Hex color for positive changes (e.g., " + constants.defaultUpColor + ")"
        defaultColor: constants.defaultUpColor
    }

    ColorSettingRow {
        settingKey: "downColor"
        label: "Down / Negative Color"
        description: "Hex color for negative changes (e.g., " + constants.defaultDownColor + ")"
        defaultColor: constants.defaultDownColor
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  POPUP LAYOUT
    // ═══════════════════════════════════════════════════════════════════════

    StyledText {
        width: parent.width
        text: "Popup Height"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingM
    }

    SliderSetting {
        settingKey: "popoutRows"
        label: "Visible Symbol Rows without scrolling"
        minimum: constants.minPopoutRows
        maximum: constants.maxPopoutRows
        defaultValue: constants.defaultPopoutRows
    }

    StyledText {
        width: parent.width
        text: "Global symbol settings"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingM
    }

    StyledText {
        width: parent.width
        text: "Choose which details to show for all of the configured symbols"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        settingKey: "showTicker"
        label: "Show Symbol Ticker"
        description: "Show the ticker ID and price resolution below the symbol name"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showPriceChange"
        label: "Show Price Change"
        description: "Show the price change amount and percentage"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showChartRange"
        label: "Show Chart Range"
        description: "Show the time range on the chart"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showProviderName"
        label: "Show Provider Alias"
        description: "Show the data provider's three-letter alias on the chart"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showRefreshedSince"
        label: "Show Refreshed Since"
        description: "Show how long ago the symbol data was last refreshed"
        defaultValue: true
    }

    Rectangle { width: parent.width; height: 1; color: Theme.outlineVariant }

    // ═══════════════════════════════════════════════════════════════════════
    //  SYMBOL LOOKUP + ADD/EDIT
    // ═══════════════════════════════════════════════════════════════════════

    StyledText {
        width: parent.width
        text: root.editIndex >= 0 ? "Edit Symbol" : "Add New Symbol"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingM
    }

    SelectionSetting {
        id: providerSelect
        settingKey: JsK.DRAFT_KEYS.provider
        label: "Data Provider"
        description: "Source for price data"
        visible: ProvidersManager.types.length > 1
        options: ProvidersManager.options()
        defaultValue: ProvidersManager.defaultId
    }

    Column {
        id: providerInfo
        width: parent.width
        spacing: Theme.spacingXS
        visible: root.selectedProvider.description !== undefined
                 && (root.selectedProvider.description || "") !== ""

        StyledText {
            width: parent.width
            text: root.selectedProvider.description || ""
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }
    }

    // Providers that could not be loaded; the others keep working.
    Repeater {
        model: root.providerLoadErrors
        delegate: StyledText {
            width: parent.width
            text: modelData.userMessage
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.error
            wrapMode: Text.WordWrap
        }
    }

    StyledText {
        width: parent.width
        visible: root.selectedProviderDisabled
        text: root.selectedProvider.disabledMessage
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    Column {
        id: tickerInput
        width: parent.width
        visible: !root.selectedProviderDisabled
        height: visible ? implicitHeight : 0
        spacing: Theme.spacingS

        property alias value: tickerField.text

        Component.onCompleted: Qt.callLater(function() {
            tickerInput.value = storage.loadDraftField("ticker", "")
        })

        StyledText {
            text: "Symbol Ticker"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        StyledText {
            text: root.selectedProvider.symbolHelpText
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            width: parent.width
            wrapMode: Text.WordWrap
        }

        // Format and length come from the provider's declared symbol rules.
        StyledText {
            visible: root.tickerText !== "" && !root.tickerValidation.valid
            text: root.tickerValidation.message
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.error
            width: parent.width
            wrapMode: Text.WordWrap
        }

        Row {
            width: parent.width
            height: constants.compactRowHeight
            spacing: Theme.spacingS

            DankTextField {
                id: tickerField
                width: parent.width - providerSearchButton.width - Theme.spacingS
                placeholderText: root.selectedProvider.symbolPlaceholder
                onEditingFinished: storage.saveDraftField("ticker", text.trim())
            }

            Rectangle {
                id: providerSearchButton
                width: Math.min(constants.symbolSearchButtonWidth, Math.round(parent.width * 0.48))
                height: parent.height
                radius: Theme.cornerRadius
                color: providerSearchMouseArea.containsMouse ? Theme.primary : Theme.surfaceContainerHighest
                border.color: Theme.primary
                border.width: 1

                Row {
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: constants.symbolSearchButtonPadding
                        rightMargin: constants.symbolSearchButtonPadding
                    }
                    spacing: Theme.spacingXS

                    DankIcon {
                        name: "open_in_new"
                        size: Theme.fontSizeMedium
                        color: providerSearchMouseArea.containsMouse ? Theme.surfaceContainer : Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "Open symbols search..."
                        width: parent.width - x
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: providerSearchMouseArea.containsMouse ? Theme.surfaceContainer : Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: providerSearchMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var provider = root.selectedProvider
                        if (provider.symbolSearchUrl) Qt.openUrlExternally(provider.symbolSearchUrl)
                    }
                }
            }
        }
    }

    Column {
        id: nameInput
        width: parent.width
        visible: !root.selectedProviderDisabled
        height: visible ? implicitHeight : 0
        spacing: Theme.spacingS

        property alias value: nameField.text

        Component.onCompleted: Qt.callLater(function() {
            nameInput.value = storage.loadDraftField("name", "")
        })

        StyledText {
            text: "Display Name"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        StyledText {
            text: "Short label shown for the symbol (max " + JsK.DISPLAY_NAME_MAX_LENGTH + " char.)"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            width: parent.width
            wrapMode: Text.WordWrap
        }

        DankTextField {
            id: nameField
            width: parent.width
            placeholderText: "Gold"
            maximumLength: JsK.DISPLAY_NAME_MAX_LENGTH
            onEditingFinished: storage.saveDraftField("name", text.trim())
        }

        StyledText {
            visible: root.nameText !== "" && !root.nameValidation.valid
            text: root.nameValidation.message
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.error
            width: parent.width
            wrapMode: Text.WordWrap
        }
    }

    SelectionSetting {
        id: priceResolutionSelect
        settingKey: JsK.DRAFT_KEYS.priceResolution
        label: "Price Resolution"
        description: "Candle size for the live price, also sets how often it is refreshed"
        visible: !root.selectedProviderDisabled
        options: root.priceResolutionOptions
        defaultValue: JsK.DEFAULT_PRICE_RESOLUTION
    }

    SelectionSetting {
        id: changeResolutionSelect
        settingKey: JsK.DRAFT_KEYS.changeResolution
        label: "Price Change Resolution"
        description: "The price change is calculated against the close of the previous period of this size"
        visible: !root.selectedProviderDisabled
        options: root.changeResolutionOptions
        defaultValue: JsK.DEFAULT_CHANGE_RESOLUTION
    }

    SelectionSetting {
        id: chartResolutionSelect
        settingKey: JsK.DRAFT_KEYS.chartResolution
        label: "Chart Resolution"
        description: "Candle size of the charts"
        visible: !root.selectedProviderDisabled
        options: root.chartResolutionOptions
        defaultValue: JsK.DEFAULT_CHART_RESOLUTION
        // Keep the chart range valid for the newly chosen resolution.
        onValueChanged: Qt.callLater(root.syncSelections)
    }

    SelectionSetting {
        id: chartRangeSelect
        settingKey: JsK.DRAFT_KEYS.chartRange
        label: "Chart Range"
        description: root.chartRangeAvailable
                     ? "How much historical data to show in the charts"
                     : "Choose a chart resolution first"
        visible: !root.selectedProviderDisabled
        enabled: root.chartRangeAvailable
        opacity: enabled ? 1.0 : 0.5
        options: root.chartRangeOptions
        defaultValue: JsK.DEFAULT_CHART_SPAN
    }

    // Non-blocking note: the chosen resolution gives very few / very many candles.
    // (Combinations that would be far off are not offered at all.)
    StyledText {
        width: parent.width
        visible: !root.selectedProviderDisabled && root.chartRangeAvailable
                 && root.chartRangeStatus.level === "warn"
        text: root.chartRangeStatus.message
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.warning
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        id: showChangeToggle
        settingKey: JsK.DRAFT_KEYS.showChange
        label: "Show Price Change When Pinned"
        description: "Display price change in the bar when this symbol is pinned"
        defaultValue: false
        visible: !root.selectedProviderDisabled
        onValueChanged: {
            if (!isInitialized) return
            root.saveEditedSymbolFlags()
        }
    }

    ToggleSetting {
        id: invertToggle
        settingKey: JsK.DRAFT_KEYS.invert
        label: "Invert Prices (1/x)"
        description: "Show the reciprocal of the price and chart (e.g., USD/EUR instead of EUR/USD)"
        defaultValue: false
        visible: !root.selectedProviderDisabled
        onValueChanged: {
            if (!isInitialized) return
            root.saveEditedSymbolFlags()
        }
    }

    // ── Add / Update / Cancel buttons ────────────────────────────────────────
    Item {
        width: parent.width
        visible: !root.selectedProviderDisabled
        height: visible ? constants.compactRowHeight : 0

        Row {
            anchors.fill: parent
            spacing: Theme.spacingS

            Rectangle {
                id: addButton
                width: root.editIndex >= 0 ? parent.width - cancelButton.width - Theme.spacingS : parent.width
                height: parent.height
                radius: Theme.cornerRadius

                property bool canAdd: {
                    var ticker      = (tickerInput.value || "").trim()
                    return root.tickerValidation.valid && root.nameValidation.valid && !root.selectedProviderDisabled
                }

                color: canAdd
                    ? (addButtonMouseArea.containsMouse ? Theme.primary : Theme.surfaceContainerHighest)
                    : Theme.surfaceContainerHigh
                border.color: canAdd ? Theme.primary : Theme.outlineVariant
                border.width: 1
                opacity: canAdd ? 1.0 : 0.5

                StyledText {
                    anchors.centerIn: parent
                    text: root.editIndex >= 0 ? "Update Symbol" : "Add Symbol"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: addButton.canAdd
                        ? (addButtonMouseArea.containsMouse ? Theme.surfaceContainer : Theme.primary)
                        : Theme.surfaceVariantText
                }

                MouseArea {
                    id: addButtonMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: addButton.canAdd ? Qt.PointingHandCursor : Qt.ArrowCursor
                    enabled: addButton.canAdd
                    onClicked: root.addOrUpdateSymbol()
                }
            }

            Rectangle {
                id: cancelButton
                width: constants.smallButtonWidth
                height: parent.height
                radius: Theme.cornerRadius
                visible: root.editIndex >= 0
                color: cancelButtonMouseArea.containsMouse ? Theme.error : Theme.surfaceContainerHighest
                border.color: Theme.error
                border.width: 1

                StyledText {
                    anchors.centerIn: parent
                    text: "Cancel"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: cancelButtonMouseArea.containsMouse ? Theme.surfaceContainer : Theme.error
                }

                MouseArea {
                    id: cancelButtonMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.cancelEdit()
                }
            }
        }
    }

    Rectangle { width: parent.width; height: 1; color: Theme.outlineVariant }

    // ═══════════════════════════════════════════════════════════════════════
    //  CONFIGURED SYMBOLS LIST
    // ═══════════════════════════════════════════════════════════════════════

    StyledText {
        width: parent.width
        text: "Configured Symbols"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingS
    }

    Repeater {
        model: root.symbolsList

        delegate: ConfiguredSymbol {
            width: root.width
            symbolData: modelData
            isEditing:  root.editIndex === index
            isFirst:    index === 0
            isLast:     index === root.symbolsList.length - 1

            onClicked:   root.editSymbol(index)
            onRemoved:   root.removeSymbolAt(index)
            onMovedUp:   root.moveSymbol(index, -1)
            onMovedDown: root.moveSymbol(index, 1)
        }
    }

    } // settingsBody

    // ═══════════════════════════════════════════════════════════════════════
    //  FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function addOrUpdateSymbol() {
        var ticker = (tickerInput.value || "").trim()
        var name   = (nameInput.value || "").trim()
        if (!ticker || !name) return

        // Blocking: the display name must be short and made of allowed characters.
        var nameVerdict = SymbolRules.validateName(name)
        if (!nameVerdict.valid) {
            ToastService.showError("Markets", nameVerdict.message)
            return
        }

        // Blocking: the symbol must match the provider's declared format and length.
        var validation = ProvidersManager.requireFromId(providerSelect.value || ProvidersManager.defaultId).validateSymbol(ticker)
        if (!validation.valid) {
            ToastService.showError("Markets", validation.message)
            return
        }

        // Duplicate check (skip the entry being edited)
        for (var symbolIndex = 0; symbolIndex < symbolsList.length; symbolIndex++) {
            if (symbolIndex === editIndex) continue
            if (symbolsList[symbolIndex].ticker === ticker) {
                ToastService.showError("Markets", "'" + ticker + "' is already added")
                return
            }
        }

        doSaveSymbol(ticker, name)
    }

    function doSaveSymbol(ticker, name) {
        var provider   = providerSelect.value || ProvidersManager.defaultId

        // Blocking validation: never save a resolution that is far too big/small for the range.
        var handler  = ProvidersManager.requireFromId(provider)
        var status = handler.chartRangeStatus(chartResolutionSelect.value, chartRangeSelect.value)
        if (status.level === "block") {
            ToastService.showError("Markets", status.message)
            return
        }
        var selection        = handler.clampSelection({
            priceResolution: priceResolutionSelect.value, changeResolution: changeResolutionSelect.value, chartResolution: chartResolutionSelect.value, chartRange: chartRangeSelect.value })
        var showChange = Helpers.boolValue(showChangeToggle.value, false)
        var invert     = Helpers.boolValue(invertToggle.value, false)

        // A new symbol gets its own uid; the storage refuses anything that is not a valid SavedSymbol.
        var entry = {
            uid:                  Helpers.generateUuid(),
            ticker:               ticker,
            name:                 name,
            provider:             provider,
            priceResolution:      selection.priceResolution,
            changeResolution:     selection.changeResolution,
            chartResolution:      selection.chartResolution,
            chartRange:           selection.chartRange,
            showChangeWhenPinned: showChange,
            invert:               invert,
            pinned:               false
        }

        // Editing keeps the symbol's uid and pinned state (the storage does that); success is
        // only announced once the list is really saved.
        Logger.debug("settings", (editIndex >= 0 ? "updating " : "adding ") + ticker + " (" + provider + ")")
        var outcome = storage.upsertSymbol(symbolsList, entry, editIndex)
        if (!outcome.saved) return
        ToastService.showInfo("Markets", (outcome.updated ? "Updated " : "Added ") + name + " (" + ticker + ")")
        Qt.callLater(clearForm)
    }

    function editSymbol(symbolIndex) {
        if (symbolIndex < 0 || symbolIndex >= symbolsList.length) return
        // Toggle: clicking the already-selected symbol deselects it
        if (editIndex === symbolIndex) { cancelEdit(); return }
        editIndex = symbolIndex
        setDraft(SymbolDraft.fromSymbol(symbolsList[symbolIndex], ProvidersManager.defaultId))
        Qt.callLater(function() { refreshSymbolsList() })
    }

    function cancelEdit() { clearForm() }

    function clearForm() {
        editIndex = -1
        var defaultProvider = ProvidersManager.defaultId
        setDraft(SymbolDraft.empty(defaultProvider, ProvidersManager.requireFromId(defaultProvider).defaultSelection()))
        refreshSymbolsList()
    }

    // Shows a draft in the form (old or unsupported values snapped to what the provider offers; a symbol of a
    // provider that is not available keeps its values) and keeps it saved.
    function setDraft(draft) {
        var handler = ProvidersManager.handlerFromId(draft.provider)
        var selection = handler ? handler.clampSelection(draft) : draft

        tickerInput.value = draft.ticker
        nameInput.value = draft.name
        providerSelect.value = draft.provider
        priceResolutionSelect.value = selection.priceResolution
        changeResolutionSelect.value = selection.changeResolution
        chartResolutionSelect.value = selection.chartResolution
        chartRangeSelect.value = selection.chartRange
        showChangeToggle.value = draft.showChange
        invertToggle.value = draft.invert

        storage.saveDraft({
            ticker: draft.ticker, name: draft.name, provider: draft.provider,
            priceResolution: selection.priceResolution, changeResolution: selection.changeResolution, chartResolution: selection.chartResolution, chartRange: selection.chartRange,
            showChange: showChangeToggle.value, invert: invertToggle.value
        })
    }

    function saveEditedSymbolFlags() {
        if (editIndex < 0 || editIndex >= symbolsList.length) return
        var saved = storage.updateSymbolAt(symbolsList, editIndex, {
            showChangeWhenPinned: Helpers.boolValue(showChangeToggle.value, false),
            invert:               Helpers.boolValue(invertToggle.value, false)
        })
        if (saved) refreshSymbolsList()
    }

    function removeSymbolAt(symbolIndex) {
        var removed = storage.removeSymbolAt(symbolsList, symbolIndex)
        if (!removed) return
        var wasEditing = (editIndex === symbolIndex)
        if (editIndex > symbolIndex) editIndex--
        ToastService.showInfo("Markets", "Removed " + (removed.name || removed.ticker))
        if (wasEditing) Qt.callLater(clearForm)
        else Qt.callLater(refreshSymbolsList)
    }

    function moveSymbol(symbolIndex, direction) {
        var targetIndex = symbolIndex + direction
        if (!storage.moveSymbol(symbolsList, symbolIndex, direction)) return
        if (editIndex === symbolIndex) editIndex = targetIndex
        else if (editIndex === targetIndex) editIndex = symbolIndex
        Qt.callLater(refreshSymbolsList)
    }

}
