// YahooProperties.js - Yahoo Finance: what it declares (see below).
//
// Limits measured against the live chart API: 1m ≤ 7 days, 5m/15m ≤ 60 days, 1h ≤ 730 days,
// daily/weekly/monthly unlimited.
//
// Declares what the provider is and can serve: names, texts, URLs, symbol rules, credential details,
// price resolutions and chart history limits. Plain data (ProvidersManager turns it into a
// ProviderProperties contract and checks it with ProviderRules.assertDeclaration); requests and answers
// are YahooApi.js.

.pragma library
.import "YahooConstants.js" as K
.import "../../Contracts/Resolution.js" as Resolution

var ResolutionValues = Resolution.Values

function create() {
    return {
        providerId: K.YAHOO_PROVIDER_ID,
        name: K.YAHOO_NAME,
        alias: K.YAHOO_ALIAS,
        description: K.YAHOO_DESCRIPTION,
        baseUrl: K.YAHOO_BASE_URL,
        symbolSearchUrl: K.YAHOO_LOOKUP_URL,
        symbolHelpText: K.YAHOO_SYMBOL_HELP_TEXT,
        symbolPlaceholder: K.YAHOO_SYMBOL_PLACEHOLDER,
        symbolPattern: K.YAHOO_SYMBOL_PATTERN,
        symbolMinLength: K.YAHOO_SYMBOL_MIN_LENGTH,
        symbolMaxLength: K.YAHOO_SYMBOL_MAX_LENGTH,
        symbolFormatMessage: K.YAHOO_SYMBOL_FORMAT_MESSAGE,
        minPullResolution: ResolutionValues.M1,
        changeResolutions: [ResolutionValues.H1, ResolutionValues.D1, ResolutionValues.W1, ResolutionValues.MO1],
        priceResolutions: [ResolutionValues.M1, ResolutionValues.M5, ResolutionValues.M15, ResolutionValues.H1,
            ResolutionValues.D1, ResolutionValues.W1, ResolutionValues.MO1],
        chartLimits: [
            { resolution: ResolutionValues.M1,  maxHistoryDays: 7 },
            { resolution: ResolutionValues.M5,  maxHistoryDays: 60 },
            { resolution: ResolutionValues.M15, maxHistoryDays: 60 },
            { resolution: ResolutionValues.H1,  maxHistoryDays: 730 },
            { resolution: ResolutionValues.D1,  maxHistoryDays: 0 },
            { resolution: ResolutionValues.W1,  maxHistoryDays: 0 },
            { resolution: ResolutionValues.MO1, maxHistoryDays: 0 }
        ]
    }
}
