// ProviderResponse.qml — contract: the unified result of calling a provider's web API.
//
//   providerId   provider that was called       ok      true when `body` holds the answer
//   status       HTTP status when known, else 0  body    response text ("" when there was none)
//   error        null on success, otherwise a PluginError (friendly userMessage, `retryable`)
// ResponseInterpreter builds the data; failures can never be mistaken for data because the
// parsing side refuses anything with ok === false.
import QtQml

QtObject {
    property string providerId: ""
    property bool ok: false
    property int status: 0
    property string body: ""
    property var error: null
}
