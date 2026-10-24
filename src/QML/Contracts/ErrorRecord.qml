// ErrorRecord.qml - contract: one handled error, as ErrorHandler records it and the UI shows it.
//
//   scope        where it happened ("fetcher", "storage", …)    code   PluginError.Code
//   userMessage  short and friendly: the only text users see     details   technical detail for the log
//   retryable    whether the failure is transient                 status    HTTP status, else 0
//   time         epoch ms when it was handled
import QtQml

QtObject {
    property string code: ""
    property string details: ""
    property bool retryable: false
    property string scope: ""
    property int status: 0
    property real time: 0
    property string userMessage: ""
}
