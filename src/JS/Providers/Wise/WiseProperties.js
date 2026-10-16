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
.import "WiseConstants.js" as ProviderConstants
.import "../../Contracts/Resolution.js" as Resolution

var ResolutionValues = Resolution.Values

// Return this provider's declared settings and supported data ranges.
function create() {
    return {
        providerId: ProviderConstants.WISE_PROVIDER_ID,
        name: ProviderConstants.WISE_NAME,
        alias: ProviderConstants.WISE_ALIAS,
        description: ProviderConstants.WISE_DESCRIPTION,
        baseUrl: ProviderConstants.WISE_BASE_URL,
        symbolSearchUrl: ProviderConstants.WISE_SYMBOL_SEARCH_URL,
        symbolHelpText: ProviderConstants.WISE_SYMBOL_HELP_TEXT,
        symbolPlaceholder: ProviderConstants.WISE_SYMBOL_PLACEHOLDER,
        symbolPattern: ProviderConstants.WISE_SYMBOL_PATTERN,
        symbolMinLength: ProviderConstants.WISE_SYMBOL_MIN_LENGTH,
        symbolMaxLength: ProviderConstants.WISE_SYMBOL_MAX_LENGTH,
        symbolFormatMessage: ProviderConstants.WISE_SYMBOL_FORMAT_MESSAGE,
        minPullResolution: ResolutionValues.H1,
        changeResolutions: [ResolutionValues.H1, ResolutionValues.D1],
        priceResolutions: [ResolutionValues.H1, ResolutionValues.D1],
        chartLimits: [
            { resolution: ResolutionValues.H1, maxHistoryDays: ProviderConstants.WISE_HOURLY_MAX_DAYS },
            { resolution: ResolutionValues.D1, maxHistoryDays: ProviderConstants.WISE_DAILY_MAX_DAYS }
        ]
    }
}
