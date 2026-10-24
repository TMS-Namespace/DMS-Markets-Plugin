// StooqProperties.js - Stooq CSV quotes (currently disabled): what it declares (see below).
//
// Disabled, so its capabilities are placeholders (daily and coarser candles, as the old code served),
// not measured.
//
// Declares what the provider is and can serve: names, texts, URLs, symbol rules, credential details,
// price resolutions and chart history limits. Plain data (ProvidersManager turns it into a
// ProviderProperties contract and checks it with ProviderRules.assertDeclaration); requests and answers
// are StooqApi.js.

.pragma library
.import "../../Contracts/ProviderProperties.js" as Base
.import "StooqConstants.js" as ProviderConstants
.import "../../Contracts/Resolution.js" as Resolution
var ResolutionValues = Resolution.Values;

// Return this provider's declared settings and supported data ranges.
var StooqProperties = class StooqProperties extends Base.ProviderProperties {
    // Supply this provider's declared capabilities over the shared defaults.
    constructor() {
        super({
            providerId: ProviderConstants.STOOQ_PROVIDER_ID,
            name: ProviderConstants.STOOQ_NAME,
            alias: ProviderConstants.STOOQ_ALIAS,
            description: ProviderConstants.STOOQ_DESCRIPTION,
            baseUrl: ProviderConstants.STOOQ_BASE_URL,
            disabled: true,
            disabledMessage: ProviderConstants.STOOQ_DISABLED_MESSAGE,
            symbolSearchUrl: ProviderConstants.STOOQ_SYMBOL_SEARCH_URL,
            symbolHelpText: ProviderConstants.STOOQ_SYMBOL_HELP_TEXT,
            symbolPlaceholder: ProviderConstants.STOOQ_SYMBOL_PLACEHOLDER,
            symbolPattern: ProviderConstants.STOOQ_SYMBOL_PATTERN,
            symbolMinLength: ProviderConstants.STOOQ_SYMBOL_MIN_LENGTH,
            symbolMaxLength: ProviderConstants.STOOQ_SYMBOL_MAX_LENGTH,
            symbolFormatMessage: ProviderConstants.STOOQ_SYMBOL_FORMAT_MESSAGE,
            requiresCredential: true,
            credentialSettingKey: ProviderConstants.STOOQ_CREDENTIAL_SETTING_KEY,
            credentialLabel: ProviderConstants.STOOQ_CREDENTIAL_LABEL,
            credentialMinLength: ProviderConstants.STOOQ_CREDENTIAL_MIN_LENGTH,
            credentialMaxLength: ProviderConstants.STOOQ_CREDENTIAL_MAX_LENGTH,
            credentialErrorSentinel: ProviderConstants.STOOQ_CREDENTIAL_ERROR_SENTINEL,
            authErrorMessage: ProviderConstants.STOOQ_AUTH_ERROR_MESSAGE,
            minPullResolution: ResolutionValues.D1,
            changeResolutions: [ResolutionValues.D1, ResolutionValues.W1, ResolutionValues.MO1],
            priceResolutions: [ResolutionValues.D1, ResolutionValues.W1, ResolutionValues.MO1],
            chartLimits: [
                { resolution: ResolutionValues.D1, maxHistoryDays: 0 },
                { resolution: ResolutionValues.W1, maxHistoryDays: 0 },
                { resolution: ResolutionValues.MO1, maxHistoryDays: 0 }
            ],
            tailHistory: true
        });
    }
};

// Create the provider declaration expected by ProvidersManager.
function create() {
    return new StooqProperties();
}
