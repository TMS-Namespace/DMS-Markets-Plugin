import QtQuick
import "../../../../src/JS/Helpers/Helpers.js" as Helpers
import "../../../../src/QML/Services"
import "../../../Helpers"

TestSuite {
    id: suite

    readonly property var legacy: [
        {
            id: "BRLPLN",
            name: "Real",
            provider: "wise",
            priceInterval: "5m",
            graphInterval: "1Y",
            pinned: true
        }
    ]
    property Component serviceType: Component {
        QtObject {
            property int attempts: 0
            property var data: ({})
            property int failFirst: 0          // the first n saves throw, then they work
            property var failWith: null
            property bool refuse: false        // saves report `false`
            property bool refuseBackup: false
            property var writes: []

            function loadPluginData(id, key, fallback) {
                return key in data ? data[key] : fallback;
            }
            function savePluginData(id, key, value) {
                attempts++;
                if (failFirst > 0) {
                    failFirst--;
                    throw new Error("transient failure");
                }
                if (refuse || (refuseBackup && key === "symbolsBackup"))
                    return false;
                if (failWith)
                    throw failWith;
                writes.push([id, key, value]);
                data[key] = value;
            }
        }
    }
    property Component storageType: Component {
        DataStorage {
        }
    }
    property var toasts: []

    function async_damaged_data_is_backed_up_after_binding_evaluation_without_a_write_loop(done) {
        let pluginService = service({
            symbols: "{broken"
        }), dataStorage = storage(pluginService);
        equal(dataStorage.readCurrentSymbols("{broken"), []);
        same(pluginService.writes.length, 0, "no host writes inside binding evaluation");
        waitUntil(function () {
            return pluginService.data.symbolsBackup === "{broken";
        }, function (problem) {
            if (problem) {
                done(problem);
                return;
            }
            equal(dataStorage.readCurrentSymbols("{broken"), []);
            dataStorage.readSymbols("{broken");
            done(pluginService.writes.length === 1 ? "" : "an identical backup was written again");
        });
    }
    function buildSymbol(uid, extra) {
        let symbol = {
            uid: uid,
            ticker: "T" + uid,
            name: "N" + uid,
            provider: "wise",
            priceResolution: "1h",
            changeResolution: "1d",
            chartResolution: "1d",
            chartRange: "1M",
            showChangeWhenPinned: false,
            invert: false,
            pinned: false
        };
        for (let field in extra)
            symbol[field] = extra[field];
        return symbol;
    }
    function lastError() {
        return ErrorHandler.recent[ErrorHandler.recent.length - 1];
    }
    function list() {
        return [buildSymbol(uid(1)), buildSymbol(uid(2), {
                ticker: "TWIN"
            }), buildSymbol(uid(3), {
                ticker: "TWIN"
            })];
    }
    function saved(pluginService) {
        return JSON.parse(pluginService.data.symbols);
    }
    function service(initial, failWith) {
        return serviceType.createObject(null, {
            data: initial || ({}),
            failWith: failWith || null
        });
    }
    function setup() {
        ErrorHandler.reset();
        toasts = [];
        ErrorHandler.configure({
            notify: function (message, details, category) {
                toasts.push({
                    message: message,
                    details: details,
                    category: category
                });
            }
        });
    }
    function storage(pluginService) {
        return (storageType.createObject(null, {
                pluginId: "markets",
                pluginService: pluginService
            }) as DataStorage);
    }
    function test_a_failed_migration_save_still_returns_the_list_and_says_so() {
        let dataStorage = storage(service({}, new Error("read-only")));
        let result = dataStorage.migrate(legacy);
        check(result.changed);
        check(!result.saved);
        same(result.symbols[0].ticker, "BRLPLN");
        same(toasts[0].message, "Your changes couldn't be saved.");
    }
    function test_a_failing_service_is_a_failed_save_that_tells_the_user() {
        let broken = storage(service({}, new Error("EACCES: permission denied")));
        check(!broken.save("symbols", "[]"));
        same(toasts[0].message, "Your changes couldn't be saved.");
        check(/EACCES/.test(toasts[0].details) && /symbols/.test(toasts[0].details), "cause and key in the details");
        broken.save("symbols", "[]");
        same(toasts.length, 1, "repeated failures do not spam toasts");
        same(lastError().code, "storage");
    }
    function test_a_missing_or_failing_backup_does_not_hide_the_original_problem() {
        let noService = storage(null);
        doesNotThrow(function () {
            noService.readSymbols("{broken");
        });
        same(toasts.length, 1);
        check(ErrorHandler.recent.some(function (record) {
            return /backing up saved symbols/.test(record.details);
        }));
        setup();
        let failing = storage(service({}, new Error("disk full")));
        doesNotThrow(function () {
            failing.readSymbols("{broken");
        });
        same(toasts[0].message, "Your saved symbols couldn't be read.");
        same(toasts.length, 1);
        let notText = service(), dataStorage = storage(notText);
        dataStorage.readSymbols({
            a: 1
        });
        same(notText.writes.length, 0, "only text can be backed up");
    }
    // ── Saves are retried ────────────────────────────────────────────────────
    function test_a_save_that_fails_for_a_moment_is_retried_and_succeeds_quietly() {
        let pluginService = service({});
        pluginService.failFirst = 2;
        let dataStorage = storage(pluginService);
        check(dataStorage.save("a", 1), "succeeded on the third try");
        same(pluginService.attempts, 3);
        equal(pluginService.writes, [["markets", "a", 1]]);
        same(toasts.length, 0, "the user is not bothered by a failure that went away");
    }
    function test_a_save_that_keeps_failing_is_tried_a_fixed_number_of_times_then_reported_once() {
        let pluginService = service({});
        pluginService.failFirst = 99;
        let dataStorage = storage(pluginService);
        check(!dataStorage.save("a", 1));
        same(pluginService.attempts, 3, "three tries, no more");
        same(toasts.length, 1, "one message for the whole failure");
        same(lastError().code, "storage");
    }
    function test_a_service_that_answers_false_is_a_failed_save() {
        let pluginService = service({});
        pluginService.refuse = true;
        let dataStorage = storage(pluginService);
        check(!dataStorage.save("a", 1));
        same(pluginService.attempts, 3);
        same(toasts.length, 1);
    }

    // ── Credentials / old settings ───────────────────────────────────────────
    function test_credentials_are_deobfuscated_for_providers_that_need_one() {
        let dataStorage = storage(service()), secret = "abc123";
        equal(dataStorage.readCredentials({
            providerCredential_stooq: "091617414109",
            showTicker: true
        }), {
            stooq: secret
        });
        equal(dataStorage.readCredentials({}), {
            stooq: ""
        });
        equal(dataStorage.readCredentials(null), {
            stooq: ""
        });
        same(dataStorage.readCredentials({
            providerCredential_stooq: "plain legacy text"
        }).stooq, "plain legacy text");
    }

    // ── Reading ──────────────────────────────────────────────────────────────
    function test_damaged_symbols_are_reported_and_backed_up_never_silently_dropped() {
        let pluginService = service(), dataStorage = storage(pluginService);
        same(dataStorage.readSymbols('[{"uid":"a","ticker":"A"}]').length, 1);
        same(dataStorage.readSymbols(undefined).length, 0);
        same(dataStorage.readSymbols("[]").length, 0);
        same(dataStorage.readSymbols([
            {
                ticker: "A"
            }
        ]).length, 1, "a parsed list is accepted");
        same(toasts.length, 0);
        same(pluginService.writes.length, 0);

        equal(dataStorage.readSymbols("{broken"), []);
        equal(pluginService.writes, [["markets", "symbolsBackup", "{broken"]]);
        same(toasts.length, 1);
        same(toasts[0].message, "Your saved symbols couldn't be read.");
        check(/saved symbols/.test(lastError().details));
        dataStorage.readSymbols("{broken");
        same(toasts.length, 1, "a re-read does not repeat the toast");
        dataStorage.readSymbols("[1,2]");
        same(pluginService.data.symbolsBackup, "[1,2]");
        dataStorage.readSymbols('{"a":1}');
        same(pluginService.data.symbolsBackup, '{"a":1}');
        same(pluginService.data.symbols, undefined, "the damaged value itself is never rewritten");
    }
    function test_every_edit_reports_failure() {
        let dataStorage = storage(service({}, new Error("disk full"))), input = list();
        check(!dataStorage.togglePin(input, uid(1)));
        check(!dataStorage.removeSymbol(input, uid(1)));
        same(dataStorage.removeSymbolAt(input, 0), null);
        check(!dataStorage.moveSymbol(input, 0, 1));
        check(!dataStorage.updateSymbolAt(input, 0, {
            invert: true
        }));
        equal(dataStorage.upsertSymbol(input, buildSymbol(uid(7)), -1), {
            saved: false,
            updated: false
        });
        same(toasts.length, 1, "one toast for the burst");
        same(toasts[0].message, "Your changes couldn't be saved.");
    }

    // ── List edits ───────────────────────────────────────────────────────────
    function test_list_edits_are_one_checked_save_each_and_never_mutate_the_callers_list() {
        let pluginService = service(), dataStorage = storage(pluginService), input = list(), snapshot = JSON.stringify(input);
        check(dataStorage.togglePin(input, uid(2)));
        equal(saved(pluginService).map(function (symbol) {
            return symbol.pinned;
        }), [false, true, false], "by uid, the ticker is not unique");
        check(!dataStorage.togglePin(input, "no-such-uid"));
        same(pluginService.writes.length, 1);
        check(dataStorage.removeSymbol(input, uid(1)));
        equal(saved(pluginService).map(function (symbol) {
            return symbol.uid;
        }), [uid(2), uid(3)]);
        check(dataStorage.removeSymbol(input, uid(2)));
        equal(saved(pluginService).map(function (symbol) {
            return symbol.uid;
        }), [uid(1), uid(3)], "keeps the same-ticker twin");
        check(!dataStorage.removeSymbol(input, "nope"));
        same(JSON.stringify(input), snapshot);

        same(dataStorage.removeSymbolAt(input, 1).uid, uid(2));
        same(dataStorage.removeSymbolAt(input, 7), null);
        same(dataStorage.removeSymbolAt(input, -1), null);
        check(dataStorage.moveSymbol(input, 0, 1));
        equal(saved(pluginService).map(function (symbol) {
            return symbol.uid;
        }), [uid(2), uid(1), uid(3)]);
        check(!dataStorage.moveSymbol(input, 2, 1));
        check(!dataStorage.moveSymbol(input, 0, -1));
        check(!dataStorage.moveSymbol(input, 5, 1));
        check(dataStorage.updateSymbolAt(input, 1, {
            invert: true,
            showChangeWhenPinned: true
        }));
        same(saved(pluginService)[1].invert, true);
        same(saved(pluginService)[1].showChangeWhenPinned, true);
        same(saved(pluginService)[1].ticker, "TWIN");
        check(!dataStorage.updateSymbolAt(input, 9, {
            invert: true
        }));
        same(JSON.stringify(input), snapshot);
    }
    function test_load_symbols_is_read_plus_migrate() {
        let pluginService = service({
            symbols: JSON.stringify(legacy)
        }), dataStorage = storage(pluginService);
        let loadedSymbols = dataStorage.loadSymbols();
        same(loadedSymbols[0].chartRange, "6M");
        same(saved(pluginService)[0].uid, loadedSymbols[0].uid);
        let next = service({
            symbols: JSON.stringify(loadedSymbols)
        });
        same(storage(next).loadSymbols()[0].uid, loadedSymbols[0].uid, "uids are stable across loads");
        same(next.writes.length, 0);
        let corrupt = service({
            symbols: "{nope"
        });
        equal(storage(corrupt).loadSymbols(), []);
        same(corrupt.data.symbolsBackup, "{nope");
        equal(storage(service()).loadSymbols(), []);
    }

    // ── Migration ────────────────────────────────────────────────────────────
    function test_migration_upgrades_and_persists_once() {
        let pluginService = service(), dataStorage = storage(pluginService);
        let result = dataStorage.migrate(legacy);
        check(result.changed);
        check(result.saved);
        let first = saved(pluginService)[0];
        let expected = {
            ticker: "BRLPLN",
            provider: "wise",
            priceResolution: "1h",
            changeResolution: "1d",
            chartResolution: "1d",
            chartRange: "6M",
            name: "Real",
            pinned: true
        };
        for (let field in expected)
            same(first[field], expected[field], field);
        check(Helpers.isUuid(first.uid));
        same(result.symbols[0].uid, first.uid);
        ["id", "priceInterval", "graphInterval", "graphResolution"].forEach(function (old) {
            check(!(old in first), old);
        });
        let again = dataStorage.migrate(saved(pluginService));
        check(!again.changed && !again.saved);
        same(pluginService.writes.length, 1);
        check(!dataStorage.migrate([]).changed);
    }
    function test_no_service_attached_yet_saves_nothing_and_reports_nothing() {
        // DMS creates the settings page first and attaches the service afterwards; its controls save on every change.
        let none = storage(null);
        same(none.load("a", "fallback"), "fallback");
        check(!none.save("a", 1));
        same(toasts.length, 0, "not a failure: there is nothing to save to yet");
        check(!none.saveDraft({
            ticker: "X",
            name: "",
            provider: "yahoo",
            priceResolution: "1h",
            changeResolution: "1d",
            chartResolution: "1d",
            chartRange: "1M",
            showChange: false,
            invert: false
        }));
        same(toasts.length, 0);
        let late = storage(null);
        late.pluginService = service({});
        check(late.save("a", 1), "...and it saves once the service is attached");
    }

    // ── Validity is enforced at the storage boundary ─────────────────────────
    function test_nothing_malformed_is_ever_written() {
        let pluginService = service(), dataStorage = storage(pluginService);
        let bads = [buildSymbol(uid(1), {
                ticker: ""
            }), buildSymbol(uid(1), {
                chartRange: "7Y"
            }),
            {
                ticker: "X"
            },
            {}
        ];
        bads.forEach(function (bad, i) {
            equal(dataStorage.upsertSymbol([], bad, -1), {
                saved: false,
                updated: false
            }, "bad " + i);
        });
        same(pluginService.writes.length, 0);
        same(toasts.length, 1, "reported once");
        same(lastError().code, "storage");
        check(/saving a symbol/.test(lastError().details));
        check(dataStorage.upsertSymbol([], buildSymbol(uid(1)), -1).saved, "a valid symbol is accepted");
    }
    function test_old_setting_is_carried_over_once() {
        let pluginService = service(), dataStorage = storage(pluginService);
        check(dataStorage.migrateSettings({
            showPriceRange: false
        }));
        equal(pluginService.writes, [["markets", "showPriceChange", false]]);
        check(!dataStorage.migrateSettings({
            showPriceRange: false,
            showPriceChange: true
        }));
        check(!dataStorage.migrateSettings({}));
        check(!dataStorage.migrateSettings(null));
        same(pluginService.writes.length, 1);
        let failing = storage(service({}, new Error("nope")));
        check(!failing.migrateSettings({
            showPriceRange: true
        }));
        same(toasts.length, 1);
    }
    function test_only_a_json_list_of_objects_reads_as_symbols() {
        let dataStorage = storage(service());
        equal(dataStorage.readSymbols(""), []);
        equal(dataStorage.readSymbols(undefined), []);
        equal(dataStorage.readSymbols(null), []);
        equal(dataStorage.readSymbols("[]"), []);
        same(toasts.length, 0, "empty is not damage");
        ["{", "{}", "[1]", "[[]]", "[null]", "\"text\""].forEach(function (damaged) {
            setup();
            let local = storage(service());
            equal(local.readSymbols(damaged), [], damaged);
            same(toasts.length, 1, "reported: " + damaged);
            same(lastError().code, "storage");
        });
    }
    function test_price_change_toggle_reads_the_renamed_setting_with_the_old_one_as_fallback() {
        let dataStorage = storage(service());
        same(dataStorage.readShowPriceChange({}), true, "unset means on");
        same(dataStorage.readShowPriceChange({
            showPriceRange: false
        }), false, "an old saved value still applies");
        same(dataStorage.readShowPriceChange({
            showPriceRange: false,
            showPriceChange: true
        }), true, "the new setting wins");
        same(dataStorage.readShowPriceChange({
            showPriceChange: "false"
        }), false);
    }

    // ── Raw values ───────────────────────────────────────────────────────────
    function test_raw_load_and_save() {
        let pluginService = service({
            a: 1
        }), dataStorage = storage(pluginService);
        same(dataStorage.load("a", 0), 1);
        same(dataStorage.load("missing", "dflt"), "dflt");
        check(dataStorage.save("b", "x"));
        equal(pluginService.writes, [["markets", "b", "x"]]);
        same(toasts.length, 0);
    }
    function test_reading_for_a_binding_returns_only_current_symbols_without_writing() {
        let pluginService = service(), dataStorage = storage(pluginService);
        let current = dataStorage.readCurrentSymbols('[{"id":"BRLPLN","provider":"wise","priceInterval":"5m","graphInterval":"1M"}]');
        same(current.length, 1);
        check(current[0].uid && current[0].ticker === "BRLPLN");
        same(current[0].priceResolution, "1h");
        check(current[0].id === undefined && current[0].priceInterval === undefined);
        same(pluginService.writes.length, 0, "binding evaluation never writes back to the host");
        check(dataStorage.migrateSavedSymbols('[{"id":"BRLPLN","provider":"wise","priceInterval":"5m","graphInterval":"1M"}]').saved);
        same(pluginService.writes.length, 1, "the upgrade is saved explicitly after binding evaluation");
    }
    function test_symbol_writes_wait_until_damaged_data_has_been_backed_up() {
        let pluginService = service({
            symbols: "{broken"
        });
        // Symbol saves work but the backup key is temporarily unwritable.
        pluginService.refuseBackup = true;
        let dataStorage = storage(pluginService);
        equal(dataStorage.loadSymbols(), []);
        check(!dataStorage.saveSymbols([]), "refuse to overwrite the only copy of damaged data");
        same(pluginService.data.symbols, "{broken");
        pluginService.refuseBackup = false;
        check(dataStorage.saveSymbols([]), "saving resumes after a successful backup");
        same(pluginService.data.symbolsBackup, "{broken");
        same(pluginService.data.symbols, "[]");
    }
    function test_symbols_are_saved_with_the_same_retries() {
        let pluginService = service({});
        pluginService.failFirst = 1;
        check(storage(pluginService).saveSymbols([buildSymbol(uid(1))]));
        same(pluginService.attempts, 2);
        same(toasts.length, 0);
    }
    function test_the_backup_of_unreadable_symbols_is_retried_too() {
        let pluginService = service({
            symbols: "{ broken"
        });
        pluginService.failFirst = 1;
        let dataStorage = storage(pluginService);
        equal(dataStorage.readSymbols(pluginService.data.symbols), []);
        same(pluginService.data.symbolsBackup, "{ broken", "the raw text was kept after a retry");
    }

    // ── The form draft ───────────────────────────────────────────────────────
    function test_the_form_fields_are_saved_through_the_storage_boundary() {
        let pluginService = service(), dataStorage = storage(pluginService);
        check(dataStorage.saveDraft({
            ticker: "BRLPLN",
            name: "Real",
            provider: "wise",
            priceResolution: "1h",
            changeResolution: "1d",
            chartResolution: "1d",
            chartRange: "1M",
            showChange: true,
            invert: false
        }));
        same(pluginService.data._addTicker, "BRLPLN");
        same(pluginService.data._addProvider, "wise");
        same(pluginService.data._addShowChange, true);
        same(dataStorage.load("_addTicker", ""), "BRLPLN");
        same(dataStorage.load("_addName", "dflt"), "Real");
        same(dataStorage.load("_addInvert", "dflt"), false);
        check(!storage(service({}, new Error("disk full"))).saveDraft({
            ticker: "X",
            name: "",
            provider: "wise",
            priceResolution: "1h",
            changeResolution: "1d",
            chartResolution: "1d",
            chartRange: "1M",
            showChange: false,
            invert: false
        }), "a failed save is reported, not announced as success");
        same(toasts.length, 1, "...once");
    }
    function test_upsert_adds_or_edits_keeping_uid_and_pin() {
        let pluginService = service(), dataStorage = storage(pluginService), input = list();
        equal(dataStorage.upsertSymbol(input, buildSymbol(uid(4), {
            ticker: "NEW"
        }), -1), {
            saved: true,
            updated: false
        });
        equal(saved(pluginService).map(function (symbol) {
            return symbol.uid;
        }), [uid(1), uid(2), uid(3), uid(4)]);
        input[1].pinned = true;
        equal(dataStorage.upsertSymbol(input, buildSymbol("ffffffff-1111-4111-8111-111111111111", {
            ticker: "EDITED"
        }), 1), {
            saved: true,
            updated: true
        });
        same(saved(pluginService)[1].ticker, "EDITED");
        same(saved(pluginService)[1].uid, uid(2));
        same(saved(pluginService)[1].pinned, true);
        same(saved(pluginService).length, 3);
        let oldList = [
            {
                ticker: "OLD",
                pinned: false
            }
        ];
        dataStorage.upsertSymbol(oldList, buildSymbol(uid(5)), 0);
        same(saved(pluginService)[0].uid, uid(5));
        check(!dataStorage.upsertSymbol(input, buildSymbol(uid(6)), 99).updated, "an out-of-range edit index adds");
        check(!("uid" in oldList[0]), "inputs are not mutated");
    }
    function uid(digit) {
        return "" + digit + digit + digit + digit + digit + digit + digit + digit + "-1111-4111-8111-111111111111";
    }
}
