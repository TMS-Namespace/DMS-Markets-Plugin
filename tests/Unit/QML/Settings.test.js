// Static wiring checks of Settings.qml (the behaviour is tested in Settings.test.qml on the real runtime).
const { assert, readSource } = require("../../Helpers/Loader");

const source = readSource("QML/Settings.qml");
const code = source.replace(/\/\/.*$/gm, "");

// ── Dropdowns come from the provider properties, never from hard-coded lists ─
assert(/priceResolutionSelect[\s\S]*?options:\s*root\.priceResolutionOptions/.test(source), "price range options are provider driven");
assert(/chartResolutionSelect[\s\S]*?options:\s*root\.chartResolutionOptions/.test(source), "chart resolution options are provider driven");
assert(/chartRangeSelect[\s\S]*?options:\s*root\.chartRangeOptions/.test(source), "chart range options are provider driven");
assert(source.includes("selectedHandler ? selectedHandler.priceResolutionOptions() : []"), "every question goes to the provider's handler");
assert(source.includes("selectedHandler ? selectedHandler.chartResolutionOptions() : []"));
assert(source.includes("selectedHandler ? selectedHandler.chartSpanOptions(chartResolutionSelect.value) : []"), "chart ranges are filtered by the selected chart resolution");
assert(!/value:\s*"(1m|5m|15m|1h|1d|1w|1M|1W|3M|6M|1Y|2Y|5Y|10Y)"/.test(source), "no hard-coded range option lists");

// ── Cascade wiring ───────────────────────────────────────────────────────────
assert(/chartRangeSelect[\s\S]*?enabled:\s*root\.chartRangeAvailable/.test(source), "chart range is disabled until it has options");
assert(source.includes("readonly property bool chartRangeAvailable:    chartRangeOptions.length > 0"));
assert(/onSelectedProviderIdChanged:\s*Qt\.callLater\(syncSelections\)/.test(source), "provider change re-clamps selections");
assert(/chartResolutionSelect[\s\S]*?onValueChanged:\s*Qt\.callLater\(root\.syncSelections\)/.test(source), "resolution change re-filters the chart range");
assert(/changeResolutionSelect[\s\S]*?options:\s*root\.changeResolutionOptions/.test(source), "change resolution options are provider driven");
assert(/id: changeResolutionSelect[\s\S]*?defaultValue:\s*JsK\.DEFAULT_CHANGE_RESOLUTION/.test(source), "the change defaults to one day");
const order = ["priceResolutionSelect", "changeResolutionSelect", "chartResolutionSelect", "chartRangeSelect"].map((id) => source.indexOf(`id: ${id}`));
assert(order[0] > 0 && order[0] < order[1] && order[1] < order[2] && order[2] < order[3], "dropdown order: price, change, chart resolution, chart range");

// ── Provider description and base URL are shown for the selected provider ────
assert(source.includes("root.selectedProvider.description") && source.includes("root.selectedProvider.baseUrl"));
assert(/Qt\.openUrlExternally\(root\.selectedProvider\.baseUrl\)/.test(source), "base URL opens in the browser");
assert(source.includes("root.selectedProvider.disabledMessage"), "disabled message is still shown");
assert(!source.includes("ProviderSettings"), "per-provider settings panels were removed");

// ── Saved symbol shape ───────────────────────────────────────────────────────
for (const field of ["priceResolution:", "chartResolution:", "chartRange:", "ticker:", "provider:", "showChangeWhenPinned:", "invert:", "pinned:", "uid:"])
    assert(source.includes(field), `saved symbols store ${field}`);
