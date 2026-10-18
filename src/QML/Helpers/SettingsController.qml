// SettingsController.qml - Per-page form validation, saved-symbol actions, and storage lifecycle.
// Receives plain form data and emits UI updates; it never holds a reference to an editor or control.
pragma ComponentBehavior: Bound
import QtQuick
import "../../JS/Helpers/Helpers.js" as Helpers
import "../../JS/Helpers/SymbolDraft.js" as SymbolDraft
import "../../JS/Helpers/SymbolRules.js" as SymbolRules
import "../Contracts"
import "../Services"

Item {
    id: root

    // The "add a symbol" form always starts from its defaults when the page is created (expanded): what was typed or chosen
    // before is not brought back. DMS's controls load their saved values when the service attaches, so the defaults are
    // saved over them once, then.
    property bool _applyingDraft: false
    property bool _formReset: false
    readonly property var changeResolutionOptions: selectedHandler ? selectedHandler.changeResolutionOptions() : []
    readonly property bool chartRangeAvailable: chartRangeOptions.length > 0
    readonly property var chartRangeOptions: selectedHandler ? selectedHandler.chartSpanOptions(formState.chartResolution) : []
    // Candle-count validation of the chosen resolution vs chart range (non-blocking notes).
    readonly property var chartRangeStatus: selectedHandler ? selectedHandler.chartRangeStatus(formState.chartResolution, formState.chartRange) : ({
            level: "ok",
            message: ""
        })
    readonly property var chartResolutionOptions: selectedHandler ? selectedHandler.chartResolutionOptions() : []
    property int editIndex: -1    // -1 = adding new, >= 0 = editing existing
    // Every field of the "add / edit a symbol" form as it is shown now (what tests and the save read).
    property var formState: ({})
    // The symbol's own settings (resolutions, range, toggles) can be changed once the ticker and the name are valid; a
    // symbol picked from the list has both. The provider stays choosable: the ticker is validated against it.
    readonly property bool formUnlocked: tickerValidation.valid && nameValidation.valid
    readonly property string nameText: (formState.name || "").trim()
    readonly property var nameValidation: SymbolRules.validateName(nameText)
    property string pluginId: "markets"
    property var pluginService: null
    // Dropdown options come from the selected provider's declared properties.
    readonly property var priceResolutionOptions: selectedHandler ? selectedHandler.priceResolutionOptions() : []

    // Providers that failed to load (the others keep working); shown next to the provider list.
    readonly property var providerLoadErrors: ProvidersManager.loadErrors
    // Every question about a provider goes to its ProviderHandler (null only when no provider started).
    readonly property ProviderHandler selectedHandler: ProvidersManager.handlerFromId(selectedProviderId)
    readonly property ProviderProperties selectedProvider: selectedHandler ? selectedHandler.properties : unavailableProvider
    readonly property bool selectedProviderDisabled: !!(selectedHandler && selectedHandler.properties.disabled)
    readonly property string selectedProviderId: formState.provider || ProvidersManager.defaultId
    property var symbolsList: []
    // The ticker is checked against the selected provider's declared format and length.
    readonly property string tickerText: (formState.ticker || "").trim()
    readonly property var tickerValidation: selectedHandler ? selectedHandler.validateSymbol(tickerText) : ({
            valid: false,
            message: "No data provider is available."
        })

    signal draftRequested(var draft)
    signal errorRequested(string message)
    signal infoRequested(string message)
    signal selectionRequested(var selection)

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
        let ticker = (formState.ticker || "").trim();
        let name = (formState.name || "").trim();
        if (!ticker || !name)
            return;

        // Blocking: the display name must be short and made of allowed characters.
        let nameVerdict = SymbolRules.validateName(name);
        if (!nameVerdict.valid) {
            errorRequested(nameVerdict.message);
            return;
        }

        // Blocking: the symbol must match the provider's declared format and length.
        let validation = ProvidersManager.requireFromId(formState.provider || ProvidersManager.defaultId).validateSymbol(ticker);
        if (!validation.valid) {
            errorRequested(validation.message);
            return;
        }

        // Duplicate check (skip the entry being edited)
        for (let symbolIndex = 0; symbolIndex < symbolsList.length; symbolIndex++) {
            if (symbolIndex === editIndex)
                continue;
            if (symbolsList[symbolIndex].ticker === ticker) {
                errorRequested("'" + ticker + "' is already added");
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
        let provider = formState.provider || ProvidersManager.defaultId;

        // Blocking validation: never save a resolution that is far too big/small for the range.
        let handler = ProvidersManager.requireFromId(provider);
        let status = handler.chartRangeStatus(formState.chartResolution, formState.chartRange);
        if (status.level === "block") {
            errorRequested(status.message);
            return;
        }
        let selection = handler.clampSelection({
            priceResolution: formState.priceResolution,
            changeResolution: formState.changeResolution,
            chartResolution: formState.chartResolution,
            chartRange: formState.chartRange
        });
        let showChange = Helpers.boolValue(formState.showChange, false);
        let invert = Helpers.boolValue(formState.invert, false);

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
        infoRequested((outcome.updated ? "Updated " : "Added ") + name + " (" + ticker + ")");
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
        infoRequested("Removed " + (removed.name || removed.ticker));
        if (wasEditing)
            Qt.callLater(clearForm);
        else
            Qt.callLater(refreshSymbolsList);
    }

    // Save a completed text edit through the same draft-storage boundary as the other controls.
    function saveDraftField(field, value) {
        return storage.saveDraftField(field, value);
    }

    // Persist the edited symbol flags without replacing its other settings.
    function saveEditedSymbolFlags() {
        // Loading a symbol updates several controls in sequence; those changes are not user edits.
        if (_applyingDraft)
            return;
        if (editIndex < 0 || editIndex >= symbolsList.length)
            return;
        let saved = storage.updateSymbolAt(symbolsList, editIndex, {
            showChangeWhenPinned: Helpers.boolValue(formState.showChange, false),
            invert: Helpers.boolValue(formState.invert, false)
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

        _applyingDraft = true;
        try {
            draftRequested(Object.assign({}, draft, selection));
        } finally {
            _applyingDraft = false;
        }

        storage.saveDraft({
            ticker: draft.ticker,
            name: draft.name,
            provider: draft.provider,
            priceResolution: selection.priceResolution,
            changeResolution: selection.changeResolution,
            chartResolution: selection.chartResolution,
            chartRange: selection.chartRange,
            showChange: draft.showChange,
            invert: draft.invert
        });
    }

    // Snap the three range dropdowns to values the selected provider supports
    // (e.g. after switching provider, or when loading an old saved symbol).
    function syncSelections() {
        if (!selectedHandler)
            return;
        let selection = selectedHandler.clampSelection({
            priceResolution: formState.priceResolution,
            changeResolution: formState.changeResolution,
            chartResolution: formState.chartResolution,
            chartRange: formState.chartRange
        });
        selectionRequested(selection);
        Logger.debug("settings", "selection for " + selectedProviderId + ": price " + selection.priceResolution + ", chart " + selection.chartResolution + " over " + selection.chartRange);
    }

    Component.onCompleted: {
        Logger.debug("settings", "page created: " + ProvidersManager.types.length + " providers, plugin service " + (pluginService ? "present" : "not set yet"));
        refreshSymbolsList();
        if (pluginService)
            _resetFormOnce();
        Logger.debug("settings", "controller ready: " + symbolsList.length + " symbols");
    }
    onSelectedProviderIdChanged: Qt.callLater(syncSelections)

    ProviderProperties {
        id: unavailableProvider
    }

    // ── Saved data ───────────────────────────────────────────────────────────
    // All persistence, including requests forwarded by host controls, goes through DataStorage.
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
}
