// ProviderProperties.qml - contract: what a provider declares about itself (read by the settings, the
// logic modules and the catalog). A data holder: each provider's values are written once, as plain data,
// in its own folder (JS/Providers/<Name>/<Name>Properties.js), and checked as a whole by
// ProviderRules.assertDeclaration before this object is created.
import QtQml

QtObject {
    // ── Identity ─────────────────────────────────────────────────────────────
    property string providerId: ""
    property string name: ""
    property string alias: ""        // three capital letters, e.g. "YHF": the short form of the name (shown on charts)
    property string description: ""
    property string baseUrl: ""
    property bool disabled: false
    property string disabledMessage: ""

    // ── Symbols ──────────────────────────────────────────────────────────────
    property string symbolSearchUrl: baseUrl
    property string symbolHelpText: "Provider-specific symbol"
    property string symbolPlaceholder: ""
    property string symbolPattern: ""
    property int symbolMinLength: 1
    property int symbolMaxLength: 1
    property string symbolFormatMessage: ""

    // ── Credential (when the provider needs one) ─────────────────────────────
    property bool requiresCredential: false
    property string credentialSettingKey: ""
    property string credentialLabel: ""
    property string credentialPlaceholder: ""
    property int credentialMinLength: 1
    property int credentialMaxLength: 0
    property string credentialHelpTitle: ""
    property string credentialHelpText: ""
    property string credentialErrorSentinel: ""
    property string authErrorMessage: ""
    property string credential: ""            // the current value, set through the ProviderHandler

    // ── What it can serve ────────────────────────────────────────────────────
    property string minPullResolution: "1d"   // finest refresh rate the provider allows
    property var priceResolutions: []         // Resolution values
    property var changeResolutions: []        // Resolution values the change can be measured against (previous period's close)
    property var chartLimits: []              // [{ resolution, maxHistoryDays }], 0 = unlimited
    property bool tailHistory: false          // the fetch keeps only the last N lines of a history answer
}
