// FetchCall.qml - contract: one call handed to ProviderHandler.
//
//   key          identifies this exact call; a call whose key is already in flight is refused
//   group        what the "refreshing…" state is counted for (the symbol's uid)
//   command      argv to run (ProviderRequest.command)
//   candles      how many of the newest candles to parse from the answer (ProviderRequest.candles)
//   isCurrent    function(context) → false once nobody waits for the result any more (optional)
//   context      FetchContext, returned untouched with the final response
import QtQml

QtObject {
    property string key: ""
    property string group: ""
    property var command: []
    property int candles: 0
    property var context: null
    property var isCurrent: null
}
