// Settings.qml - Plugin settings page
//
// Provides the configuration interface for the Markets plugin:
// - Chart colors (up/down)
// - Popup layout (visible rows slider)
// - Add/edit symbol form
// - Configured symbols list (via ConfiguredSymbol component)

pragma ComponentBehavior: Bound
import QtQuick
import "../JS/Helpers/Constants.js" as JsConstants
import "../JS/Helpers/Helpers.js" as Helpers
import "../JS/Helpers/SymbolDraft.js" as SymbolDraft
import "../JS/Helpers/SymbolRules.js" as SymbolRules
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

    // The "add a symbol" form always starts from its defaults when the page is created (expanded): what was typed or chosen
    // before is not brought back. DMS's controls load their saved values when the service attaches, so the defaults are
    // saved over them once, then.
    property bool _formReset: false
    readonly property var changeResolutionOptions: selectedHandler ? selectedHandler.changeResolutionOptions() : []
    readonly property bool chartRangeAvailable: chartRangeOptions.length > 0
    readonly property var chartRangeOptions: selectedHandler ? selectedHandler.chartSpanOptions(chartResolutionSelect.value) : []
    // Candle-count validation of the chosen resolution vs chart range (non-blocking notes).
    readonly property var chartRangeStatus: selectedHandler ? selectedHandler.chartRangeStatus(chartResolutionSelect.value, chartRangeSelect.value) : ({
            level: "ok",
            message: ""
        })
    readonly property var chartResolutionOptions: selectedHandler ? selectedHandler.chartResolutionOptions() : []
    property int editIndex: -1    // -1 = adding new, >= 0 = editing existing
    // Every field of the "add / edit a symbol" form as it is shown now (what tests and the save read).
    readonly property var formState: ({
            ticker: tickerInput.value,
            name: nameInput.value,
            provider: providerSelect.value,
            priceResolution: priceResolutionSelect.value,
            changeResolution: changeResolutionSelect.value,
            chartResolution: chartResolutionSelect.value,
            chartRange: chartRangeSelect.value,
            showChange: showChangeToggle.value,
            invert: invertToggle.value
        })
    // The symbol's own settings (resolutions, range, toggles) can be changed once the ticker and the name are valid; a
    // symbol picked from the list has both. The provider stays choosable: the ticker is validated against it.
    readonly property bool formUnlocked: tickerValidation.valid && nameValidation.valid
    readonly property string nameText: (nameInput.value || "").trim()
    readonly property var nameValidation: SymbolRules.validateName(nameText)
    // The display name: at most a few characters from a fixed set (see SymbolRules.validateName).
    readonly property int popoutRowsValue: popoutRowsSetting.value      // the popup-height slider's value
    // Dropdown options come from the selected provider's declared properties.
    readonly property var priceResolutionOptions: selectedHandler ? selectedHandler.priceResolutionOptions() : []

    // Providers that failed to load (the others keep working); shown next to the provider list.
    readonly property var providerLoadErrors: ProvidersManager.loadErrors
    // Every question about a provider goes to its ProviderHandler (null only when no provider started).
    readonly property var selectedHandler: ProvidersManager.handlerFromId(selectedProviderId)
    readonly property var selectedProvider: selectedHandler ? selectedHandler.properties : ({})
    readonly property bool selectedProviderDisabled: !!(selectedHandler && selectedHandler.properties.disabled)
    readonly property string selectedProviderId: providerSelect.value || ProvidersManager.defaultId
    property var symbolsList: []
    // The ticker is checked against the selected provider's declared format and length.
    readonly property string tickerText: (tickerInput.value || "").trim()
    readonly property var tickerValidation: selectedHandler ? selectedHandler.validateSymbol(tickerText) : ({
            valid: false,
            message: "No data provider is available."
        })

    // ── Error handling ───────────────────────────────────────────────────────
    // Errors are logged (devMode) and shown through DMS's toast; see Services/ErrorHandler.qml.
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
    // Reset the form after its host service attaches, once per page.
    function _resetFormOnce() {
        if (_formReset)
            return;
        _formReset = true;
        Qt.callLater(root.clearForm);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    // Validate the form and reject duplicates before saving the symbol.
    function addOrUpdateSymbol() {
        let ticker = (tickerInput.value || "").trim();
        let name = (nameInput.value || "").trim();
        if (!ticker || !name)
            return;

        // Blocking: the display name must be short and made of allowed characters.
        let nameVerdict = SymbolRules.validateName(name);
        if (!nameVerdict.valid) {
            ToastService.showError("Markets", nameVerdict.message);
            return;
        }

        // Blocking: the symbol must match the provider's declared format and length.
        let validation = ProvidersManager.requireFromId(providerSelect.value || ProvidersManager.defaultId).validateSymbol(ticker);
        if (!validation.valid) {
            ToastService.showError("Markets", validation.message);
            return;
        }

        // Duplicate check (skip the entry being edited)
        for (let symbolIndex = 0; symbolIndex < symbolsList.length; symbolIndex++) {
            if (symbolIndex === editIndex)
                continue;
            if (symbolsList[symbolIndex].ticker === ticker) {
                ToastService.showError("Markets", "'" + ticker + "' is already added");
                return;
            }
        }

        doSaveSymbol(ticker, name);
    }

    // Leave edit mode and return the form to its defaults.
    function cancelEdit() {
        clearForm();
    }

    // Reset the form to the default provider and refresh the saved list.
    function clearForm() {
        editIndex = -1;
        let defaultProvider = ProvidersManager.defaultId;
        setDraft(SymbolDraft.empty(defaultProvider, ProvidersManager.requireFromId(defaultProvider).defaultSelection()));
        refreshSymbolsList();
    }

    // Build a current-format symbol and report a successful save.
    function doSaveSymbol(ticker, name) {
        let provider = providerSelect.value || ProvidersManager.defaultId;

        // Blocking validation: never save a resolution that is far too big/small for the range.
        let handler = ProvidersManager.requireFromId(provider);
        let status = handler.chartRangeStatus(chartResolutionSelect.value, chartRangeSelect.value);
        if (status.level === "block") {
            ToastService.showError("Markets", status.message);
            return;
        }
        let selection = handler.clampSelection({
            priceResolution: priceResolutionSelect.value,
            changeResolution: changeResolutionSelect.value,
            chartResolution: chartResolutionSelect.value,
            chartRange: chartRangeSelect.value
        });
        let showChange = Helpers.boolValue(showChangeToggle.value, false);
        let invert = Helpers.boolValue(invertToggle.value, false);

        // A new symbol gets its own uid; the storage refuses anything that is not a valid SavedSymbol.
        let entry = {
            uid: Helpers.generateUuid(),
            ticker: ticker,
            name: name,
            provider: provider,
            priceResolution: selection.priceResolution,
            changeResolution: selection.changeResolution,
            chartResolution: selection.chartResolution,
            chartRange: selection.chartRange,
            showChangeWhenPinned: showChange,
            invert: invert,
            pinned: false
        };

        // Editing keeps the symbol's uid and pinned state (the storage does that); success is
        // only announced once the list is really saved.
        Logger.debug("settings", (editIndex >= 0 ? "updating " : "adding ") + ticker + " (" + provider + ")");
        let outcome = storage.upsertSymbol(symbolsList, entry, editIndex);
        if (!outcome.saved)
            return;
        ToastService.showInfo("Markets", (outcome.updated ? "Updated " : "Added ") + name + " (" + ticker + ")");
        Qt.callLater(clearForm);
    }

    // Load the selected symbol into the edit form.
    function editSymbol(symbolIndex) {
        if (symbolIndex < 0 || symbolIndex >= symbolsList.length)
            return;
        // Toggle: clicking the already-selected symbol deselects it
        if (editIndex === symbolIndex) {
            cancelEdit();
            return;
        }
        editIndex = symbolIndex;
        setDraft(SymbolDraft.fromSymbol(symbolsList[symbolIndex], ProvidersManager.defaultId));
        Qt.callLater(function () {
            refreshSymbolsList();
        });
    }
    // Read the saved value after the settings service becomes available.
    function loadValue(key, defaultValue) {
        return storage.load(key, defaultValue);
    }

    // Persist a reorder and keep the edit position on the same symbol.
    function moveSymbol(symbolIndex, direction) {
        let targetIndex = symbolIndex + direction;
        if (!storage.moveSymbol(symbolsList, symbolIndex, direction))
            return;
        if (editIndex === symbolIndex)
            editIndex = targetIndex;
        else if (editIndex === targetIndex)
            editIndex = symbolIndex;
        Qt.callLater(refreshSymbolsList);
    }

    // Reads, migrates (and persists the migration of) the saved symbols; damaged data is
    // reported and backed up by the storage.
    function refreshSymbolsList() {
        symbolsList = storage.loadSymbols();
        Logger.debug("settings", "symbols list: " + symbolsList.length + " symbols");
    }

    // Remove the selected entry and update the active edit position.
    function removeSymbolAt(symbolIndex) {
        let removed = storage.removeSymbolAt(symbolsList, symbolIndex);
        if (!removed)
            return;
        let wasEditing = (editIndex === symbolIndex);
        if (editIndex > symbolIndex)
            editIndex--;
        ToastService.showInfo("Markets", "Removed " + (removed.name || removed.ticker));
        if (wasEditing)
            Qt.callLater(clearForm);
        else
            Qt.callLater(refreshSymbolsList);
    }

    // Persist the edited symbol flags without replacing its other settings.
    function saveEditedSymbolFlags() {
        if (editIndex < 0 || editIndex >= symbolsList.length)
            return;
        let saved = storage.updateSymbolAt(symbolsList, editIndex, {
            showChangeWhenPinned: Helpers.boolValue(showChangeToggle.value, false),
            invert: Helpers.boolValue(invertToggle.value, false)
        });
        if (saved)
            refreshSymbolsList();
    }

    // Returns whether the value was really saved; a failure is reported by the storage.
    function saveValue(key, value) {
        return storage.save(key, value);
    }

    // Shows a draft in the form (old or unsupported values snapped to what the provider offers; a symbol of a
    // provider that is not available keeps its values) and keeps it saved.
    function setDraft(draft) {
        let handler = ProvidersManager.handlerFromId(draft.provider);
        let selection = handler ? handler.clampSelection(draft) : draft;

        tickerInput.value = draft.ticker;
        nameInput.value = draft.name;
        providerSelect.value = draft.provider;
        priceResolutionSelect.value = selection.priceResolution;
        changeResolutionSelect.value = selection.changeResolution;
        chartResolutionSelect.value = selection.chartResolution;
        chartRangeSelect.value = selection.chartRange;
        showChangeToggle.value = draft.showChange;
        invertToggle.value = draft.invert;

        storage.saveDraft({
            ticker: draft.ticker,
            name: draft.name,
            provider: draft.provider,
            priceResolution: selection.priceResolution,
            changeResolution: selection.changeResolution,
            chartResolution: selection.chartResolution,
            chartRange: selection.chartRange,
            showChange: showChangeToggle.value,
            invert: invertToggle.value
        });
    }

    // Snap the three range dropdowns to values the selected provider supports
    // (e.g. after switching provider, or when loading an old saved symbol).
    function syncSelections() {
        if (!selectedHandler)
            return;
        let selection = selectedHandler.clampSelection({
            priceResolution: priceResolutionSelect.value,
            changeResolution: changeResolutionSelect.value,
            chartResolution: chartResolutionSelect.value,
            chartRange: chartRangeSelect.value
        });
        if (priceResolutionSelect.value !== selection.priceResolution)
            priceResolutionSelect.value = selection.priceResolution;
        if (changeResolutionSelect.value !== selection.changeResolution)
            changeResolutionSelect.value = selection.changeResolution;
        if (chartResolutionSelect.value !== selection.chartResolution)
            chartResolutionSelect.value = selection.chartResolution;
        if (chartRangeSelect.value !== selection.chartRange)
            chartRangeSelect.value = selection.chartRange;
        Logger.debug("settings", "selection for " + selectedProviderId + ": price " + selection.priceResolution + ", chart " + selection.chartResolution + " over " + selection.chartRange);
    }

    pluginId: "markets"

    Component.onCompleted: {
        Logger.debug("settings", "page created: " + ProvidersManager.types.length + " providers, plugin service " + (pluginService ? "present" : "not set yet"));
        refreshSymbolsList();
        if (pluginService)
            _resetFormOnce();
        Logger.debug("settings", "page ready: " + symbolsList.length + " symbols, height " + implicitHeight);
    }
    onSelectedProviderIdChanged: Qt.callLater(syncSelections)

    Constants {
        id: constants
    }

    // ── Saved data ───────────────────────────────────────────────────────────
    // Everything that reads or writes plugin data goes through DataStorage. DMS's setting
    // controls call saveValue/loadValue on this item, so they are kept and delegate to it.
    DataStorage {
        id: storage

        pluginId: root.pluginId
        pluginService: root.pluginService

        // DMS creates this page first and attaches the service afterwards: the list can only be read from then on.
        onPluginServiceChanged: {
            Logger.debug("settings", "plugin service " + (pluginService ? "attached" : "detached"));
            if (pluginService) {
                root.refreshSymbolsList();
                root._resetFormOnce();
            }
        }
    }

    // Plugin data changes elsewhere too (the widget saves the migrated list, DMS delivers data late): follow it.
    Connections {
        // Reload this plugin when the host delivers updated settings.
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === root.pluginId)
                root.refreshSymbolsList();
        }

        enabled: root.pluginService !== null
        target: root.pluginService
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

        StyledText {
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
            text: "Chart Colors"
            topPadding: Theme.spacingM
            width: parent.width
        }
        ColorSettingRow {
            defaultColor: constants.defaultUpColor.toString()
            description: "Hex color for positive changes (e.g., " + constants.defaultUpColor + ")"
            label: "Up / Positive Color"
            settingKey: "upColor"
        }
        ColorSettingRow {
            defaultColor: constants.defaultDownColor.toString()
            description: "Hex color for negative changes (e.g., " + constants.defaultDownColor + ")"
            label: "Down / Negative Color"
            settingKey: "downColor"
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  POPUP LAYOUT
        // ═══════════════════════════════════════════════════════════════════════

        StyledText {
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
            text: "Popup Height"
            topPadding: Theme.spacingM
            width: parent.width
        }
        ValueSliderRow {
            id: popoutRowsSetting

            defaultValue: constants.defaultPopoutRows
            label: "Visible Symbol Rows without scrolling"
            maximum: constants.maxPopoutRows
            minimum: constants.minPopoutRows
            settingKey: "popoutRows"
        }
        StyledText {
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
            text: "Global symbol settings"
            topPadding: Theme.spacingM
            width: parent.width
        }
        StyledText {
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
            text: "Choose which details to show for all of the configured symbols"
            width: parent.width
            wrapMode: Text.WordWrap
        }
        ToggleSetting {
            defaultValue: true
            description: "Show the ticker ID and price resolution below the symbol name"
            label: "Show Symbol Ticker"
            settingKey: "showTicker"
        }
        ToggleSetting {
            defaultValue: true
            description: "Show the price change amount and percentage"
            label: "Show Price Change"
            settingKey: "showPriceChange"
        }
        ToggleSetting {
            defaultValue: true
            description: "Show the time range on the chart"
            label: "Show Chart Range"
            settingKey: "showChartRange"
        }
        ToggleSetting {
            defaultValue: true
            description: "Show the data provider's three-letter alias on the chart"
            label: "Show Provider Alias"
            settingKey: "showProviderName"
        }
        ToggleSetting {
            defaultValue: true
            description: "Show how long ago the symbol data was last refreshed"
            label: "Show Refreshed Since"
            settingKey: "showRefreshedSince"
        }
        Rectangle {
            color: Theme.outlineVariant
            height: 1
            width: parent.width
        }

        // ═══════════════════════════════════════════════════════════════════════
        //  SYMBOL LOOKUP + ADD/EDIT
        // ═══════════════════════════════════════════════════════════════════════

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

                    onEditingFinished: storage.saveDraftField("ticker", text.trim())
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

                onEditingFinished: storage.saveDraftField("name", text.trim())
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
            onValueChanged: Qt.callLater(root.syncSelections)
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
                root.saveEditedSymbolFlags();
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
                root.saveEditedSymbolFlags();
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
                        let ticker = (tickerInput.value || "").trim();
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

                        onClicked: root.addOrUpdateSymbol()
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

                        onClicked: root.cancelEdit()
                    }
                }
            }
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
            model: root.symbolsList

            delegate: ConfiguredSymbol {
                required property int index
                required property var modelData

                isEditing: root.editIndex === index
                isFirst: index === 0
                isLast: index === root.symbolsList.length - 1
                symbolData: modelData
                width: root.width

                onClicked: root.editSymbol(index)
                onMovedDown: root.moveSymbol(index, 1)
                onMovedUp: root.moveSymbol(index, -1)
                onRemoved: root.removeSymbolAt(index)
            }
        }
    } // settingsBody

}
