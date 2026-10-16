// ErrorRecord.qml — contract: one handled error, as ErrorHandler records it and the UI shows it.
//
//   scope        where it happened ("fetcher", "storage", …)    code   PluginError.Code
//   userMessage  short and friendly: the only text users see     details   technical detail for the log
//   retryable    whether the failure is transient                 status    HTTP status, else 0
//   time         epoch ms when it was handled
import QtQml

QtObject {
    property string scope: ""
    property string code: ""
    property string userMessage: ""
    property string details: ""
    property bool retryable: false
    property int status: 0
    property real time: 0
}
