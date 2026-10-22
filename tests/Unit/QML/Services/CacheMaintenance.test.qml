// CacheMaintenance.test.qml - clear only disposable directories and coordinate buffered and in-flight disk writes.
import QtQuick
import "../../../../src/QML/Services"
import "../../../Helpers"

TestSuite {
    id: suite

    property Component cacheType: Component {
        MarketCache {
            flushDelayMs: 1000
            retryDelayMs: 5
        }
    }
    property var caches: []
    readonly property string firstUid: "aaaaaaaa-1111-4111-8111-111111111111"
    readonly property string secondUid: "bbbbbbbb-2222-4222-8222-222222222222"

    // Clearing waits for a real active save, drops pending saves, and covers every writer sharing a directory.
    function async_clear_waits_for_writes_and_later_saves_still_work(done) {
        let directory = freshDirectory("cache-clear");
        let first = make(directory, firstUid);
        let second = make(directory, secondUid);
        first.flushNow();
        check(first.busy > 0, "a save is in progress");
        CacheMaintenance.clearAll(function (success) {
            if (!success) {
                done("cache clear failed");
                return;
            }
            suite.shell('ls -1 -- "$1" 2>/dev/null', [directory], function (code, output) {
                try {
                    suite.same(output.trim(), "", "active and buffered saves leave no cache files");
                    suite.same(first._pausedForClear, false);
                    suite.same(second._pausedForClear, false);
                    first.markDirty(suite.firstUid);
                    first.flushNow();
                    suite.waitUntil(function () {
                        return first.busy === 0;
                    }, function (problem) {
                        if (problem) {
                            done(problem);
                            return;
                        }
                        first.load([suite.firstUid], function (records) {
                            done(records[suite.firstUid] && records[suite.firstUid].price.close === 12 ? "" : "later saves did not resume");
                        });
                    });
                } catch (error) {
                    done(error.message);
                }
            });
        });
        same(CacheMaintenance.clearAll(function () {}), false, "parallel clears are rejected");
    }

    // Disk failures must be reported, with caching resumed rather than permanently paused.
    function async_failed_clear_is_reported_and_resumes_writers(done) {
        let directory = freshDirectory("cache-clear-failure");
        let cache = make(directory, firstUid);
        shell('mkdir -p -- "$1/blocked.json"', [directory], function () {
            CacheMaintenance.clearAll(function (success) {
                try {
                    suite.same(success, false);
                    suite.same(cache._pausedForClear, false);
                    suite.same(CacheMaintenance.clearing, false);
                    suite.check(ErrorHandler.recent.some(function (record) {
                        return record.code === "storage";
                    }), "failure is recorded");
                    done("");
                } catch (error) {
                    done(error.message);
                }
            });
        });
    }

    // The settings action is also valid before any cache directory has ever been created.
    function async_missing_directory_is_an_empty_cache(done) {
        make(freshDirectory("absent-cache"), firstUid);
        CacheMaintenance.clearAll(function (success) {
            done(success ? "" : "missing directory was treated as an error");
        });
    }

    // Use one temporary directory per case; every registered writer is destroyed before the next case.
    function make(directory, uid): MarketCache {
        let cache = cacheType.createObject(null, {
            directory: directory,
            snapshotOf: function () {
                return {
                    price: {
                        close: 12
                    }
                };
            }
        }) as MarketCache;
        caches.push(cache);
        cache.markDirty(uid);
        return cache;
    }

    // Keep logging deterministic and avoid notifications from intentional failure injection.
    function setup() {
        teardown();
        ErrorHandler.reset();
        ErrorHandler.configure({
            notify: function () {}
        });
        Logger.configure({
            isDevMode: false
        });
    }

    // All deletion targets are below the temporary cache root supplied by the runner.
    function teardown() {
        caches.forEach(function (cache) {
            cache.destroy();
        });
        caches = [];
    }
}
