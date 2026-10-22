import QtQml
import "../../../../src/JS/Contracts/PluginError.js" as PluginError
import "../../../../src/QML/Services"
import "../../../Helpers"

TestSuite {
    property var heldRecord: null
    property var logs: []
    property real now: 1000
    property var toasts: []

    function async_evicted_records_still_held_by_a_symbol_remain_usable(done) {
        heldRecord = ErrorHandler.handle("fetcher", new PluginError.PluginError("network", "Saved failure", "detail"), {
            notify: false
        });
        for (let i = 0; i < 500; i++)
            ErrorHandler.handle("other", new Error("other failure"), {
                notify: false
            });
        // QObject destruction is deferred until the event loop runs.
        Qt.callLater(function () {
            done(heldRecord && heldRecord.userMessage === "Saved failure" ? "" : "eviction destroyed a record still displayed by a symbol");
            heldRecord = null;
        });
    }
    function setup() {
        ErrorHandler.reset();
        Logger.configure({
            isDevMode: false
        });
        toasts = [];
        logs = [];
        now = 1000;
        Logger.configure({
            isDevMode: true,
            sink: function (level, scope, text) {
                logs.push([level, scope, text]);
            }
        });
        ErrorHandler.configure({
            notify: function (message, details, category) {
                toasts.push([message, details, category]);
            },
            now: function () {
                return now;
            }
        });
    }
    function test_a_failing_notifier_never_breaks_handling() {
        ErrorHandler.configure({
            notify: function () {
                throw new Error("toast broke");
            }
        });
        doesNotThrow(function () {
            ErrorHandler.handle("s", new Error("x"));
        });
    }
    function test_foreign_errors_show_only_the_generic_message() {
        let record = ErrorHandler.handle("fetcher", new Error("secret internals"));
        check(record.userMessage.indexOf("secret") === -1, "raw text is never shown");
        same(toasts.length, 1);
        check(toasts[0][0].indexOf("secret") === -1);
        check(logs.length === 1 && logs[0][2].indexOf("secret") !== -1, "isDevMode logs the exact reason");
    }
    function test_guard_returns_value_or_record() {
        let ok = ErrorHandler.guard("s", function () {
            return 5;
        });
        check(ok.ok);
        same(ok.value, 5);
        let bad = ErrorHandler.guard("s", function () {
            throw new Error("boom");
        });
        check(!bad.ok);
        same(bad.error.scope, "s");
    }
    function test_nothing_is_logged_outside_dev_mode() {
        Logger.configure({
            isDevMode: false
        });
        ErrorHandler.handle("fetcher", new Error("x"));
        Logger.debug("fetcher", "hello");
        Logger.error("fetcher", "boom");
        same(logs.length, 0);
    }
    function test_notify_false_records_without_toast() {
        ErrorHandler.handle("fetcher", new Error("x"), {
            notify: false
        });
        same(toasts.length, 0);
        same(ErrorHandler.recent.length, 1);
    }
    function test_plugin_errors_keep_friendly_text_and_flags() {
        let error = new PluginError.PluginError("network", "Can't reach X.", "curl exit 6", {
            retryable: true,
            status: 0
        });
        let record = ErrorHandler.handle("fetcher", error, {
            context: "EURUSD"
        });
        same(record.userMessage, "Can't reach X.");
        check(record.retryable);
        same(record.details, "EURUSD: curl exit 6");
        same(toasts[0][2], "markets-network");
    }
    function test_recent_is_bounded() {
        for (let i = 0; i < 500; i++)
            ErrorHandler.handle("s", new Error("e" + i), {
                notify: false
            });
        check(ErrorHandler.recent.length <= 100 && ErrorHandler.recent.length > 0);
    }
    function test_retry_only_transient_and_bounded() {
        let transient = new PluginError.PluginError("network", "m", "", {
            retryable: true
        });
        let fatal = new PluginError.PluginError("notFound", "m", "");
        check(ErrorHandler.shouldRetry(transient, 0, 2));
        check(!ErrorHandler.shouldRetry(transient, 2, 2));
        check(!ErrorHandler.shouldRetry(fatal, 0, 2));
        check(!ErrorHandler.shouldRetry(new Error("x"), 0, 2));
    }
    function test_toasts_are_rate_limited_per_message() {
        let error = new PluginError.PluginError("network", "Can't reach X.", "");
        ErrorHandler.handle("fetcher", error);
        ErrorHandler.handle("fetcher", error);
        same(toasts.length, 1, "second identical error within the cooldown is not toasted");
        same(ErrorHandler.recent.length, 2, "…but still recorded");
        now += 10 * 60 * 1000;
        ErrorHandler.handle("fetcher", error);
        same(toasts.length, 2, "after the cooldown it may be shown again");
    }
}