assert(/storage\.saveDraft\(\{/.test(source), "the form draft is saved by the storage");
assert(!/"_add\w+"/.test(source), "the draft's storage keys live in the constants only");
assert(/settingKey: JsK\.DRAFT_KEYS\.provider/.test(source) && /settingKey: JsK\.DRAFT_KEYS\.invert/.test(source), "the controls use the draft keys");
assert(!/\n\s+id:\s+ticker,/.test(source), "the ticker is stored as `ticker`, not `id`");
assert(!/symbol\.id\b/.test(source), "the ticker is never read from `id`");
assert(!/Contracts\/|SavedSymbol\.create|Selection\.create/.test(source), "no JS contracts: symbols are plain current-format data checked by the storage");

// ── Defaults come from constants / the provider ──────────────────────────────
assert(/id: chartResolutionSelect[\s\S]*?defaultValue:\s*JsK\.DEFAULT_CHART_RESOLUTION/.test(source));
assert(/id: chartRangeSelect[\s\S]*?defaultValue:\s*JsK\.DEFAULT_CHART_SPAN/.test(source));
assert(/id: priceResolutionSelect[\s\S]*?defaultValue:\s*JsK\.DEFAULT_PRICE_RESOLUTION/.test(source));
assert(source.includes('import "../JS/Helpers/Constants.js" as JsK'));
assert(!/\|\|\s*"(1m|5m|15m|1h|1d|1w|1M|1W|3M|6M|1Y|2Y|5Y|10Y)"/.test(source), "no range literals as fallbacks");
assert(!/\bdefaultValue:\s*"(1m|5m|15m|1h|1d|1w|1M|1W)"/.test(source), "no range literals as control defaults");
assert(!/providerCredentials|setProviderCredential/.test(source), "dead credential code removed");
assert(!/placeholderText: "EUR\/USD"/.test(source) && !/e\.g\., EUR\/USD, Gold/.test(source), "no provider-specific display name examples");

// The form is filled from one draft object (built by SymbolDraft), not from positional arguments.
assert(/function setDraft\(draft\)/.test(source) && !/setDraftValues/.test(source));
assert(/SymbolDraft\.fromSymbol\(/.test(source) && /SymbolDraft\.empty\(/.test(source));

// ── Resolution vs range validation ───────────────────────────────────────────
assert(/chartRangeStatus:\s+selectedHandler \? selectedHandler\.chartRangeStatus\(chartResolutionSelect\.value, chartRangeSelect\.value\)/.test(source));
assert(/visible:[^{}]{0,160}root\.chartRangeStatus\.level === "warn"/.test(source), "note only for warnings");
assert(/text:\s*root\.chartRangeStatus\.message/.test(source), "note shows the rule message");
assert(source.indexOf("root.chartRangeStatus.message") > source.indexOf("id: chartRangeSelect"), "note sits under the chart range");
assert(/color:\s*Theme\.warning/.test(source), "note uses the warning colour");
assert(/doSaveSymbol[\s\S]*?chartRangeStatus\(chartResolutionSelect\.value, chartRangeSelect\.value\)[\s\S]*?level === "block"/.test(source));

// ── Show provider name (plugin-wide setting) ─────────────────────────────────
assert(/ToggleSetting\s*\{[^}]*settingKey:\s*"showProviderName"[^}]*defaultValue:\s*true/.test(source), "toggle exists and defaults to on");
assert(/"showProviderName"[\s\S]{0,200}Show Provider Name/.test(source));
const rowSettings = ["showTicker", "showPriceChange", "showChartRange", "showProviderName", "showRefreshedSince"].map((settingKey) => source.indexOf(`"${settingKey}"`));
assert(rowSettings.every((position, index) => position > 0 && (index === 0 || position > rowSettings[index - 1])), "grouped with the other symbol row display toggles");

// ── Naming ───────────────────────────────────────────────────────────────────
assert(/label: "Price Resolution"/.test(source) && !/Price Range/.test(source), "the control is called Price Resolution");
assert(/settingKey: JsK\.DRAFT_KEYS\.priceResolution/.test(source) && !/_addPriceRange/.test(source));
assert(!/priceRange|priceInterval|graphInterval|graphResolution|showPriceRange/.test(source), "old variable names are gone");
assert(/settingKey: "showPriceChange"/.test(source));

// ── Display name hints and symbol validation come from the selected provider ─
assert(/placeholderText:\s*root\.selectedProvider\.displayNamePlaceholder/.test(source));
assert(/root\.selectedProvider\.displayNameHelpText/.test(source));
assert(/tickerValidation:\s+selectedHandler \? selectedHandler\.validateSymbol\(tickerText\)/.test(source), "validated against the selected provider");
assert(/tickerText:\s+\(tickerInput\.value \|\| ""\)\.trim\(\)/.test(source), "the typed text is trimmed before validation");
assert(/visible: root\.tickerText !== "" && !root\.tickerValidation\.valid[\s\S]{0,80}text: root\.tickerValidation\.message/.test(source));
assert(/color: Theme\.error/.test(source));
assert(/root\.tickerValidation\.valid && displayName !== ""/.test(source), "the Add button needs a valid symbol");
assert(source.indexOf("tickerValidation.message") > source.indexOf("symbolHelpText"), "message sits under the symbol help text");

// ── Error handling and storage wiring ────────────────────────────────────────
assert(/function _configureErrorHandler\(\) \{[\s\S]*?Logger\.configure\(\{ devMode: constants\.devMode \}\)[\s\S]*?ErrorHandler\.configure\(\{[\s\S]*?ToastService\.showError\("Markets: " \+ message, details, "", category\)/.test(source));
assert(/readonly property bool _errorHandlerReady: _configureErrorHandler\(\)/.test(source));
assert(source.indexOf("_errorHandlerReady") < source.indexOf("Component.onCompleted"), "configured before anything can fail");
assert(!/console\./.test(source), "logging goes through the Logger");
assert(!/pluginService\./.test(code), "the settings never call the plugin service themselves");
assert(!/root\.saveValue\("symbols"/.test(source) && !/JSON\.(parse|stringify)/.test(code), "symbols are saved through the storage only");
assert(/storage\.upsertSymbol\(symbolsList, entry, editIndex\)/.test(source) && /storage\.removeSymbolAt\(symbolsList, symbolIndex\)/.test(source)
       && /storage\.moveSymbol\(symbolsList, symbolIndex, direction\)/.test(source) && /storage\.updateSymbolAt\(symbolsList, editIndex/.test(source), "edits go through the storage");
assert(/function saveValue\(key, value\) \{ return storage\.save\(key, value\) \}/.test(source));

// ── Providers that failed to load are shown ──────────────────────────────────
assert(/readonly property var providerLoadErrors: ProvidersManager\.loadErrors/.test(source));
assert(/model: root\.providerLoadErrors[\s\S]{0,200}text: modelData\.userMessage[\s\S]{0,200}color: Theme\.error/.test(source), "each failure is listed in the error colour");

console.log("Settings static tests passed");
