// MarketCache.qml - the last market data of every symbol, kept on disk so the popup has something to
// show right after a start while the providers are still being asked.
//
// One file per symbol, `<uid>.json` in `directory`; only the latest update stays: every write replaces the
// symbol's earlier data. Loading and saving are asynchronous and never block the UI.
//   • load(uids, callback)   reads the newest readable file of each symbol; callback(records) gets
//                            { uid: record } for the symbols that have data. A missing, unreadable or damaged
//                            file is NOT an error: it is logged and the symbol starts as on a first run.
//   • markDirty(uid)         the symbol has newer data: it is written in the background after a short delay
//                            (updates in that time become one write). The data written is whatever
//                            `snapshotOf(uid)` returns when the write starts.
//   • discard(uid)           the symbol was removed: its files are deleted.
// Reads and writes are retried. A symbol's file that cannot be written (even after the retries) is not given
// up on: the data goes to a new file `<uid>-<random>.json`; reading takes the newest file of the symbol by
// modification time (trying the older ones if it is unreadable), and after a successful write the symbol's
// other files are deleted.
//
// A record is plain data: { version, uid, savedAt, signature, price, reference, graph, refreshedAt }
//   signature    what the symbol's fetching depends on (data of another configuration must not be reused)
//   price        a PriceInfo's fields, or null            reference  the change reference close, or null
//   graph        the chart's candles (DataPoint fields), or null
//   refreshedAt  { price, change, graph }: epoch ms of each successful pull, or null  (drives "x min ago")

import QtQuick
import Quickshell
import Quickshell.Io
import "../../JS/Contracts/PluginError.js" as PluginError
import "../../JS/Helpers/Constants.js" as JsConstants

