// FetchContext.qml - contract: what a pull remembers about itself while a provider call is running.
// It travels with the call (ProviderHandler returns it untouched with the final response).
//
//   uid, ticker, providerId   the symbol the request is for
//   fetchType                 "price" | "graph"      chartRange, chartResolution   what it was built for
import QtQml
import "../../JS/Contracts/FetchType.js" as FetchType

QtObject {
    property string uid: ""
    property string ticker: ""
    property string providerId: ""
    property string fetchType: ""
    property string signature: ""     // configuration identity: rejects answers from before a symbol edit
    property string chartRange: ""
    property string chartResolution: ""

    readonly property bool fetchTypeValid: FetchType.isValid(fetchType)
}
