// ProviderRequest.qml — contract: a ready-to-run provider request.
//
//   url         the https URL (also the last element of `command`)
//   tailLines   when > 0 only the last N lines of the body are kept
//   command     argv for a Process; the URL is always its own argument
//   candles     how many of the newest candles the answer is needed for (the parser builds no more)
import QtQml

QtObject {
    property string url: ""
    property int tailLines: 0
    property var command: []
    property int candles: 0
}
