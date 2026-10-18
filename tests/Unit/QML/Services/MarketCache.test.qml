// MarketCache against the real file system: one file per symbol, only the latest update stays, retries,
// a fallback file name when the symbol's file cannot be written, the newest file (by modification time) is the one
// read, and nothing that goes wrong with a file is ever an error for the caller.
import QtQuick
import "../../../../src/JS/Helpers/Constants.js" as JsConstants
import "../../../../src/QML/Services"
import "../../../Helpers"

TestSuite {
    id: suite

    property var cache: null
    property Component cacheType: Component {
        MarketCache {
            attempts: 3
            flushDelayMs: 20
            retryDelayMs: 10
        }
    }
    property var current: ({})      // what snapshotOf returns, by uid

    property var logs: []
    readonly property string uidA: "aaaaaaaa-1111-4111-8111-111111111111"
    readonly property string uidB: "bbbbbbbb-2222-4222-8222-222222222222"

    function async_a_failing_read_is_retried_then_skipped(done) {
        make({
            attempts: 3
        });
        cache._readFile(uidA, "missing.json", 1, function (record) {
            done(record === null && loggedCount("reading missing.json failed (attempt") === 2 && logged("failed 3 times") && ErrorHandler.recent.length === 0 ? "" : JSON.stringify(logs));
        });
    }

    // ── Removing ─────────────────────────────────────────────────────────────
    function async_a_removed_symbols_files_are_deleted_and_other_symbols_stay(done) {
        make();
        seed(uidA + ".json", json(uidA, 1), 10, function () {
            seed(uidA + "-4.json", json(uidA, 2), 5, function () {
                seed(uidB + ".json", json(uidB, 3), 5, function () {
                    cache.discard(uidA);
                    waitUntil(idle, function (problem) {
                        if (problem) {
                            done(problem);
                            return;
                        }
                        files(function (names) {
                            done(JSON.stringify(names) === JSON.stringify([uidB + ".json"]) ? "" : "files " + names);
                        });
                    }, 5000);
                });
            });
        });
    }
    function async_a_symbol_removed_during_its_write_leaves_no_file(done) {
        make();
        current[uidA] = record(1);
        cache.markDirty(uidA);
        cache.flushNow();
        cache.discard(uidA);
        waitUntil(function () {
            return idle() && !cache._writing[uidA];
        }, function (problem) {
            if (problem) {
                done(problem);
                return;
            }
            files(function (names) {
                done(names.length === 0 ? "" : "left behind: " + names);
            });
        }, 5000);
    }

    // ── First run ────────────────────────────────────────────────────────────
    function async_a_symbol_without_a_file_just_starts_empty_and_nothing_is_reported(done) {
        make();
        cache.load([uidA, uidB], function (records) {
            let problems = [];
            if (Object.keys(records).length !== 0)
                problems.push("records: " + JSON.stringify(records));
            if (!logged("no saved data for " + uidA))
                problems.push("the first run is not logged");
            if (ErrorHandler.recent.length !== 0)
                problems.push("an error was reported");
            if (logs.some(function (line) {
                return line.indexOf("TOAST") === 0;
            }))
                problems.push("the user was told");
            done(problems.join("; "));
        });
    }
    function async_an_unreadable_newest_file_falls_back_to_the_next_one(done) {
        make();
        seed(uidA + ".json", json(uidA, 1), 100, function () {
            seed(uidA + "-9.json", "{ not json", 1, function () {
                cache.load([uidA], function (records) {
                    done(records[uidA] && records[uidA].price.close === 1 && logged("-9.json is not usable") && ErrorHandler.recent.length === 0 ? "" : "records " + JSON.stringify(records) + " " + logs);
                });
            });
        });
    }
    function async_an_unwritable_file_is_retried_then_replaced_by_a_new_one_with_a_suffix(done) {
        make({
            attempts: 2
        });
        blockPrimary(function () {
            current[uidA] = record(5);
            let name = "";
            cache.written.connect(function (uid, fileName) {
                name = fileName;
            });
            cache.markDirty(uidA);
            waitUntil(function () {
                return name !== "" && idle();
            }, function (problem) {
                if (problem) {
                    done(problem);
                    return;
                }
                let problems = [];
                if (!new RegExp("^" + uidA + "-[0-9]+\\.json$").test(name))
                    problems.push("name " + name);
                if (loggedCount("writing " + uidA + ".json failed (attempt") !== 1)
                    problems.push("not retried: " + loggedCount("failed (attempt"));
                if (!logged("cannot be written"))
                    problems.push("no fallback logged");
                if (ErrorHandler.recent.length !== 0)
                    problems.push("reported as an error although the data was saved");
                cache.load([uidA], function (records) {
                    if (!records[uidA] || records[uidA].price.close !== 5)
                        problems.push("the fallback file is not read back: " + JSON.stringify(records));
                    done(problems.join("; "));
                });
            }, 8000, function () {
                return JSON.stringify(logs);
            });
        });
    }
    function async_an_unwritable_or_missing_directory_is_a_first_run_too(done) {
        make({
            directory: "/proc/definitely/not/here"
        });
        cache.load([uidA], function (records) {
            done(Object.keys(records).length === 0 && ErrorHandler.recent.length === 0 ? "" : "reported");
        });
    }
    function async_an_update_during_a_write_is_written_after_it_not_lost(done) {
        let calls = 0;
        make({
            snapshotOf: function (uid) {
                calls++;
                return record(calls);
            }
        });
        cache.markDirty(uidA);
        cache.flushNow();                                               // the first write starts now…
        cache.markDirty(uidA);                                          // …and the symbol changes meanwhile
        waitUntil(function () {
            return idle() && cache._dirty[uidA] === undefined && calls >= 2;
        }, function (problem) {
            if (problem) {
                done(problem);
                return;
            }
            read(uidA + ".json", function (text) {
                done(JSON.parse(text).price.close === calls ? "" : "stale file: " + JSON.parse(text).price.close + " of " + calls);
            });
        }, 5000);
    }
    function async_bad_uids_are_refused_by_every_entry_point(done) {
        make({
            snapshotOf: function () {
                return record(1);
            }
        });
        cache.markDirty("../escape");
        cache.discard("../escape");
        cache.load(["../escape", "x"], function (records) {
            files(function (names) {
                done(Object.keys(records).length === 0 && names.length === 0 && !cache._dirty["../escape"] ? "" : "something was accepted: " + JSON.stringify(names));
            });
        });
    }
    function async_damaged_or_foreign_files_are_never_an_error(done) {
        make();
        let bad = [["{ no", "invalid"], ["[1,2]", "not a record"], ["null", "not a record"], [JSON.stringify({
                    version: 99,
                    uid: uidA
                }), "format version 99"], [JSON.stringify({
                    version: 1,
                    uid: uidB
                }), "belongs to another symbol"], ["", "invalid"]];
        let remaining = bad.length, problems = [];
        bad.forEach(function (entry, index) {
            let uid = "c" + index + "cccccc-3333-4333-8333-333333333333";
            seed(uid + ".json", entry[0], 5, function () {
                cache.load([uid], function (records) {
                    if (records[uid])
                        problems.push("accepted " + entry[0]);
                    if (--remaining === 0)
                        done(problems.concat(ErrorHandler.recent.length ? ["an error was reported"] : []).join("; "));
                });
            });
        });
    }
    function async_loading_nothing_still_calls_back(done) {
        make();
        cache.load([], function (records) {
            done(JSON.stringify(records) === "{}" ? "" : "unexpected");
        });
    }
    function async_new_data_after_a_removal_during_a_write_is_kept(done) {
        // The symbol's settings changed while its old data was being written: the old file goes, the new data stays.
        let calls = 0;
        make({
            snapshotOf: function (uid) {
                calls++;
                return record(calls === 1 ? 1 : 77);
            }
        });
        current[uidA] = record(1);
        cache.markDirty(uidA);
        cache.flushNow();
        cache.discard(uidA);
        cache.markDirty(uidA);
        waitUntil(function () {
            return idle() && cache._dirty[uidA] === undefined && !cache._writing[uidA];
        }, function (problem) {
            if (problem) {
                done(problem);
                return;
            }
            read(uidA + ".json", function (text) {
                done(text.indexOf('"close":77') !== -1 ? "" : "the new data was lost: " + text.slice(0, 80));
            });
        }, 5000);
    }
    function async_nothing_to_save_writes_nothing_and_a_failing_snapshot_is_survived(done) {
        make({
            snapshotOf: function (uid) {
                if (uid === uidA)
                    return null;
                throw new Error("boom");
            }
        });
        cache.markDirty(uidA);
        cache.markDirty(uidB);
        waitUntil(function () {
            return Object.keys(cache._dirty).length === 0 && idle();
        }, function (problem) {
            if (problem) {
                done(problem);
                return;
            }
            files(function (names) {
                done(names.length === 0 && logged("no snapshot of " + uidB) && Object.keys(cache._writing).length === 0 ? "" : "files " + names + " " + JSON.stringify(logs));
            });
        }, 5000);
    }
    function async_one_file_per_symbol_named_by_its_uid(done) {
        make();
        current[uidA] = record(1);
        current[uidB] = record(2);
        cache.markDirty(uidA);
        cache.markDirty(uidB);
        waitUntil(function () {
            return idle() && cache._dirty[uidA] === undefined && cache._dirty[uidB] === undefined;
        }, function (problem) {
            if (problem) {
                done(problem);
                return;
            }
            files(function (names) {
                done(JSON.stringify(names) === JSON.stringify([uidA + ".json", uidB + ".json"]) ? "" : "files: " + names);
            });
        }, 5000);
    }
    function async_only_the_very_last_update_stays_on_disk(done) {
        make();
        current[uidA] = record(1);
        cache.markDirty(uidA);
        cache.written.connect(function onFirst() {
            cache.written.disconnect(onFirst);
            current[uidA] = record(2);                                   // the symbol is refreshed separately, say by the user
            cache.markDirty(uidA);
            cache.written.connect(function onSecond() {
                cache.written.disconnect(onSecond);
                waitUntil(idle, function (problem) {
                    if (problem) {
                        done(problem);
                        return;
                    }
                    files(function (names) {
                        read(uidA + ".json", function (text) {
                            let saved = JSON.parse(text);
                            done(names.length === 1 && saved.price.close === 2 ? "" : "files " + names + ", close " + saved.price.close);
                        });
                    });
                }, 5000);
            });
        });
    }
    function async_shell_work_is_serial_and_bounded(done) {
        make();
        let completed = 0, refused = 0, highestActive = 0;
        cache._processCountChanged.connect(function () {
            highestActive = Math.max(highestActive, cache._processCount);
        });
        for (let i = 0; i < JsConstants.CACHE_PROCESS_QUEUE_MAX + 2; i++) {
            cache._run(["bash", "-c", "printf ready"], function (code, text) {
                completed++;
                if (code !== 0)
                    refused++;
            });
        }
        same(cache._processCount, 1);
        same(cache._processQueue.length, JsConstants.CACHE_PROCESS_QUEUE_MAX);
        waitUntil(function () {
            return completed === JsConstants.CACHE_PROCESS_QUEUE_MAX + 2 && cache.busy === 0;
        }, function (problem) {
            done(problem || (highestActive <= 1 && refused === 1 ? "" : "active=" + highestActive + ", refused=" + refused));
        }, 10000);
    }
    function async_the_directory_is_created_when_it_is_missing_and_again_if_it_vanishes(done) {
        make();
        current[uidA] = record(1);
        cache.markDirty(uidA);
        cache.written.connect(function onFirst() {
            cache.written.disconnect(onFirst);
            shell('rm -rf -- "$1"', [cache.directory], function () {
                current[uidA] = record(2);
                cache.markDirty(uidA);
                waitUntil(function () {
                    return cache._dirty[uidA] === undefined && idle();
                }, function (problem) {
                    if (problem) {
                        done(problem);
                        return;
                    }
                    cache.load([uidA], function (records) {
                        done(records[uidA] && records[uidA].price.close === 2 ? "" : "lost after the directory vanished: " + JSON.stringify(logs));
                    });
                }, 8000);
            });
        });
    }
    function async_the_latest_file_by_modification_time_is_read(done) {
        make();
        seed(uidA + ".json", json(uidA, 1), 300, function () {
            seed(uidA + "-777.json", json(uidA, 3), 10, function () {
                seed(uidA + "-555.json", json(uidA, 2), 100, function () {
                    cache.load([uidA], function (records) {
                        done(records[uidA] && records[uidA].price.close === 3 ? "" : "read " + JSON.stringify(records[uidA] && records[uidA].price));
                    });
                });
            });
        });
    }
    function async_the_next_update_goes_to_the_new_file_name_again_and_old_ones_are_cleaned(done) {
        make({
            attempts: 1
        });
        blockPrimary(function () {
            current[uidA] = record(1);
            cache.markDirty(uidA);
            cache.written.connect(function onFirst(uid, first) {
                cache.written.disconnect(onFirst);
                current[uidA] = record(2);
                cache.markDirty(uidA);
                cache.written.connect(function onSecond(uid2, second) {
                    cache.written.disconnect(onSecond);
                    waitUntil(idle, function (problem) {
                        if (problem) {
                            done(problem);
                            return;
                        }
                        files(function (names) {
                            let suffixed = names.filter(function (name) {
                                return name !== uidA + ".json";
                            });
                            cache.load([uidA], function (records) {
                                done(suffixed.length === 1 && suffixed[0] === second && records[uidA].price.close === 2 ? "" : "files " + names + ", read " + JSON.stringify(records[uidA] && records[uidA].price));
                            });
                        });
                    }, 5000);
                });
            });
        });
    }
    function async_the_older_files_are_deleted_once_a_newer_one_is_written(done) {
        make();
        seed(uidA + ".json", json(uidA, 1), 300, function () {
            seed(uidA + "-5.json", json(uidA, 2), 100, function () {
                current[uidA] = record(9);
                cache.markDirty(uidA);
                waitUntil(function () {
                    return idle() && cache._dirty[uidA] === undefined;
                }, function (problem) {
                    if (problem) {
                        done(problem);
                        return;
                    }
                    files(function (names) {
                        done(JSON.stringify(names) === JSON.stringify([uidA + ".json"]) ? "" : "files " + names);
                    });
                }, 5000);
            });
        });
    }
    function async_updates_within_the_delay_are_one_write_of_the_latest_data(done) {
        let snapshots = 0;
        make({
            flushDelayMs: 60,
            snapshotOf: function (uid) {
                snapshots++;
                return record(snapshots);
            }
        });
        for (let i = 0; i < 6; i++)
            cache.markDirty(uidA);
        let writes = 0;
        cache.written.connect(function () {
            writes++;
        });
        waitUntil(function () {
            return writes >= 1 && idle();
        }, function (problem) {
            if (problem) {
                done(problem);
                return;
            }
            done(snapshots === 1 && writes === 1 ? "" : "snapshots " + snapshots + ", writes " + writes);
        }, 5000);
    }

    // ── Write and read back ──────────────────────────────────────────────────
    function async_what_is_written_is_read_back_with_when_it_was_fetched(done) {
        make();
        current[uidA] = record(101);
        let begun = Date.now();
        cache.markDirty(uidA);
        waitUntil(function () {
            return cache._dirty[uidA] === undefined && idle();
        }, function (problem) {
            if (problem) {
                done(problem);
                return;
            }
            cache.load([uidA], function (records) {
                let saved = records[uidA];
                let problems = [];
                if (!saved) {
                    done("nothing was read back");
                    return;
                }
                if (saved.version !== 1 || saved.uid !== uidA)
                    problems.push("version/uid");
                if (!(saved.savedAt >= begun))
                    problems.push("savedAt");
                if (saved.price.close !== 101 || saved.reference !== 100 || saved.graph.length !== 1)
                    problems.push("data: " + JSON.stringify(saved));
                if (JSON.stringify(saved.refreshedAt) !== JSON.stringify({
                    price: 1000,
                    change: 1000,
                    graph: 1000
                }))
                    problems.push("when it was fetched");
                if (saved.signature !== record(1).signature)
                    problems.push("signature");
                files(function (names) {
                    if (JSON.stringify(names) !== JSON.stringify([uidA + ".json"]))
                        problems.push("files: " + names);
                    done(problems.join("; "));
                });
            });
        }, 5000, function () {
            return "busy " + cache.busy;
        });
    }
    function async_when_no_file_can_be_written_it_is_logged_and_reported_quietly_and_nothing_stalls(done) {
        // The cache "directory" is a regular file, so neither creating it nor writing below it can work.
        make({
            attempts: 2,
            maxFallbacks: 1
        });
        shell('rm -rf -- "$1"; : > "$1"', [cache.directory], function () {
            current[uidA] = record(1);
            let gaveUp = false;
            cache.writeGaveUp.connect(function () {
                gaveUp = true;
            });
            cache.markDirty(uidA);
            waitUntil(function () {
                return gaveUp && idle();
            }, function (problem) {
                if (problem) {
                    done(problem);
                    return;
                }
                let problems = [];
                if (ErrorHandler.recent.length !== 1 || ErrorHandler.recent[0].code !== "storage")
                    problems.push("not recorded: " + JSON.stringify(ErrorHandler.recent));
                if (logs.some(function (line) {
                    return line.indexOf("TOAST") === 0;
                }))
                    problems.push("the user was bothered with a toast");
                if (cache._writing[uidA])
                    problems.push("the symbol stays marked as writing");
                // …and a later update is tried again from scratch.
                shell('rm -f -- "$1"', [cache.directory], function () {
                    let ok = false;
                    cache.written.connect(function () {
                        ok = true;
                    });
                    cache.markDirty(uidA);
                    waitUntil(function () {
                        return ok && idle();
                    }, function (problem2) {
                        done(problem2 || problems.join("; "));
                    }, 5000);
                });
            }, 8000, function () {
                return JSON.stringify(logs);
            });
        });
    }

    // ── A file that cannot be written ────────────────────────────────────────
    // A directory in the place of the symbol's file makes every write to that name fail.
    function blockPrimary(done) {
        shell('mkdir -p -- "$1/$2.json"', [cache.directory, uidA], function () {
            done();
        });
    }
    // Names of the files in the cache directory, sorted (done gets an array).
    function files(done) {
        shell('ls -1 -- "$1" 2>/dev/null | sort', [cache.directory], function (code, text) {
            done(text.split("\n").filter(Boolean));
        });
    }
    function idle() {
        return cache.busy === 0;
    }
    function json(uid, close) {
        return JSON.stringify(Object.assign({
            version: 1,
            uid: uid,
            savedAt: 1
        }, record(close)));
    }
    function logged(fragment) {
        return logs.some(function (line) {
            return line.indexOf(fragment) !== -1;
        });
    }
    function loggedCount(fragment) {
        return logs.filter(function (line) {
            return line.indexOf(fragment) !== -1;
        }).length;
    }
    function make(extra) {
        cache = (cacheType.createObject(null, Object.assign({
                directory: freshDirectory("cache"),
                snapshotOf: function (uid) {
                    return current[uid] || null;
                }
            }, extra || {})) as MarketCache);
        return cache;
    }
    function read(name, done) {
        shell('cat -- "$1/$2"', [cache.directory, name], function (code, text) {
            done(text);
        });
    }
    function record(close, extra) {
        return Object.assign({
            signature: "yahoo|T|1h|1d|1d|1M|false",
            price: {
                open: close - 1,
                high: close + 1,
                low: close - 2,
                close: close,
                date: "2026-01-02",
                time: "10:00:00",
                change: 1,
                changePercent: 1
            },
            reference: close - 1,
            graph: [
                {
                    date: "2026-01-01",
                    time: "",
                    open: 1,
                    high: 2,
                    low: 0.5,
                    close: close,
                    volume: 0
                }
            ],
            refreshedAt: {
                price: 1000,
                change: 1000,
                graph: 1000
            }
        }, extra || {});
    }

    // ── The newest file wins ─────────────────────────────────────────────────
    function seed(name, text, age, done) {
        shell('mkdir -p -- "$1" && printf %s "$3" > "$1/$2" && touch -d "$4 seconds ago" "$1/$2"', [cache.directory, name, text, String(age)], function () {
            done();
        });
    }
    function setup() {
        ErrorHandler.reset();
        logs = [];
        Logger.configure({
            devMode: true,
            sink: function (level, scope, text) {
                logs.push(level + " " + scope + ": " + text);
            }
        });
        ErrorHandler.configure({
            notify: function (message, details, category) {
                logs.push("TOAST " + message);
            }
        });
        if (cache) {
            cache.destroy();
            cache = null;
        }
        current = {};
    }
    function teardown() {
        Logger.configure({
            devMode: false
        });
    }

    // ── Names and ids ────────────────────────────────────────────────────────
    function test_only_real_uids_are_accepted_so_a_symbol_can_never_reach_outside_the_directory() {
        make();
        check(cache.isValidUid(uidA));
        ["", "..", "../x", "a/b", "aaaaaaaa-1111-4111-8111-11111111111", uidA + "x", uidA + "/..", null, undefined, 5].forEach(function (bad) {
            check(!cache.isValidUid(bad), "refused: " + bad);
        });
        same(cache.fileNameOf(uidA), uidA + ".json");
        let fallback = cache.fallbackNameOf(uidA);
        check(new RegExp("^" + uidA + "-[0-9]+\\.json$").test(fallback), fallback);
        check(cache.fallbackNameOf(uidA) !== cache.fallbackNameOf(uidA) || cache.fallbackNameOf(uidA) !== cache.fallbackNameOf(uidA), "random suffixes");
    }
}