Item {
    id: root

    property bool _directoryReady: false

    // ── State ─────────────────────────────────────────────────────────────────
    property var _dirty: ({})       // uids with data not yet written
    property int _processCount: 0
    property var _processQueue: []
    property var _removed: ({})       // uids discarded while a write was in progress
    readonly property var _uidPattern: /^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$/
    property var _writing: ({})       // uids with a write in progress (one at a time per symbol)
    property int attempts: JsConstants.CACHE_ATTEMPTS

    // ── Outputs ───────────────────────────────────────────────────────────────
    // Number of reads, writes and clean-ups in progress or waiting; 0 = everything asked for is on disk.
    property int busy: 0

    // ── Configuration ─────────────────────────────────────────────────────────
    readonly property string defaultDirectory: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/" + JsConstants.CACHE_DIR_NAME
    property string directory: defaultDirectory
    property int flushDelayMs: JsConstants.CACHE_FLUSH_DELAY_MS
    property int maxFallbacks: JsConstants.CACHE_MAX_FALLBACKS
    property int retryDelayMs: JsConstants.CACHE_RETRY_MS
    // function(uid) → the symbol's current record (see above, without version/uid/savedAt), or null for nothing to save.
    property var snapshotOf: null

    signal writeGaveUp(string uid)                    // no file name could be written

    signal written(string uid, string fileName)       // a symbol's data reached the disk

    // Write the snapshot atomically after ensuring its directory exists.
    function _attemptWrite(uid, text, name, attempt, fallbacksUsed) {
        _ensureDirectory(function (ready) {
            if (!ready) {
                _writeFailed(uid, text, name, attempt, fallbacksUsed, "no directory");
                return;
            }
            busy++;
            let settled = false;
            let writer = null;
            // Finish this file operation once and release its file object.
            function settle(action) {
                if (settled)
                    return;
                settled = true;
                busy--;
                writer.destroy();
                action();
            }
            writer = writerType.createObject(root, {
                path: directory + "/" + name,
                whenSaved: function () {
                    settle(function () {
                        _writeSucceeded(uid, name);
                    });
                },
                whenFailed: function (error) {
                    settle(function () {
                        _writeFailed(uid, text, name, attempt, fallbacksUsed, String(error));
                    });
                }
            });
            writer.setText(text);
        });
    }

    // Create the cache directory when it has not yet been checked.
    function _ensureDirectory(callback) {
        if (_directoryReady) {
            callback(true);
            return;
        }
        _run(["mkdir", "-p", "--", directory], function (code) {
            _directoryReady = code === 0;
            if (!_directoryReady)
                Logger.debug("cache", "could not create the data directory (exit " + code + ")");
            callback(_directoryReady);
        });
    }

    // Return a new state map with the requested flag set or removed.
    function _flag(map, uid, on) {
        let copy = Object.assign({}, map);
        if (on)
            copy[uid] = true;
        else
            delete copy[uid];
        return copy;
    }
    // Run the action after a one-shot delay.
    function _later(delayMs, action) {
        laterType.createObject(root, {
            interval: delayMs,
            action: action,
            running: true
        });
    }

    // The symbol's files, newest first by modification time.
    function _listFiles(uid, callback) {
        // Regular files only (-d: never list a directory's contents), newest first.
        let script = 'cd "$1" 2>/dev/null && ls -1td -- "$2.json" "$2"-*.json 2>/dev/null | while read -r f; do [ -f "$f" ] && echo "$f"; done; true';
        _run(["sh", "-c", script, "sh", directory, uid], function (code, text) {
            callback(text.split("\n").filter(function (name) {
                return name !== "";
            }));
        });
    }

    // Require the supported cache version and matching symbol handle.
    function _parseRecord(uid, text) {
        let record = JSON.parse(text);
        if (!record || typeof record !== "object" || Array.isArray(record))
            throw _unusable("not a record");
        if (record.version !== JsConstants.CACHE_FORMAT_VERSION)
            throw _unusable("format version " + record.version);
        if (record.uid !== uid)
            throw _unusable("belongs to another symbol");
        return record;
    }

    // Serialize shell work; callbacks can queue more work without starting overlapping processes.
    function _pumpProcesses() {
        if (_processCount > 0 || _processQueue.length === 0)
            return;
        let job = _processQueue[0];
        _processQueue = _processQueue.slice(1);
        _processCount++;
        // Release the completed process slot and run its callback.
        function finished(code, text) {
            busy--;
            _processCount--;
            try {
                job.callback(code, text);
            } finally {
                Qt.callLater(root._pumpProcesses);
            }
        }
        try {
            let process = runType.createObject(root, {
                command: job.command,
                done: finished,
                running: true
            });
            if (!process)
                throw PluginError.internal("could not create a cache process");
        } catch (caughtError) {
            Logger.debug("cache", "could not run " + job.command[0] + ": " + String(caughtError && caughtError.message));
            Qt.callLater(function () {
                finished(-1, "");
            });
        }
    }

    // callback(record or null). A failed read is tried again; a file that reads but is not a valid record is not.
    function _readFile(uid, name, attempt, callback) {
        busy++;
        let settled = false;
        let reader = null;
        // Finish this file operation once and release its file object.
        function settle(record) {
            if (settled)
                return;
            settled = true;
            busy--;
            reader.destroy();
            callback(record);
        }
        // Parse a loaded cache file and complete the read.
        function loaded() {
            let record = null;
            try {
                record = _parseRecord(uid, reader.text());
            } catch (caughtError) {
                Logger.debug("cache", name + " is not usable: " + String(caughtError && caughtError.message));
            }
            settle(record);
        }
        // Retry a failed cache read or complete it without a record.
        function failed(error) {
            if (attempt < attempts) {
                Logger.debug("cache", "reading " + name + " failed (attempt " + attempt + "/" + attempts + "), trying again");
                settled = true;
                busy--;
                reader.destroy();
                _later(retryDelayMs, function () {
                    _readFile(uid, name, attempt + 1, callback);
                });
            } else {
                Logger.debug("cache", "reading " + name + " failed " + attempts + " times: skipped");
                settle(null);
            }
        }
        reader = readerType.createObject(root, {
            path: directory + "/" + name,
            whenLoaded: loaded,
            whenFailed: failed
        });
    }

    // Find the newest readable saved record for one symbol.
    function _readSymbol(uid, callback) {
        _listFiles(uid, function (names) {
            if (names.length === 0) {
                Logger.debug("cache", "no saved data for " + uid + " (first run)");
                callback(null);
                return;
            }
            _tryFiles(uid, names, 0, callback);
        });
    }

    // Runs a program (argument list); callback(exitCode, stdout) afterwards. A program that cannot start counts as failed.
    function _run(command, callback) {
        if (_processQueue.length >= JsConstants.CACHE_PROCESS_QUEUE_MAX) {
            Logger.debug("cache", "shell queue is full: deferring to the caller's failure handling");
            Qt.callLater(function () {
                callback(-1, "");
            });
            return;
        }
        busy++;
        _processQueue = _processQueue.concat([
            {
                command: command,
                callback: callback
            }
        ]);
        _pumpProcesses();
    }

    // Snapshot dirty data and begin a bounded write attempt.
    function _startWrite(uid) {
        _dirty = _flag(_dirty, uid, false);
        let record = null;
        try {
            record = snapshotOf ? snapshotOf(uid) : null;
        } catch (caughtError) {
            Logger.debug("cache", "no snapshot of " + uid + ": " + String(caughtError && caughtError.message));
        }
        if (!record)
            return;
        _writing = _flag(_writing, uid, true);
        busy++;
        record.version = JsConstants.CACHE_FORMAT_VERSION;
        record.uid = uid;
        record.savedAt = Date.now();
        _attemptWrite(uid, JSON.stringify(record), fileNameOf(uid), 1, 0);
    }

    // Try the remaining cache files from newest to oldest.
    function _tryFiles(uid, names, index, callback) {
        if (index >= names.length) {
            Logger.debug("cache", "none of the " + names.length + " saved files of " + uid + " could be read: starting empty");
            callback(null);
            return;
        }
        _readFile(uid, names[index], 1, function (record) {
            if (record)
                callback(record);
            else
                _tryFiles(uid, names, index + 1, callback);
        });
    }

    // Build a typed error explaining why cached data cannot be restored.
    function _unusable(detail) {
        return new PluginError.PluginError(PluginError.Code.STORAGE, "Saved market data couldn't be read.", detail);
    }

    // Release the write slot and handle newer data or a pending removal.
    function _writeEnded(uid) {
        _writing = _flag(_writing, uid, false);
        busy--;
        if (_dirty[uid]) {
            _startWrite(uid);
            return;
        }            // newer data wins over a pending removal
        if (_removed[uid]) {
            _removed = _flag(_removed, uid, false);
            discard(uid);
        }
    }

    // Retry the write or try a bounded number of fallback file names.
    function _writeFailed(uid, text, name, attempt, fallbacksUsed, reason) {
        _directoryReady = false;      // maybe the directory vanished: make sure of it on the next try
        if (attempt < attempts) {
            Logger.debug("cache", "writing " + name + " failed (attempt " + attempt + "/" + attempts + "): " + reason);
            _later(retryDelayMs, function () {
                _attemptWrite(uid, text, name, attempt + 1, fallbacksUsed);
            });
        } else if (fallbacksUsed < maxFallbacks) {
            let other = fallbackNameOf(uid);
            Logger.debug("cache", name + " cannot be written (" + reason + "): using " + other);
            _attemptWrite(uid, text, other, 1, fallbacksUsed + 1);
        } else {
            Logger.debug("cache", "no file of " + uid + " could be written: the data is not saved");
            ErrorHandler.handle("cache", new PluginError.PluginError(PluginError.Code.STORAGE, "The latest market data couldn't be saved.", reason), {
                context: "market data of " + uid,
                notify: false
            });
            _writeEnded(uid);
            writeGaveUp(uid);
        }
    }

    // Remove older files after the newest snapshot reaches disk.
    function _writeSucceeded(uid, name) {
        Logger.debug("cache", "saved " + name);
        // Only the latest update stays: the symbol's other files (an older fallback, a stale primary) go.
        let script = 'cd "$1" 2>/dev/null || exit 0; for f in "$2".json "$2"-*.json; do [ "$f" = "$3" ] || rm -f -- "$f"; done';
        _run(["sh", "-c", script, "sh", directory, uid, name], function () {
            _writeEnded(uid);
            written(uid, name);
        });
    }

    // ── Removing ──────────────────────────────────────────────────────────────
    function discard(uid) {
        if (!isValidUid(uid))
            return;
        _dirty = _flag(_dirty, uid, false);
        if (_writing[uid]) {
            _removed = _flag(_removed, uid, true);
            return;
        }   // cleaned when that write ends
        let script = 'cd "$1" 2>/dev/null || exit 0; rm -f -- "$2".json "$2"-*.json';
        _run(["sh", "-c", script, "sh", directory, uid], function () {
            Logger.debug("cache", "removed the saved data of " + uid);
        });
    }
    // Choose a fallback file name after the primary cannot be written.
    function fallbackNameOf(uid) {
        return uid + "-" + (1 + Math.floor(Math.random() * 999999999)) + ".json";
    }
    // Build the primary cache file name for a validated handle.
    function fileNameOf(uid) {
        return uid + ".json";
    }

    // Starts the writes that are due now (also what the timer does).
    function flushNow() {
        flushTimer.stop();
        Object.keys(_dirty).forEach(function (uid) {
            if (!_writing[uid])
                _startWrite(uid);
        });
    }

    // Reject handles that cannot safely identify a cache file.
    function isValidUid(uid) {
        return typeof uid === "string" && _uidPattern.test(uid);
    }

    // ── Loading ───────────────────────────────────────────────────────────────
    // callback(records): { uid: record } for the symbols that have readable saved data.
    function load(uids, callback) {
        let wanted = (uids || []).filter(function (uid) {
            let ok = isValidUid(uid);
            if (!ok)
                Logger.debug("cache", "not loading '" + String(uid).slice(0, 40) + "': not a symbol uid");
            return ok;
        });
        let records = {};
        let left = wanted.length;
        if (left === 0) {
            Qt.callLater(function () {
                callback(records);
            });
            return;
        }
        busy++;
        wanted.forEach(function (uid) {
            _readSymbol(uid, function (record) {
                if (record)
                    records[uid] = record;
                if (--left === 0) {
                    busy--;
                    callback(records);
                }
            });
        });
    }

    // ── Saving ────────────────────────────────────────────────────────────────
    function markDirty(uid) {
        if (!isValidUid(uid)) {
            Logger.debug("cache", "not saving '" + String(uid).slice(0, 40) + "': not a symbol uid");
            return;
        }
        let dirty = Object.assign({}, _dirty);
        dirty[uid] = true;
        _dirty = dirty;
        _removed = _flag(_removed, uid, false);       // new data after a discard: it is kept
        if (!flushTimer.running)
            flushTimer.restart();
    }

    // ── Small async tools ─────────────────────────────────────────────────────
    Component {
        id: runType

        Process {
            id: cacheProcess

            property int _code: -1
            property bool _exited: false
            property bool _streamed: false
            property string _text: ""
            property var done

            // Wait for process exit and stdout completion before delivering the result.
            function _finish() {
                if (!_exited || !_streamed)
                    return;
                let callback = done;
                done = null;
                try {
                    if (callback)
                        callback(_code, _text);
                } finally {
                    destroy();
                }
            }

            stdout: StdioCollector {
                onStreamFinished: {
                    cacheProcess._text = text;
                    cacheProcess._streamed = true;
                    cacheProcess._finish();
                }
            }

            onExited: code => {
                _code = code;
                _exited = true;
                _finish();
            }
        }
    }
    Component {
        id: laterType

        Timer {
            property var action

            repeat: false

            onTriggered: {
                var run = action;
                action = null;
                destroy();
                run();
            }
        }
    }

    // FileView's `loaded` is also a property, so its signals are handled here and passed on.
    Component {
        id: readerType

        FileView {
            property var whenFailed
            property var whenLoaded

            printErrors: false
            watchChanges: false

            onLoadFailed: error => {
                if (whenFailed)
                    whenFailed(error);
            }
            onLoaded: {
                if (whenLoaded)
                    whenLoaded();
            }
        }
    }
    Component {
        id: writerType

        FileView {
            property var whenFailed
            property var whenSaved

            atomicWrites: true
            printErrors: false
            watchChanges: false

            onSaveFailed: error => {
                if (whenFailed)
                    whenFailed(error);
            }
            onSaved: {
                if (whenSaved)
                    whenSaved();
            }
        }
    }
    Timer {
        id: flushTimer

        interval: root.flushDelayMs
        repeat: false

        onTriggered: root.flushNow()
    }
}
