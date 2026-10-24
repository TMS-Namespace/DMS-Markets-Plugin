// CacheMaintenance.qml - coordinate explicit cache deletion across settings pages and live widget instances.
pragma Singleton
import QtQuick
import "../../JS/Contracts/PluginError.js" as PluginError
import "../../JS/Helpers/Constants.js" as JsConstants

QtObject {
    id: root

    property var _caches: []
    property var _completion: null
    property real _deadline: 0
    property bool _failed: false
    property int _remaining: 0
    property var _targets: []
    property Timer _waiter: Timer {
        interval: 20
        repeat: false

        onTriggered: root._clearWhenIdle()
    }
    property bool clearing: false
    property int generation: 0

    signal clearStarted

    // Let existing reads, atomic writes and retries settle before removing their files.
    function _clearWhenIdle() {
        if (_caches.some(function (cache) {
            return cache && cache.busy > 0;
        })) {
            if (Date.now() >= _deadline) {
                _failed = true;
                _waiter.stop();
                _finish();
            } else {
                _waiter.restart();
            }
            return;
        }
        _waiter.stop();
        let directories = {};
        _targets = _caches.filter(function (cache) {
            if (!cache || directories[cache.directory])
                return false;
            directories[cache.directory] = true;
            return true;
        });
        _remaining = _targets.length;
        if (!_remaining) {
            _finish();
            return;
        }
        _targets.forEach(function (cache) {
            cache.clearStoredFiles(function (success) {
                root._complete(cache, success);
            });
        });
    }

    // Settle each directory once, including a writer destroyed while its cleanup is running.
    function _complete(cache, success) {
        if (_targets.indexOf(cache) === -1)
            return;
        _targets = _targets.filter(function (candidate) {
            return candidate !== cache;
        });
        _failed = _failed || !success;
        if (--_remaining === 0)
            _finish();
    }

    // Resume caching and report one outcome after every distinct cache directory has been handled.
    function _finish() {
        let success = !_failed;
        _caches.forEach(function (cache) {
            if (cache)
                cache.resumeAfterClear();
        });
        let completion = _completion;
        _completion = null;
        _targets = [];
        clearing = false;
        if (!success)
            ErrorHandler.handle("cache", new PluginError.PluginError(PluginError.Code.STORAGE, "The cache couldn't be completely cleared.", "a cache file could not be removed"));
        if (completion)
            completion(success);
    }

    // Clear only after an explicit settings action. Normal reads and writes never trigger this operation.
    function clearAll(completion) {
        if (clearing)
            return false;
        clearing = true;
        _failed = false;
        _deadline = Date.now() + JsConstants.CACHE_CLEAR_TIMEOUT_MS;
        _completion = completion;
        generation++;
        _caches.forEach(function (cache) {
            if (cache)
                cache.pauseForClear();
        });
        clearStarted();
        _waiter.start();
        return true;
    }

    // Track live cache writers, including a settings-owned instance when no bar widget is loaded.
    function registerCache(cache) {
        _caches = _caches.concat([cache]);
        if (clearing)
            cache.pauseForClear();
    }

    // Release destroyed pages and widgets so the registry never retains their cache objects.
    function unregisterCache(cache) {
        _caches = _caches.filter(function (candidate) {
            return candidate && candidate !== cache;
        });
        if (clearing)
            _complete(cache, false);
    }
}
