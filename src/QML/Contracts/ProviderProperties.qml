// ProviderProperties.qml - Typed QML data holder for provider declarations.
// Defaults come from the shared JavaScript base. ProvidersManager validates each declaration before copying it here.
import QtQml
import "../../JS/Contracts/ProviderProperties.js" as Declaration

QtObject {
    property string alias: defaults.alias    // three capital letters, e.g. "YHF": the short form of the name (shown on charts)
    property string authErrorMessage: defaults.authErrorMessage
    property string baseUrl: defaults.baseUrl
    property var changeResolutions: defaults.changeResolutions    // Resolution values the change can be measured against (previous period's close)
    property var chartLimits: defaults.chartLimits    // [{ resolution, maxHistoryDays }], 0 = unlimited
    property string credential: defaults.credential    // the current value, set through the ProviderHandler

    property string credentialErrorSentinel: defaults.credentialErrorSentinel
    property string credentialLabel: defaults.credentialLabel
    property int credentialMaxLength: defaults.credentialMaxLength
    property int credentialMinLength: defaults.credentialMinLength
    property string credentialSettingKey: defaults.credentialSettingKey
    readonly property var defaults: Declaration.create()
    property string description: defaults.description
    property bool disabled: defaults.disabled
    property string disabledMessage: defaults.disabledMessage

    // ── What it can serve ────────────────────────────────────────────────────
    property string minPullResolution: defaults.minPullResolution    // finest refresh rate the provider allows
    property string name: defaults.name
    property var priceResolutions: defaults.priceResolutions    // Resolution values
    // ── Identity ─────────────────────────────────────────────────────────────
    property string providerId: defaults.providerId

    // ── Credential (when the provider needs one) ─────────────────────────────
    property bool requiresCredential: defaults.requiresCredential
    property string symbolFormatMessage: defaults.symbolFormatMessage
    property string symbolHelpText: defaults.symbolHelpText
    property int symbolMaxLength: defaults.symbolMaxLength
    property int symbolMinLength: defaults.symbolMinLength
    property string symbolPattern: defaults.symbolPattern
    property string symbolPlaceholder: defaults.symbolPlaceholder

    // ── Symbols ──────────────────────────────────────────────────────────────
    property string symbolSearchUrl: baseUrl
    property bool tailHistory: defaults.tailHistory    // the fetch keeps only the last N lines of a history answer
}
