// StooqProperties.js — Stooq CSV quotes (currently disabled): what it declares (see below).
//
// Disabled, so its capabilities are placeholders (daily and coarser candles, as the old code served),
// not measured.
//
// Declares what the provider is and can serve: names, texts, URLs, symbol rules, credential details,
// price resolutions and chart history limits. Plain data (ProvidersManager turns it into a
// ProviderProperties contract and checks it with ProviderRules.assertDeclaration); requests and answers
// are StooqApi.js.

.pragma library
.import "StooqConstants.js" as K
.import "../../Contracts/Resolution.js" as Resolution

var ResolutionValues = Resolution.Values

function create() {
    return {
        providerId: K.STOOQ_PROVIDER_ID,
        name: K.STOOQ_NAME,
        description: K.STOOQ_DESCRIPTION,
        baseUrl: K.STOOQ_BASE_URL,
        settingsText: K.STOOQ_SETTINGS_TEXT,
        disabled: true,
        disabledMessage: K.STOOQ_DISABLED_MESSAGE,
        symbolSearchUrl: K.STOOQ_SYMBOL_SEARCH_URL,
        symbolHelpText: K.STOOQ_SYMBOL_HELP_TEXT,
        symbolPlaceholder: K.STOOQ_SYMBOL_PLACEHOLDER,
        symbolPattern: K.STOOQ_SYMBOL_PATTERN,
        symbolMinLength: K.STOOQ_SYMBOL_MIN_LENGTH,
        symbolMaxLength: K.STOOQ_SYMBOL_MAX_LENGTH,
        symbolFormatMessage: K.STOOQ_SYMBOL_FORMAT_MESSAGE,
        displayNamePlaceholder: K.STOOQ_DISPLAY_NAME_PLACEHOLDER,
        displayNameHelpText: K.STOOQ_DISPLAY_NAME_HELP_TEXT,
        requiresCredential: true,
        credentialSettingKey: K.STOOQ_CREDENTIAL_SETTING_KEY,
        credentialLabel: K.STOOQ_CREDENTIAL_LABEL,
        credentialPlaceholder: K.STOOQ_CREDENTIAL_PLACEHOLDER,
        credentialMinLength: K.STOOQ_CREDENTIAL_MIN_LENGTH,
        credentialMaxLength: K.STOOQ_CREDENTIAL_MAX_LENGTH,
        credentialHelpTitle: K.STOOQ_CREDENTIAL_HELP_TITLE,
        credentialHelpText: K.STOOQ_CREDENTIAL_HELP_TEXT,
        credentialErrorSentinel: K.STOOQ_CREDENTIAL_ERROR_SENTINEL,
        authErrorMessage: K.STOOQ_AUTH_ERROR_MESSAGE,
        minPullResolution: ResolutionValues.D1,
        changeResolutions: [ResolutionValues.D1, ResolutionValues.W1, ResolutionValues.MO1],
        priceResolutions: [ResolutionValues.D1, ResolutionValues.W1, ResolutionValues.MO1],
        chartLimits: [
            { resolution: ResolutionValues.D1,  maxHistoryDays: 0 },
            { resolution: ResolutionValues.W1,  maxHistoryDays: 0 },
            { resolution: ResolutionValues.MO1, maxHistoryDays: 0 }
        ],
        tailHistory: true
    }
}
