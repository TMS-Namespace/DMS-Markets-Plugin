// SymbolErrorMap.js - logic: the latest failure of each pull, per symbol.
//
// A plain errorMap { uid: { price: ErrorRecord, graph: ErrorRecord } } owned by the widget and read by
// the symbol cards. It is never edited in place: `set` returns a new errorMap (so QML bindings notice)
// and drops entries that became empty. A pull that succeeds clears its own error only.
//
//   SymbolErrorMap.set(errorMap, uid, FetchType.Values.PRICE, record)   → new errorMap ( record null clears )
//   SymbolErrorMap.entry(errorMap, uid)                                 → { price?, graph? } (never undefined)
//   SymbolErrorMap.message(entry)                                  → the text a card shows ("" if none)

.pragma library
.import "../Contracts/FetchType.js" as FetchType
.import "Helpers.js" as Helpers


// Read one symbol error entry, defaulting to an empty map.
function entry(errorMap, uid) {
    return (errorMap && errorMap[uid]) || {}
}

// Return an updated error map and remove entries that have recovered.
function set(errorMap, uid, fetchType, record) {
    let current = entry(errorMap, uid)
    if (!record && !current[fetchType]) return errorMap          // nothing to clear: same errorMap, no re-render
    let updated = record ? Helpers.withEntry(current, fetchType, record) : Helpers.withoutEntry(current, fetchType)
    return updated[FetchType.Values.PRICE] || updated[FetchType.Values.GRAPH] ? Helpers.withEntry(errorMap, uid, updated)
                                                                                : Helpers.withoutEntry(errorMap, uid)
}

// A failed price replaces the price and the chart on the card; a failed chart only the chart.
function priceFailed(symbolEntry) { return !!(symbolEntry && symbolEntry[FetchType.Values.PRICE]) }
// Check whether the latest chart pull failed.
function chartFailed(symbolEntry) { return !!(symbolEntry && symbolEntry[FetchType.Values.GRAPH]) }

// Choose the price failure first, otherwise the chart failure.
function _record(symbolEntry) {
    if (priceFailed(symbolEntry)) return symbolEntry[FetchType.Values.PRICE]
    if (chartFailed(symbolEntry)) return symbolEntry[FetchType.Values.GRAPH]
    return null
}

// Read the user-facing text of the selected failure.
function message(symbolEntry) { var record = _record(symbolEntry); return record ? record.userMessage : "" }
// Read the diagnostic details of the selected failure.
function details(symbolEntry) { var record = _record(symbolEntry); return record ? (record.details || "") : "" }
