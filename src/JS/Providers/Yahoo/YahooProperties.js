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
.import "../../Contracts/ProviderProperties.js" as Base
.import "YahooConstants.js" as ProviderConstants
.import "../../Contracts/Resolution.js" as Resolution
var ResolutionValues = Resolution.Values;

// Return this provider's declared settings and supported data ranges.
var YahooProperties = class YahooProperties extends Base.ProviderProperties {
    // Supply this provider's declared capabilities over the shared defaults.
    constructor() {
        super({
            providerId: ProviderConstants.YAHOO_PROVIDER_ID,
            name: ProviderConstants.YAHOO_NAME,
            alias: ProviderConstants.YAHOO_ALIAS,
            description: ProviderConstants.YAHOO_DESCRIPTION,
            baseUrl: ProviderConstants.YAHOO_BASE_URL,
            symbolSearchUrl: ProviderConstants.YAHOO_LOOKUP_URL,
            symbolHelpText: ProviderConstants.YAHOO_SYMBOL_HELP_TEXT,
            symbolPlaceholder: ProviderConstants.YAHOO_SYMBOL_PLACEHOLDER,
            symbolPattern: ProviderConstants.YAHOO_SYMBOL_PATTERN,
            symbolMinLength: ProviderConstants.YAHOO_SYMBOL_MIN_LENGTH,
            symbolMaxLength: ProviderConstants.YAHOO_SYMBOL_MAX_LENGTH,
            symbolFormatMessage: ProviderConstants.YAHOO_SYMBOL_FORMAT_MESSAGE,
            minPullResolution: ResolutionValues.M1,
            changeResolutions: [ResolutionValues.H1, ResolutionValues.D1, ResolutionValues.W1, ResolutionValues.MO1],
            priceResolutions: [
                ResolutionValues.M1,
                ResolutionValues.M5,
                ResolutionValues.M15,
                ResolutionValues.H1,
                ResolutionValues.D1,
                ResolutionValues.W1,
                ResolutionValues.MO1
            ],
            chartLimits: [
                { resolution: ResolutionValues.M1, maxHistoryDays: 7 },
                { resolution: ResolutionValues.M5, maxHistoryDays: 60 },
                { resolution: ResolutionValues.M15, maxHistoryDays: 60 },
                { resolution: ResolutionValues.H1, maxHistoryDays: 730 },
                { resolution: ResolutionValues.D1, maxHistoryDays: 0 },
                { resolution: ResolutionValues.W1, maxHistoryDays: 0 },
                { resolution: ResolutionValues.MO1, maxHistoryDays: 0 }
            ]
        });
    }
};

// Create the provider declaration expected by ProvidersManager.
function create() {
    return new YahooProperties();
}
