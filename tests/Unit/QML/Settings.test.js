// Static wiring checks of Settings.qml (the behaviour is tested in Settings.test.qml on the real runtime).
const { assert, readSource } = require("../../Helpers/Loader");

const page = readSource("QML/Settings.qml");
const controller = readSource("QML/Helpers/SettingsController.qml");
const editor = readSource("QML/Views/SymbolEditor.qml");
const display = readSource("QML/Views/DisplaySettings.qml");
const source = [page, controller, editor, display].join("\n").replace(/^\s*\/\/.*$/gm, "");

// Views expose fields and actions; persistence and provider decisions stay on the page.
assert(/SymbolEditor\s*\{/.test(page) && /DisplaySettings\s*\{/.test(page));
for (const view of [editor, display])
    assert(
        !/DataStorage|storage\.|pluginService\./.test(view.replace(/\/\/[^\n]*/g, "")),
        "settings views do not access storage"
    );
for (const [signal, action] of [
    ["SaveRequested", "addOrUpdateSymbol"],
    ["CancelRequested", "cancelEdit"],
    ["FlagsEdited", "saveEditedSymbolFlags"]
])
    assert(page.includes(`on${signal}: root.controller.${action}()`), `${signal} reaches the page controller`);
assert(/onDraftFieldEdited:[^\n]*root\.controller\.saveDraftField/.test(page));
const code = source.replace(/\/\/.*$/gm, "");

// ── Dropdowns come from the provider properties, never from hard-coded lists ─
assert(
    /priceResolutionSelect[\s\S]*?options:\s*root\.priceResolutionOptions/.test(source),
    "price range options are provider driven"
);
assert(
    /chartResolutionSelect[\s\S]*?options:\s*root\.chartResolutionOptions/.test(source),
    "chart resolution options are provider driven"
);
assert(
    /chartRangeSelect[\s\S]*?options:\s*root\.chartRangeOptions/.test(source),
    "chart range options are provider driven"
);
assert(
    source.includes("selectedHandler ? selectedHandler.priceResolutionOptions() : []"),
    "every question goes to the provider's handler"
);
assert(source.includes("selectedHandler ? selectedHandler.chartResolutionOptions() : []"));
assert(
    source.includes("selectedHandler ? selectedHandler.chartSpanOptions(formState.chartResolution) : []"),
    "chart ranges are filtered by the selected chart resolution"
);
assert(!/value:\s*"(1m|5m|15m|1h|1d|1w|1M|1W|3M|6M|1Y|2Y|5Y|10Y)"/.test(source), "no hard-coded range option lists");

// ── Cascade wiring ───────────────────────────────────────────────────────────
assert(
    /chartRangeSelect[\s\S]*?enabled:\s*root\.formUnlocked && root\.chartRangeAvailable/.test(source),
    "chart range is disabled until it has options"
);
assert(/readonly property bool chartRangeAvailable:\s*chartRangeOptions.length > 0/.test(source));
assert(
    /onSelectedProviderIdChanged:\s*Qt\.callLater\(syncSelections\)/.test(source),
    "provider change re-clamps selections"
);
assert(
    /chartResolutionSelect[\s\S]*?onValueChanged:\s*root\.chartResolutionEdited\(\)/.test(source),
    "resolution change re-filters the chart range"
);
assert(
    /changeResolutionSelect[\s\S]*?options:\s*root\.changeResolutionOptions/.test(source),
    "change resolution options are provider driven"
);
assert(
    /id: changeResolutionSelect[\s\S]*?defaultValue:\s*JsConstants\.DEFAULT_CHANGE_RESOLUTION/.test(source),
    "the change defaults to one day"
);
const order = ["priceResolutionSelect", "changeResolutionSelect", "chartResolutionSelect", "chartRangeSelect"].map(
    (id) => source.indexOf(`id: ${id}`)
);
assert(
    order[0] > 0 && order[0] < order[1] && order[1] < order[2] && order[2] < order[3],
    "dropdown order: price, change, chart resolution, chart range"
);

// ── Only the provider's description is shown for the selected provider (its base URL stays a property, not a link) ──
assert(source.includes("root.selectedProvider.description"));
assert(
    !/selectedProvider\.baseUrl/.test(source) && !/baseUrlMouseArea/.test(source),
    "no provider link in the settings"
);
assert(!/settingsText/.test(source), "the unused settings text is gone");
assert(source.includes("root.selectedProvider.disabledMessage"), "disabled message is still shown");
assert(!source.includes("ProviderSettings"), "per-provider settings panels were removed");

// ── Saved symbol shape ───────────────────────────────────────────────────────
for (const field of [
    "priceResolution:",
    "chartResolution:",
    "chartRange:",
    "ticker:",
    "provider:",
    "showChangeWhenPinned:",
    "invert:",
    "pinned:",
    "uid:"
])
    assert(source.includes(field), `saved symbols store ${field}`);
assert(/storage\.saveDraft\(\{/.test(source), "the form draft is saved by the storage");
assert(!/"_add\w+"/.test(source), "the draft's storage keys live in the constants only");
assert(
    /settingKey: JsConstants\.DRAFT_KEYS\.provider/.test(source) &&
        /settingKey: JsConstants\.DRAFT_KEYS\.invert/.test(source),
    "the controls use the draft keys"
);
assert(!/\n\s+id:\s+ticker,/.test(source), "the ticker is stored as `ticker`, not `id`");
assert(!/symbol\.id\b/.test(source), "the ticker is never read from `id`");
assert(
    !/Contracts\/|SavedSymbol\.create|Selection\.create/.test(source),
    "no JS contracts: symbols are plain current-format data checked by the storage"
);

// ── Defaults come from constants / the provider ──────────────────────────────
assert(/id: chartResolutionSelect[\s\S]*?defaultValue:\s*JsConstants\.DEFAULT_CHART_RESOLUTION/.test(source));
assert(/id: chartRangeSelect[\s\S]*?defaultValue:\s*JsConstants\.DEFAULT_CHART_SPAN/.test(source));
assert(/id: priceResolutionSelect[\s\S]*?defaultValue:\s*JsConstants\.DEFAULT_PRICE_RESOLUTION/.test(source));
assert(editor.includes('import "../../JS/Helpers/Constants.js" as JsConstants'));
assert(!/\|\|\s*"(1m|5m|15m|1h|1d|1w|1M|1W|3M|6M|1Y|2Y|5Y|10Y)"/.test(source), "no range literals as fallbacks");
assert(!/\bdefaultValue:\s*"(1m|5m|15m|1h|1d|1w|1M|1W)"/.test(source), "no range literals as control defaults");
assert(!/providerCredentials|setProviderCredential/.test(source), "dead credential code removed");
assert(
    !/placeholderText: "EUR\/USD"/.test(source) && !/e\.g\., EUR\/USD, Gold/.test(source),
    "no provider-specific display name examples"
);

// The form is filled from one draft object (built by SymbolDraft), not from positional arguments.
assert(/function setDraft\(draft\)/.test(source) && !/setDraftValues/.test(source));
assert(/SymbolDraft\.fromSymbol\(/.test(source) && /SymbolDraft\.empty\(/.test(source));

// ── Resolution vs range validation ───────────────────────────────────────────
assert(
    /chartRangeStatus:\s+selectedHandler \? selectedHandler\.chartRangeStatus\(formState\.chartResolution, formState\.chartRange\)/.test(
        source
    )
);
assert(/visible:[^{}]{0,160}root\.chartRangeStatus\.level === "warn"/.test(source), "note only for warnings");
assert(/text:\s*root\.chartRangeStatus\.message/.test(source), "note shows the rule message");
assert(
    source.indexOf("root.chartRangeStatus.message") > source.indexOf("id: chartRangeSelect"),
    "note sits under the chart range"
);
assert(/color:\s*Theme\.warning/.test(source), "note uses the warning colour");
assert(
    /doSaveSymbol[\s\S]*?chartRangeStatus\(formState\.chartResolution, formState\.chartRange\)[\s\S]*?level === "block"/.test(
        source
    )
);

// ── Show provider name (plugin-wide setting) ─────────────────────────────────
const providerToggle = /ToggleSetting\s*\{[^}]*settingKey:\s*"showProviderName"[^}]*\}/.exec(source);
assert(providerToggle, "provider alias toggle exists");
assert(/defaultValue:\s*true/.test(providerToggle[0]), "provider alias defaults to on");
assert(/label:\s*"Show Provider Alias"/.test(providerToggle[0]), "titled with the alias");
assert(
    /description:[^\n]*three-letter alias/.test(providerToggle[0]) && !/Show Provider Name/.test(source),
    "described with the alias"
);
const rowSettings = ["showTicker", "showPriceChange", "showChartRange", "showProviderName", "showRefreshedSince"].map(
    (settingKey) => source.indexOf(`"${settingKey}"`)
);
assert(
    rowSettings.every((position, index) => position > 0 && (index === 0 || position > rowSettings[index - 1])),
    "grouped with the other symbol row display toggles"
);

// ── Naming ───────────────────────────────────────────────────────────────────
assert(
    /label: "Price Resolution"/.test(source) && !/Price Range/.test(source),
    "the control is called Price Resolution"
);
assert(/settingKey: JsConstants\.DRAFT_KEYS\.priceResolution/.test(source) && !/_addPriceRange/.test(source));
assert(
    !/priceRange|priceInterval|graphInterval|graphResolution|showPriceRange/.test(source),
    "old variable names are gone"
);
assert(/settingKey: "showPriceChange"/.test(source));

// ── Display name hints and symbol validation come from the selected provider ─
assert(
    !/displayName(Placeholder|HelpText)/.test(source),
    "how a symbol is named is the user's choice: no provider text or limits for it"
);
assert(
    /id: nameField[\s\S]*?placeholderText: "Gold"/.test(source) &&
        /\+ JsConstants\.DISPLAY_NAME_MAX_LENGTH \+/.test(source),
    "one generic hint for every provider"
);
assert(
    /tickerValidation:\s+selectedHandler \? selectedHandler\.validateSymbol\(tickerText\)/.test(source),
    "validated against the selected provider"
);
assert(
    /tickerText:\s+\(formState\.ticker \|\| ""\)\.trim\(\)/.test(source),
    "the typed text is trimmed before validation"
);
assert(
    /StyledText\s*\{(?=[^{}]*visible: root\.tickerText !== "" && !root\.tickerValidation\.valid)(?=[^{}]*text: root\.tickerValidation\.message)/.test(
        source
    )
);
assert(/color: Theme\.error/.test(source));
assert(
    /root\.tickerValidation\.valid && root\.nameValidation\.valid/.test(source),
    "the Add button needs a valid symbol and a valid display name"
);
// The display name is validated by SymbolRules.validateName: shown when wrong, blocking on save, and capped while typing.
assert(/nameValidation:\s+SymbolRules\.validateName\(nameText\)/.test(source));
assert(
    /StyledText\s*\{(?=[^{}]*visible: root\.nameText !== "" && !root\.nameValidation\.valid)(?=[^{}]*text: root\.nameValidation\.message)/.test(
        source
    ),
    "the reason is shown under the field"
);
assert(
    /id: nameField[\s\S]*?maximumLength: JsConstants\.DISPLAY_NAME_MAX_LENGTH/.test(source),
    "typing stops at the maximum length"
);
assert(
    /SymbolRules\.validateName\(name\)[\s\S]{0,120}errorRequested\(nameVerdict\.message\)/.test(source),
    "saving a bad name is refused with the reason"
);
assert(
    source.indexOf("tickerValidation.message") > source.indexOf("symbolHelpText"),
    "message sits under the symbol help text"
);

// ── Error handling and storage wiring ────────────────────────────────────────
assert(
    /function _configureErrorHandler\(\) \{[\s\S]*?Logger\.configure\(\{\s*devMode:\s*constants\.devMode\s*\}\)[\s\S]*?ErrorHandler\.configure\(\{[\s\S]*?ToastService\.showError\("Markets: " \+ message, details, "", category\)/.test(
        source
    )
);
assert(/readonly property bool _errorHandlerReady: _configureErrorHandler\(\)/.test(source));
assert(
    source.indexOf("_errorHandlerReady") < source.indexOf("Component.onCompleted"),
    "configured before anything can fail"
);
assert(!/console\./.test(source), "logging goes through the Logger");
assert(!/pluginService\./.test(code), "the settings never call the plugin service themselves");
assert(
    !/root\.saveValue\("symbols"/.test(source) && !/JSON\.(parse|stringify)/.test(code),
    "symbols are saved through the storage only"
);
assert(
    /storage\.upsertSymbol\(symbolsList, entry, editIndex\)/.test(source) &&
        /storage\.removeSymbolAt\(symbolsList, symbolIndex\)/.test(source) &&
        /storage\.moveSymbol\(symbolsList, symbolIndex, direction\)/.test(source) &&
        /storage\.updateSymbolAt\(symbolsList, editIndex/.test(source),
    "edits go through the storage"
);
assert(/function saveValue\(key, value\)\s*\{\s*return storage\.save\(key, value\);?\s*\}/.test(source));

// ── Providers that failed to load are shown ──────────────────────────────────
assert(/readonly property var providerLoadErrors: ProvidersManager\.loadErrors/.test(source));
assert(
    /Repeater\s*\{(?=[\s\S]*?model: root\.providerLoadErrors)[\s\S]*?StyledText\s*\{(?=[^{}]*text: modelData\.userMessage)(?=[^{}]*color: Theme\.error)/.test(
        source
    ),
    "each failure is listed in the error colour"
);

// ── Always the defaults when the page is created ─────────────────────────────
assert(!/loadDraftField\(/.test(source), "what was typed or chosen last time is not brought back");
assert(
    /function _resetFormOnce\(\) \{[\s\S]*?_formReset = true[\s\S]*?Qt\.callLater\(root\.clearForm\)/.test(source),
    "the form is reset once to its defaults"
);
assert(
    /onPluginServiceChanged:[\s\S]*?root\._resetFormOnce\(\)/.test(source) &&
        /if \(pluginService\)\s*_resetFormOnce\(\)/.test(source),
    "…when the service attaches (or is there already)"
);
// ── The popup height shows its value next to the slider ──────────────────────
assert(
    /ValueSliderRow \{\s*id: popoutRowsSetting[\s\S]*?settingKey: "popoutRows"/.test(source) &&
        !/\bSliderSetting \{/.test(source),
    "the popup height uses the slider with a value label"
);
const sliderRow = require("fs").readFileSync(
    require("path").join(__dirname, "../../../src/QML/Views/ValueSliderRow.qml"),
    "utf8"
);
assert(
    /DankSlider \{[\s\S]*?width: sliderRow\.width - root\.valueWidth - sliderRow\.spacing/.test(sliderRow) &&
        /text: root\.value/.test(sliderRow),
    "the value sits to the right of the slider"
);
assert(
    /DankSlider \{[\s\S]*?anchors\.verticalCenter: parent\.verticalCenter[\s\S]*?StyledText \{[\s\S]*?anchors\.verticalCenter: parent\.verticalCenter/.test(
        sliderRow
    ),
    "slider and value are centred on the same line"
);
assert(/valueWidth: Math\.round\(Theme\.fontSizeMedium/.test(sliderRow), "sized from the theme font");

// ── Locked until a valid ticker and name; every dropdown keeps showing what it is set to ──
assert(
    /formUnlocked:\s+tickerValidation\.valid && nameValidation\.valid/.test(source),
    "unlocked by a valid ticker and a valid name"
);
for (const id of [
    "priceResolutionSelect",
    "changeResolutionSelect",
    "chartResolutionSelect",
    "showChangeToggle",
    "invertToggle"
])
    assert(new RegExp(`id: ${id}[^{}]*enabled: root\\.formUnlocked`).test(source), `${id} is locked until then`);
assert(
    !/id: providerSelect[^{}]*enabled:/.test(source),
    "the provider stays choosable (the ticker is validated against it)"
);
assert(
    !/\bSelectionSetting \{/.test(source) && /SelectionRow \{[\s\S]*?id: providerSelect/.test(source),
    "dropdowns are SelectionRow, not DMS's SelectionSetting (whose dropdown stops following its value after a user choice)"
);
assert((source.match(/SelectionRow \{/g) || []).length === 5, "all five dropdowns");
assert(
    /Binding \{[\s\S]*?property: "currentValue"/.test(readSource("QML/Views/SelectionRow.qml")),
    "a Binding keeps the shown text following the value"
);

console.log("Settings static tests passed");
