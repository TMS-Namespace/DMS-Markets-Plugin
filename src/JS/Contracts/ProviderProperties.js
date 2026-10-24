// ProviderProperties.js - Base declaration of the fields QML expects, including their common defaults.
// Provider subclasses pass their declared values to super(); ProviderRules checks cross-field constraints.
.pragma library

// Extend this class in each provider's Properties.js; arrays belong to each instance.
var ProviderProperties = class ProviderProperties {
    // Apply a provider declaration over the shared defaults, without sharing mutable instance data.
    constructor(values) {
        // three capital letters, e.g. "YHF": the short form of the name (shown on charts)
        this.alias = "";
        this.authErrorMessage = "";
        this.baseUrl = "";
        // Resolution values the change can be measured against (previous period's close)
        this.changeResolutions = [];
        // [{ resolution, maxHistoryDays }], 0 = unlimited
        this.chartLimits = [];
        // the current value, set through the ProviderHandler
        this.credential = "";
        this.credentialErrorSentinel = "";
        this.credentialLabel = "";
        this.credentialMaxLength = 0;
        this.credentialMinLength = 1;
        this.credentialSettingKey = "";
        this.description = "";
        this.disabled = false;
        this.disabledMessage = "";
        // finest refresh rate the provider allows
        this.minPullResolution = "1d";
        this.name = "";
        // Resolution values
        this.priceResolutions = [];
        this.providerId = "";
        this.requiresCredential = false;
        this.symbolFormatMessage = "";
        this.symbolHelpText = "Provider-specific symbol";
        this.symbolMaxLength = 1;
        this.symbolMinLength = 1;
        this.symbolPattern = "";
        this.symbolPlaceholder = "";
        this.symbolSearchUrl = "";
        // the fetch keeps only the last N lines of a history answer
        this.tailHistory = false;
        Object.assign(this, values || {});
        if (!this.symbolSearchUrl) this.symbolSearchUrl = this.baseUrl;
    }
};

// Expose the common defaults to QML without requiring class metadata from the language server.
function create() {
    return new ProviderProperties();
}
