// Logger.qml - the single place anything is written to the log (QML singleton).
//
// Callers just log: `Logger.debug("scope", "what happened")`. Whether anything is written is decided here,
// once, by dev mode - nothing else checks it. With dev mode off every call returns immediately, so
// messages cost nothing and nothing is printed.
//   • debug(scope, text)   a decision or an outcome worth seeing while developing
//   • error(scope, text)   something went wrong (ErrorHandler logs every handled error here)
// Never put URLs, keys or credentials in a message.
//
// Wiring (once, by the widget and the settings): Logger.configure({ devMode: constants.devMode }).
// The default sink prints "[Markets/<scope>] <text>" with console.info (debug) / console.warn (error): Quickshell
// hides console.log, so a log line written with it would never be seen. Tests replace it with `sink`.
pragma Singleton
import QtQml

QtObject {
    property bool devMode: false
    property var sink: function(level, scope, text) {
        (level === "error" ? console.warn : console.info)("[Markets/" + scope + "]", text)
    }

    // Any of: devMode, sink. Unspecified fields keep their value.
    function configure(settings) {
        var changes = settings || {}
        if (changes.devMode !== undefined) devMode = !!changes.devMode
        if (changes.sink !== undefined)    sink = changes.sink
    }

    // Send a diagnostic message through the configured logging policy.
    function debug(scope, text) { _write("debug", scope, text) }
    // Send a failure message through the configured logging policy.
    function error(scope, text) { _write("error", scope, text) }

    // Write to the configured destination using this service's failure policy.
    function _write(level, scope, text) {
        if (!devMode || !sink) return
        try { sink(level, scope, text) } catch (failure) { /* logging must never break the caller */ }
    }
}
