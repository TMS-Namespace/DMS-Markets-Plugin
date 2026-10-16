// WiseProperties.js - Wise anonymous FX rates: what it declares (see below).
//
// Verified limits (live API): resolution is only hourly|daily; hourly reaches 30 days back, daily
// 5 years (60 months); there is no weekly/monthly.
//
// Declares what the provider is and can serve: names, texts, URLs, symbol rules, credential details,
// price resolutions and chart history limits. Plain data (ProvidersManager turns it into a
// ProviderProperties contract and checks it with ProviderRules.assertDeclaration); requests and answers
// are WiseApi.js.

.pragma library
.import "WiseConstants.js" as K
.import "../../Contracts/Resolution.js" as Resolution

var ResolutionValues = Resolution.Values

function create() {
    return {
        providerId: K.WISE_PROVIDER_ID,
        name: K.WISE_NAME,
        alias: K.WISE_ALIAS,
        description: K.WISE_DESCRIPTION,
        baseUrl: K.WISE_BASE_URL,
        symbolSearchUrl: K.WISE_SYMBOL_SEARCH_URL,
        symbolHelpText: K.WISE_SYMBOL_HELP_TEXT,
        symbolPlaceholder: K.WISE_SYMBOL_PLACEHOLDER,
        symbolPattern: K.WISE_SYMBOL_PATTERN,
        symbolMinLength: K.WISE_SYMBOL_MIN_LENGTH,
        symbolMaxLength: K.WISE_SYMBOL_MAX_LENGTH,
        symbolFormatMessage: K.WISE_SYMBOL_FORMAT_MESSAGE,
        minPullResolution: ResolutionValues.H1,
        changeResolutions: [ResolutionValues.H1, ResolutionValues.D1],
        priceResolutions: [ResolutionValues.H1, ResolutionValues.D1],
        chartLimits: [
            { resolution: ResolutionValues.H1, maxHistoryDays: K.WISE_HOURLY_MAX_DAYS },
            { resolution: ResolutionValues.D1, maxHistoryDays: K.WISE_DAILY_MAX_DAYS }
        ]
    }
}
