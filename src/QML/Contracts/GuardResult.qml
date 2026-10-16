// GuardResult.qml - contract: the outcome of running something under ErrorHandler.guard.
//
//   ok      boolean       value   what the function returned (undefined on failure)
//   error   null on success, otherwise the ErrorRecord of the failure
import QtQml

QtObject {
    property bool ok: false
    property var value: undefined
    property var error: null
}
