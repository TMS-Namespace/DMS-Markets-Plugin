// DataStorage.qml - everything that reads or writes the plugin's saved data.
//
// One place owns the storage rules, so no other item touches `pluginService` directly:
//   • every write reports whether it really happened; a failure is shown to the user (toast via
//     ErrorHandler) and never looks like success
//   • damaged saved symbols are never mistaken for "no symbols": the user is told and the raw
//     text is kept in `symbolsBackup` before anything can overwrite it
//   • saved symbols are migrated here (SymbolMigration: legacy field names, uids, supported ranges)
//   • list edits (pin, remove, move, add/update, flag changes) are pure transformations of the
//     list you pass in, followed by one checked save - callers keep their own list state
//   • credentials are read from plugin data and de-obfuscated here
//
// Both the widget and the settings create one (pluginId + pluginService); DMS's PluginSettings
// base class still calls the settings' own saveValue/loadValue, which delegate here.

import QtQuick
import "../Contracts"
import "../../JS/Helpers/Helpers.js" as Helpers
import "../../JS/Contracts/PluginError.js" as PluginError
import "../../JS/Helpers/Constants.js" as JsK

Item {
    id: root

    property string pluginId: ""
    property var    pluginService: null

    // Keep the original protected until its backup has actually reached storage.
    property var _unbackedSymbols: null

    Component { id: savedSymbolType; SavedSymbol {} }

    // ── Raw values ────────────────────────────────────────────────────────────
    function load(key, defaultValue) {
        if (!pluginService) return defaultValue
        return pluginService.loadPluginData(pluginId, key, defaultValue)
    }

    // Returns whether the value was really saved; failures are reported (never silent). Before DMS has attached the
    // plugin service (the settings page is created first and given its service afterwards, and DMS's controls save on
    // every value change, defaults included) there is nothing to save to yet: that is not a failure, nothing is
    // reported, and false is returned.
    function save(key, value) {
        if (!pluginService) {
            Logger.debug("storage", "not saved '" + key + "': the plugin service is not attached yet")
            return false
        }
        try {
            if (key === JsK.STORAGE_SYMBOLS_KEY && _unbackedSymbols !== null) {
                if (!_backup(_unbackedSymbols))
                    throw new PluginError.PluginError(PluginError.Code.STORAGE, "Your changes couldn't be saved.",
                                                      "the damaged saved symbols must be backed up before replacement")
                _unbackedSymbols = null
            }
            _write(key, value)
            Logger.debug("storage", "saved '" + key + "'")
            return true
        } catch (e) {
            var error = PluginError.isPluginError(e) ? e
                : new PluginError.PluginError(PluginError.Code.STORAGE, "Your changes couldn't be saved.", String(e && e.message))
            ErrorHandler.handle("storage", error, { context: key })
            return false
        }
    }

    // One write to the plugin data, tried up to JsK.STORAGE_SAVE_ATTEMPTS times (a write can fail for a moment, e.g. while
    // the settings file is being replaced). A write that reports `false` is a failure too. Throws the last failure.
    function _write(key, value) {
        for (var attempt = 1; ; attempt++) {
            try {
                if (pluginService.savePluginData(pluginId, key, value) === false)
                    throw new PluginError.PluginError(PluginError.Code.STORAGE, "Your changes couldn't be saved.", "the plugin service refused to save '" + key + "'")
                return
            } catch (e) {
                Logger.debug("storage", "saving '" + key + "' failed (attempt " + attempt + "/" + JsK.STORAGE_SAVE_ATTEMPTS + "): " + String(e && e.message))
                if (attempt >= JsK.STORAGE_SAVE_ATTEMPTS) throw e
            }
        }
    }

    // ── Symbols: reading ──────────────────────────────────────────────────────
    // `raw` is the saved text (or an already parsed list). Damaged data is reported and backed
    // up, and reads as an empty list only after that.
    function readSymbols(raw) {
        try {
            var parsed = _parseSymbols(raw)
            Logger.debug("storage", "read " + parsed.length + " saved symbols")
            return parsed
        } catch (e) {
            ErrorHandler.handle("storage", e, { context: "saved symbols" })
            if (typeof raw === "string") {
                _unbackedSymbols = raw
                if (_backup(raw)) _unbackedSymbols = null
            }
            return []
        }
    }

    // The saved text as a list of objects. Empty means no symbols; anything else that is not a JSON list of
    // objects is a STORAGE error (never read as "no symbols", which would let damaged data be overwritten unnoticed).
    function _parseSymbols(raw) {
        if (raw === undefined || raw === null || raw === "") return []
        var parsed
        try {
            parsed = typeof raw === "string" ? JSON.parse(raw) : raw
        } catch (e) {
            throw _unreadableSymbols("symbols is not valid JSON: " + e.message, e)
        }
        if (!Array.isArray(parsed)) throw _unreadableSymbols("symbols is not a list")
        for (var i = 0; i < parsed.length; i++)
            if (!parsed[i] || typeof parsed[i] !== "object" || Array.isArray(parsed[i]))
                throw _unreadableSymbols("symbols[" + i + "] is not an object")
        return parsed
    }

    function _unreadableSymbols(detail, cause) {
        return new PluginError.PluginError(PluginError.Code.STORAGE, "Your saved symbols couldn't be read.", detail,
                                           cause ? { cause: cause } : undefined)
    }

    function _backup(raw) {
        try {
            if (!pluginService)
                throw new PluginError.PluginError(PluginError.Code.STORAGE, "Your saved symbols couldn't be backed up.", "plugin service unavailable")
            _write(JsK.STORAGE_SYMBOLS_BACKUP_KEY, raw)
            Logger.debug("storage", "kept the unreadable saved symbols in '" + JsK.STORAGE_SYMBOLS_BACKUP_KEY + "'")
            return true
        } catch (e) {
            ErrorHandler.handle("storage", PluginError.from(e, PluginError.Code.STORAGE), { context: "backing up saved symbols", notify: false })
            return false
        }
    }

    // Reads the symbols from storage and migrates them; see migrate().
    function loadSymbols() {
        return migrate(readSymbols(load(JsK.STORAGE_SYMBOLS_KEY, "[]"))).symbols
    }

    // ── Symbols: migration ────────────────────────────────────────────────────
    // Brings a list up to date (legacy field names, a unique `uid` per symbol, the closest
    // supported price resolution / chart resolution / chart range) and saves it when anything
    // changed. Returns { symbols, changed, saved }; a failing migration is reported and the list
    // is returned unchanged.
    function migrate(list) {
        var result
        try {
            result = ProvidersManager.migrateSymbols(list)
        } catch (e) {
            ErrorHandler.handle("storage", e, { context: "migrating saved symbols" })
            return { symbols: list, changed: false, saved: false }
        }
        if (!result.changed) return { symbols: result.symbols, changed: false, saved: false }
        Logger.debug("storage", "migrated saved symbols (the list changed and is saved)")
        return { symbols: result.symbols, changed: true, saved: saveSymbols(result.symbols) }
    }

    // ── Symbols: writing ──────────────────────────────────────────────────────
    function saveSymbols(list) {
        Logger.debug("storage", "saving " + list.length + " symbols")
        return save(JsK.STORAGE_SYMBOLS_KEY, JSON.stringify(list))
    }

    function _copy(list) { return JSON.parse(JSON.stringify(list)) }

    function togglePin(list, uid) {
        var copy = _copy(list)
        for (var i = 0; i < copy.length; i++) {
            if (copy[i].uid === uid) {
                copy[i].pinned = !copy[i].pinned
                return saveSymbols(copy)
            }
        }
        return false
    }

    function removeSymbol(list, uid) {
        var copy = list.filter(function(symbol) { return symbol.uid !== uid })
        if (copy.length === list.length) {
            Logger.debug("storage", "remove: no symbol " + uid)
            return false
        }
        return saveSymbols(copy)
    }

    // Removes by position; returns the removed symbol, or null when nothing was removed / saved.
    function removeSymbolAt(list, index) {
        if (index < 0 || index >= list.length) return null
        var copy = _copy(list)
        var removed = copy.splice(index, 1)[0]
        return saveSymbols(copy) ? removed : null
    }

    function moveSymbol(list, index, direction) {
        var target = index + direction
        if (index < 0 || index >= list.length || target < 0 || target >= list.length) return false
        var copy = _copy(list)
        var moved = copy[index]
        copy[index] = copy[target]
        copy[target] = moved
        return saveSymbols(copy)
    }

    // Adds `entry`, or replaces the symbol at `editIndex` (keeping its uid and pinned state).
    // Returns { saved, updated }.
    function upsertSymbol(list, entry, editIndex) {
        // Nothing malformed is written: the entry must be a valid SavedSymbol.
        var candidate = savedSymbolType.createObject(null)
        var known = candidate.toJson()
        for (var field in known) if (entry[field] !== undefined) candidate[field] = entry[field]
        var valid = candidate.valid
        candidate.destroy()
        if (!valid) {
            ErrorHandler.handle("storage", new PluginError.PluginError(PluginError.Code.STORAGE, "A saved symbol is damaged.",
                                "the symbol to save is not valid"), { context: "saving a symbol" })
            return { saved: false, updated: false }
        }
        var copy = _copy(list)
        var updating = editIndex >= 0 && editIndex < copy.length
        if (updating) {
            entry.pinned = copy[editIndex].pinned
            entry.uid    = copy[editIndex].uid || entry.uid
            copy[editIndex] = entry
        } else {
            copy.push(entry)
        }
        return { saved: saveSymbols(copy), updated: updating }
    }

    // Changes some fields of the symbol at `index` (e.g. the per-symbol toggles).
    function updateSymbolAt(list, index, fields) {
        if (index < 0 || index >= list.length) return false
        var copy = _copy(list)
        for (var key in fields) copy[index][key] = fields[key]
        return saveSymbols(copy)
    }

    // ── The "add / edit symbol" form's draft ──────────────────────────────────
    // One stored value per form field (JsK.DRAFT_KEYS), so the form survives closing the settings.
    function loadDraftField(field, defaultValue) { return load(JsK.DRAFT_KEYS[field], defaultValue) }
    function saveDraftField(field, value) { return save(JsK.DRAFT_KEYS[field], value) }

    // Saves every field of a draft; true when all were saved.
    function saveDraft(draft) {
        var allSaved = true
        for (var field in JsK.DRAFT_KEYS)
            if (!saveDraftField(field, draft[field])) allSaved = false
        return allSaved
    }

    // ── Credentials ───────────────────────────────────────────────────────────
    // { providerId: credential } for the providers that need one, de-obfuscated. `data` is the
    // plugin data map (the widget's `pluginData`).
    function readCredentials(data) {
        var result = {}
        ProvidersManager.types.forEach(function(type) {
            var provider = ProvidersManager.handlerFor(type).properties
            if (provider.requiresCredential) {
                result[provider.providerId] = Helpers.deobfuscate((data && data[provider.credentialSettingKey]) || "")
                Logger.debug("storage", "credential for " + provider.providerId + ": " + (result[provider.providerId] ? "present" : "missing"))
            }
        })
        return result
    }

    // ── Settings written by older versions ────────────────────────────────────
    // The current value of the price-change toggle: an old "showPriceRange" value still applies until
    // the renamed setting is touched. `data` is the plugin data map.
    function readShowPriceChange(data) {
        var value = data[JsK.STORAGE_SHOW_PRICE_CHANGE_KEY] !== undefined
                    ? data[JsK.STORAGE_SHOW_PRICE_CHANGE_KEY] : data[JsK.STORAGE_LEGACY_SHOW_PRICE_RANGE_KEY]
        return Helpers.pluginDataBool(value)
    }

    // "showPriceRange" was renamed "showPriceChange": carry an old saved value over once.
    function migrateSettings(data) {
        if (!data || data[JsK.STORAGE_SHOW_PRICE_CHANGE_KEY] !== undefined
                || data[JsK.STORAGE_LEGACY_SHOW_PRICE_RANGE_KEY] === undefined)
            return false
        Logger.debug("storage", "carrying the old '" + JsK.STORAGE_LEGACY_SHOW_PRICE_RANGE_KEY + "' setting over to '" + JsK.STORAGE_SHOW_PRICE_CHANGE_KEY + "'")
        return save(JsK.STORAGE_SHOW_PRICE_CHANGE_KEY, data[JsK.STORAGE_LEGACY_SHOW_PRICE_RANGE_KEY])
    }
}
