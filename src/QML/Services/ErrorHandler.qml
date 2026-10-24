// ErrorHandler.qml - the single place where errors are caught, logged and shown (QML singleton).
//
// JS modules throw PluginError and never touch the UI. QML layers catch and hand the error to
// `handle`, which
//   1. turns any thrown value into a PluginError (users only ever see `userMessage`),
//   2. logs it through Logger (which writes only in dev mode),
//   3. remembers it (bounded list, `recent`),
//   4. notifies the user through `notifier` (DMS ToastService), rate limited so a failing
//      provider cannot spam toasts.
// Nothing here swallows an error silently: whatever is not shown is still recorded and logged
// (Logger decides whether dev mode lets it through). What to do with an error is ErrorPolicy.js; this object only holds the state.
//
// Wiring (once, from QML):
//   ErrorHandler.configure({ notify: function(userMessage, details, category) { ToastService.showError(...) } })
pragma Singleton
import QtQml
import "../../JS/Helpers/Constants.js" as Constants
import "../../JS/Helpers/ErrorPolicy.js" as Policy
import "../../JS/Helpers/Helpers.js" as Helpers
import "../Contracts"

QtObject {
    id: root

    property Component _guardType: Component {
        GuardResult {
        }
    }
    property Component _recordType: Component {
        ErrorRecord {
        }
    }
    property var clock: function () {
        return Date.now();
    }
    property var lastNotified: ({})
    property var notifier: null            // function(userMessage, details, category)
    property var recent: []                // ErrorRecord, oldest first, bounded

    signal handled(var record)

    // Apply the cooldown before calling the configured notifier.
    function _notifyUser(record, category) {
        if (!notifier || !Policy.shouldNotify(lastNotified, record, Constants.ERROR_NOTIFY_COOLDOWN_MS))
            return;
        lastNotified = Helpers.withEntry(lastNotified, Policy.notifyKey(record), record.time);
        try {
            notifier(record.userMessage, record.details, "markets-" + (category || record.code));
        } catch (caughtError) {
            Logger.error("ErrorHandler", "notifier failed: " + (caughtError && caughtError.message));
        }
    }

    // Any of: notify, now. Unspecified fields keep their value.
    function configure(options) {
        let settings = options || {};
        if (settings.notify !== undefined)
            notifier = settings.notify;
        if (settings.now !== undefined)
            clock = settings.now;
    }

    // Runs fn; on a throw, handles the error. Returns a GuardResult.
    function guard(scope, action, options) {
        try {
            return _guardType.createObject(null, {
                ok: true,
                value: action()
            });
        } catch (caughtError) {
            return _guardType.createObject(null, {
                ok: false,
                error: handle(scope, caughtError, options)
            });
        }
    }

    // Returns the ErrorRecord. options:
    //   notify   false to record/log without a toast (e.g. the card already shows it)
    //   context  short text added to the details (e.g. the ticker)
    //   category toast category (defaults to the error code)
    function handle(scope, error, options) {
        let handling = options || {};
        let made = Policy.recordOf(scope, error, handling.context, clock());
        let record = _recordType.createObject(null, made.fields) as ErrorRecord;

        let next = recent.slice();
        next.push(record);
        // A symbol may still display an evicted record. Leave its lifetime to JS ownership:
        // it is collected once neither diagnostics nor a symbol holds it.
        if (next.length > Constants.RECENT_ERRORS_MAX)
            next.shift();
        recent = next;

        Logger.error(record.scope, "[" + record.code + "] " + made.error.message + (handling.context ? " (" + handling.context + ")" : "") + (made.error.stack ? "\n" + made.error.stack : ""));

        if (handling.notify !== false)
            _notifyUser(record, handling.category);
        handled(record);
        return record;
    }

    // Clear recorded errors and notification configuration.
    function reset() {
        notifier = null;
        clock = function () {
            return Date.now();
        };
        recent = [];
        lastNotified = ({});
    }

    // Allow only transient failures within the retry budget.
    function shouldRetry(error, attempt, maxRetries) {
        return Policy.shouldRetry(error, attempt, maxRetries);
    }
}
