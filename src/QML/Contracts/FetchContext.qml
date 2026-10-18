// FetchContext.qml - contract: what a pull remembers about itself while a provider call is running.
// It travels with the call (ProviderHandler returns it untouched with the final response).
//
//   uid, ticker, providerId   the symbol the request is for
//   fetchType                 "price" | "graph"      chartRange, chartResolution   what it was built for
import QtQml
import "../../JS/Contracts/FetchType.js" as FetchType

QtObject {
    property string chartRange: ""
    property string chartResolution: ""
    property string fetchType: ""
    readonly property bool fetchTypeValid: FetchType.isValid(fetchType)
    property string providerId: ""
    property string signature: ""     // configuration identity: rejects answers from before a symbol edit
    property string ticker: ""
    property string uid: ""
}
