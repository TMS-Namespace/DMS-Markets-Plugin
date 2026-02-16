import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "marketsPlugin"

    property var symbolsList: []
    property bool isValidating: false
    property int editIndex: -1    // -1 = adding new, >= 0 = editing existing

    // Symbol search
    property var searchResults: []
    property bool isSearching: false

    // ── Explicit save/load via pluginService (matches DankNotepadModule pattern) ─
    function saveValue(key, value) {
        if (pluginService)
            pluginService.savePluginData(root.pluginId, key, value)
    }

    function loadValue(key, defaultValue) {
        if (pluginService)
            return pluginService.loadPluginData(root.pluginId, key, defaultValue)
        return defaultValue
    }

    function refreshSymbolsList() {
        var raw = loadValue("symbols", "[]")
        try { symbolsList = JSON.parse(raw) }
        catch (e) { symbolsList = [] }
    }

    // pluginService may not be ready at Component.onCompleted
    onPluginServiceChanged: {
        if (pluginService)
            refreshSymbolsList()
    }

    Component.onCompleted: refreshSymbolsList()

    StyledText {
        width: parent.width
        text: "Markets Plugin"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Track live prices for currencies, stocks, commodities, and crypto.\nNote: futures (.f) symbols show prices but charts may be unavailable."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    // ── Global color settings ────────────────────────────────────────────────
    StyledText {
        width: parent.width
        text: "Chart Colors"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.DemiBold
        color: Theme.surfaceText
        topPadding: Theme.spacingM
    }

    StringSetting {
        id: upColorInput
        settingKey: "upColor"
        label: "Up / Positive Color"
        description: "Hex color for positive changes (e.g., #4CAF50)"
        placeholder: "#4CAF50"
        defaultValue: "#4CAF50"
    }

    StringSetting {
        id: downColorInput
        settingKey: "downColor"
        label: "Down / Negative Color"
        description: "Hex color for negative changes (e.g., #F44336)"
        placeholder: "#F44336"
        defaultValue: "#F44336"
    }

    // Color preview
    Row {
        width: parent.width
        spacing: Theme.spacingM

        Row {
            spacing: Theme.spacingS
            Rectangle {
                width: 16; height: 16; radius: 3
                color: (upColorInput.value || "").trim() !== "" ? upColorInput.value.trim() : "#4CAF50"
                border.color: Theme.outlineVariant; border.width: 1
            }
            StyledText {
                text: "Up"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Row {
            spacing: Theme.spacingS
            Rectangle {
                width: 16; height: 16; radius: 3
                color: (downColorInput.value || "").trim() !== "" ? downColorInput.value.trim() : "#F44336"
                border.color: Theme.outlineVariant; border.width: 1
            }
            StyledText {
                text: "Down"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outlineVariant
    }

    StyledText {
        width: parent.width
        text: root.editIndex >= 0 ? "Edit Symbol" : "Add New Symbol"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.DemiBold
        color: Theme.surfaceText
        topPadding: Theme.spacingM
    }

    // ── Symbol Search ─────────────────────────────────────────────────────
    StringSetting {
        id: searchInput
        settingKey: "_searchQuery"
        label: "Search Stooq Symbols"
        description: "Type to search for symbols (e.g., eur, gold, btc, apple)"
        placeholder: "Search…"
        defaultValue: ""
    }

    Item {
        width: parent.width
        height: searchBtn.height

        Rectangle {
            id: searchBtn
            width: 120
            height: 36
            radius: Theme.cornerRadius

            property bool canSearch: (searchInput.value || "").trim().length >= 2 && !root.isSearching

            color: canSearch
                ? (searchBtnMouse.containsMouse ? Theme.primary : Theme.surfaceContainerHighest)
                : Theme.surfaceContainerHigh
            border.color: canSearch ? Theme.primary : Theme.outlineVariant
            border.width: 1
            opacity: canSearch ? 1.0 : 0.5

            StyledText {
                anchors.centerIn: parent
                text: root.isSearching ? "Searching…" : "Search"
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: searchBtn.canSearch
                    ? (searchBtnMouse.containsMouse ? Theme.surfaceContainer : Theme.primary)
                    : Theme.surfaceVariantText
            }

            MouseArea {
                id: searchBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: searchBtn.canSearch ? Qt.PointingHandCursor : Qt.ArrowCursor
                enabled: searchBtn.canSearch
                onClicked: root.doSearch()
            }
        }
    }

    // Search results
    Repeater {
        model: root.searchResults

        delegate: Item {
            width: root.width
            height: 44

            Rectangle {
                anchors.fill: parent
                radius: Theme.cornerRadius
                color: srMouse.containsMouse ? Theme.primaryContainer : Theme.surfaceContainerHigh

                MouseArea {
                    id: srMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.saveValue("_addTicker", modelData.id)
                        root.saveValue("_addName", modelData.name)
                        root.searchResults = []
                        Qt.callLater(function() { root.refreshSymbolsList() })
                    }
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingS
                    spacing: Theme.spacingS

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 90 - Theme.spacingS

                        StyledText {
                            text: modelData.id || ""
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        StyledText {
                            text: (modelData.name || "") + "  ·  " + (modelData.market || "")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    StyledText {
                        width: 90
                        anchors.verticalCenter: parent.verticalCenter
                        text: (modelData.price || "") + "  " + (modelData.changeStr || "")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    Rectangle {
        visible: root.searchResults.length > 0
        width: parent.width
        height: 1
        color: Theme.outlineVariant
    }

    StringSetting {
        id: tickerInput
        settingKey: "_addTicker"
        label: "Symbol Ticker"
        description: "Provider-specific symbol — fill manually or pick from search above"
        placeholder: "eurusd"
        defaultValue: ""
    }

    StringSetting {
        id: nameInput
        settingKey: "_addName"
        label: "Display Name"
        description: "Short label shown in the bar and popup (e.g., EUR/USD, Gold)"
        placeholder: "EUR/USD"
        defaultValue: ""
    }

    SelectionSetting {
        id: providerSelect
        settingKey: "_addProvider"
        label: "Data Provider"
        description: "Source for price data"
        options: [
            { label: "Stooq", value: "stooq" }
        ]
        defaultValue: "stooq"
    }

    SelectionSetting {
        id: priceRangeSelect
        settingKey: "_addPriceRange"
        label: "Price Range"
        description: "Candle period for price display and change calculation"
        options: [
            { label: "1 Minute",    value: "1m"  },
            { label: "5 Minutes",   value: "5m"  },
            { label: "15 Minutes",  value: "15m" },
            { label: "1 Hour",      value: "1h"  },
            { label: "1 Day",       value: "1d"  },
            { label: "1 Week",      value: "1w"  },
            { label: "1 Month",     value: "1M"  }
        ]
        defaultValue: "1h"
    }

    SelectionSetting {
        id: chartRangeSelect
        settingKey: "_addChartRange"
        label: "Chart Range"
        description: "How much historical data to show in the popup sparkline"
        options: [
            { label: "1 Week",     value: "1W"  },
            { label: "1 Month",    value: "1M"  },
            { label: "3 Months",   value: "3M"  },
            { label: "6 Months",   value: "6M"  },
            { label: "1 Year",     value: "1Y"  },
            { label: "2 Years",    value: "2Y"  },
            { label: "5 Years",    value: "5Y"  },
            { label: "10 Years",   value: "10Y" }
        ]
        defaultValue: "1M"
    }

    ToggleSetting {
        id: showChangeToggle
        settingKey: "_addShowChange"
        label: "Show Change When Pinned"
        description: "Display price change in the bar when this symbol is pinned"
        defaultValue: false
    }

    Item {
        width: parent.width
        height: 44

        Row {
            anchors.fill: parent
            spacing: Theme.spacingS

            Rectangle {
                id: addBtn
                width: root.editIndex >= 0 ? parent.width - cancelBtn.width - Theme.spacingS : parent.width
                height: parent.height
                radius: Theme.cornerRadius

                property bool canAdd: {
                    var t = (tickerInput.value || "").trim()
                    var n = (nameInput.value || "").trim()
                    return t !== "" && n !== "" && !root.isValidating
                }

                color: canAdd
                    ? (addBtnMouse.containsMouse ? Theme.primary : Theme.surfaceContainerHighest)
                    : Theme.surfaceContainerHigh
                border.color: canAdd ? Theme.primary : Theme.outlineVariant
                border.width: 1
                opacity: canAdd ? 1.0 : 0.5

                StyledText {
                    anchors.centerIn: parent
                    text: root.isValidating ? "Verifying…"
                        : (root.editIndex >= 0 ? "Update Symbol" : "Add Symbol")
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: addBtn.canAdd
                        ? (addBtnMouse.containsMouse ? Theme.surfaceContainer : Theme.primary)
                        : Theme.surfaceVariantText
                }

                MouseArea {
                    id: addBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: addBtn.canAdd ? Qt.PointingHandCursor : Qt.ArrowCursor
                    enabled: addBtn.canAdd
                    onClicked: root.validateAndAdd()
                }
            }

            Rectangle {
                id: cancelBtn
                width: 80
                height: parent.height
                radius: Theme.cornerRadius
                visible: root.editIndex >= 0
                color: cancelMouse.containsMouse ? Theme.error : Theme.surfaceContainerHighest
                border.color: Theme.error
                border.width: 1

                StyledText {
                    anchors.centerIn: parent
                    text: "Cancel"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: cancelMouse.containsMouse ? Theme.surfaceContainer : Theme.error
                }

                MouseArea {
                    id: cancelMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.cancelEdit()
                }
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outlineVariant
    }

    StyledText {
        width: parent.width
        text: "Configured Symbols"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.DemiBold
        color: Theme.surfaceText
        topPadding: Theme.spacingS
    }

    Repeater {
        model: root.symbolsList

        delegate: Item {
            width: root.width
            height: 56

            Rectangle {
                anchors.fill: parent
                radius: Theme.cornerRadius
                color: root.editIndex === index
                    ? Theme.primaryContainer
                    : (symRowMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)

                MouseArea {
                    id: symRowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.editSymbol(index)
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingS
                    spacing: Theme.spacingS

                    DankIcon {
                        name: "push_pin"
                        size: 18
                        color: modelData.pinned ? Theme.primary : Theme.surfaceContainerHighest
                        anchors.verticalCenter: parent.verticalCenter
                        rotation: modelData.pinned ? 0 : 45
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 18 - 80 - Theme.spacingS * 3

                        StyledText {
                            text: modelData.name || modelData.id || ""
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        StyledText {
                            text: (modelData.id || "") + "  |  " + (modelData.provider || "stooq") + "  |  price " + (modelData.priceInterval || "1M") + "  |  chart " + (modelData.graphInterval || "1M") + (modelData.showChangeWhenPinned ? "  |  Δ on bar" : "")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        // Move up button
                        MouseArea {
                            width: 24
                            height: 24
                            cursorShape: index > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                            hoverEnabled: true
                            enabled: index > 0
                            onClicked: root.moveSymbol(index, -1)

                            DankIcon {
                                anchors.centerIn: parent
                                name: "arrow_upward"
                                size: 16
                                color: index > 0
                                    ? (parent.containsMouse ? Theme.primary : Theme.surfaceVariantText)
                                    : Theme.surfaceContainerHighest
                            }
                        }

                        // Move down button
                        MouseArea {
                            width: 24
                            height: 24
                            cursorShape: index < root.symbolsList.length - 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                            hoverEnabled: true
                            enabled: index < root.symbolsList.length - 1
                            onClicked: root.moveSymbol(index, 1)

                            DankIcon {
                                anchors.centerIn: parent
                                name: "arrow_downward"
                                size: 16
                                color: index < root.symbolsList.length - 1
                                    ? (parent.containsMouse ? Theme.primary : Theme.surfaceVariantText)
                                    : Theme.surfaceContainerHighest
                            }
                        }

                        // Delete button
                        MouseArea {
                            width: 24
                            height: 24
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onClicked: root.removeSymbolAt(index)

                            DankIcon {
                                anchors.centerIn: parent
                                name: "delete"
                                size: 18
                                color: parent.containsMouse ? Theme.error : Theme.surfaceVariantText
                            }
                        }
                    }
                }
            }
        }
    }

    function validateAndAdd() {
        var ticker = (tickerInput.value || "").trim()
        var name   = (nameInput.value || "").trim()
        if (!ticker || !name) return

        // Duplicate check (skip the entry being edited)
        for (var i = 0; i < symbolsList.length; i++) {
            if (i === editIndex) continue
            if (symbolsList[i].id === ticker) {
                ToastService.showError("Markets", "'" + ticker + "' is already added")
                return
            }
        }

        // When editing and ticker unchanged, skip re-validation
        if (editIndex >= 0 && symbolsList[editIndex].id === ticker) {
            doSaveSymbol(ticker, name)
            return
        }

        // Validate symbol exists on Stooq
        var url = "https://stooq.com/q/l/?s=" + encodeURIComponent(ticker) + "&i=d"
        var xhr = new XMLHttpRequest()
        isValidating = true

        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                isValidating = false
                if (xhr.status === 200 && xhr.responseText && xhr.responseText.trim()) {
                    var line   = xhr.responseText.trim().split("\n")[0]
                    var fields = line.split(",")
                    if (fields.length >= 7 && fields[6] !== "N/D" && !isNaN(parseFloat(fields[6]))) {
                        doSaveSymbol(ticker, name)
                    } else {
                        ToastService.showError("Markets", "Symbol '" + ticker + "' not found on Stooq")
                    }
                } else {
                    ToastService.showError("Markets", "Could not verify '" + ticker + "' — check connection")
                }
            }
        }
        xhr.open("GET", url)
        xhr.send()
    }

    function doSaveSymbol(ticker, name) {
        var provider   = providerSelect.value || "stooq"
        var priceRange = priceRangeSelect.value || "1h"
        var chartRange = chartRangeSelect.value || "1M"
        var showChange = showChangeToggle.value || false

        var syms = JSON.parse(JSON.stringify(symbolsList))
        var entry = {
            id: ticker,
            name: name,
            provider: provider,
            priceInterval: priceRange,
            graphInterval: chartRange,
            showChangeWhenPinned: showChange,
            pinned: false
        }

        if (editIndex >= 0 && editIndex < syms.length) {
            entry.pinned = syms[editIndex].pinned
            syms[editIndex] = entry
            ToastService.showInfo("Markets", "Updated " + name + " (" + ticker + ")")
        } else {
            syms.push(entry)
            ToastService.showInfo("Markets", "Added " + name + " (" + ticker + ")")
        }

        root.saveValue("symbols", JSON.stringify(syms))
        symbolsList = syms
        clearForm()
    }

    function editSymbol(idx) {
        if (idx < 0 || idx >= symbolsList.length) return
        // Toggle: clicking the already-selected symbol deselects it
        if (editIndex === idx) { cancelEdit(); return }
        var sym = symbolsList[idx]
        editIndex = idx
        root.saveValue("_addTicker", sym.id || "")
        root.saveValue("_addName", sym.name || "")
        root.saveValue("_addProvider", sym.provider || "stooq")
        root.saveValue("_addPriceRange", sym.priceInterval || "1h")
        root.saveValue("_addChartRange", sym.graphInterval || "1M")
        root.saveValue("_addShowChange", sym.showChangeWhenPinned ? true : false)
        // Force SelectionSettings to re-read from pluginData after save
        Qt.callLater(function() { refreshSymbolsList() })
    }

    function cancelEdit() {
        clearForm()
    }

    function clearForm() {
        editIndex = -1
        root.saveValue("_addTicker", "")
        root.saveValue("_addName", "")
        root.saveValue("_addPriceRange", "1h")
        root.saveValue("_addChartRange", "1M")
        root.saveValue("_addShowChange", false)
        refreshSymbolsList()
    }

    function doSearch() {
        var query = (searchInput.value || "").trim()
        if (query.length < 2) return
        isSearching = true
        searchResults = []

        var url = "https://stooq.com/cmp/?q=" + encodeURIComponent(query)
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                isSearching = false
                if (xhr.status === 200 && xhr.responseText) {
                    var text = xhr.responseText
                    // Extract content from window.cmp_r('...')
                    var start = text.indexOf("'")
                    var end   = text.lastIndexOf("'")
                    if (start >= 0 && end > start) {
                        var inner = text.substring(start + 1, end)
                        // Remove HTML bold tags
                        inner = inner.replace(/<b>/g, "").replace(/<\/b>/g, "")
                        var entries = inner.split("|")
                        var results = []
                        for (var i = 0; i < entries.length; i++) {
                            var parts = entries[i].split("~")
                            if (parts.length >= 5) {
                                results.push({
                                    id:        parts[0].toLowerCase(),
                                    name:      parts[1],
                                    market:    parts[2],
                                    price:     parts[3],
                                    changeStr: parts[4]
                                })
                            }
                        }
                        searchResults = results
                        if (results.length === 0)
                            ToastService.showInfo("Markets", "No results for '" + query + "'")
                    }
                } else {
                    ToastService.showError("Markets", "Search failed — check connection")
                }
            }
        }
        xhr.open("GET", url)
        xhr.send()
    }

    function removeSymbolAt(idx) {
        var syms = JSON.parse(JSON.stringify(symbolsList))
        if (idx < 0 || idx >= syms.length) return
        var removed = syms[idx]
        syms.splice(idx, 1)
        root.saveValue("symbols", JSON.stringify(syms))
        symbolsList = syms
        if (editIndex === idx) clearForm()
        else if (editIndex > idx) editIndex--
        ToastService.showInfo("Markets", "Removed " + (removed.name || removed.id))
    }

    function moveSymbol(idx, direction) {
        var newIdx = idx + direction
        var syms = JSON.parse(JSON.stringify(symbolsList))
        if (newIdx < 0 || newIdx >= syms.length) return
        var tmp = syms[idx]
        syms[idx] = syms[newIdx]
        syms[newIdx] = tmp
        root.saveValue("symbols", JSON.stringify(syms))
        symbolsList = syms
        // Update editIndex if the edited item moved
        if (editIndex === idx) editIndex = newIdx
        else if (editIndex === newIdx) editIndex = idx
    }
}
