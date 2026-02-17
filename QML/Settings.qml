// Settings.qml — Plugin settings page
//
// Provides the configuration interface for the Markets plugin:
// - Chart colors (up/down)
// - Popup layout (visible rows slider)
// - Symbol search (via SymbolSearch component)
// - Add/edit symbol form
// - Configured symbols list (via ConfiguredSymbol component)

import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Plugins
import qs.Widgets
import "../JS/ProviderInterface.js" as Providers
import "../JS/StooqProvider.js" as StooqProvider

PluginSettings {
    id: root
    pluginId: "markets"

    property var  symbolsList:  []
    property bool isValidating: false
    property int  editIndex:    -1    // -1 = adding new, >= 0 = editing existing

    // ── Persistence helpers ──────────────────────────────────────────────────
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

    onPluginServiceChanged: {
        if (pluginService)
            refreshSymbolsList()
    }

    Component.onCompleted: refreshSymbolsList()

    // ═══════════════════════════════════════════════════════════════════════
    //  HEADER
    // ═══════════════════════════════════════════════════════════════════════

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

    // ═══════════════════════════════════════════════════════════════════════
    //  CHART COLORS
    // ═══════════════════════════════════════════════════════════════════════

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

    // ═══════════════════════════════════════════════════════════════════════
    //  POPUP LAYOUT
    // ═══════════════════════════════════════════════════════════════════════

    StyledText {
        width: parent.width
        text: "Popup Layout"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.DemiBold
        color: Theme.surfaceText
        topPadding: Theme.spacingM
    }

    StringSetting {
        id: popoutRowsInput
        settingKey: "popoutRows"
        label: "Visible Symbol Rows"
        description: ""
        placeholder: "5"
        defaultValue: "5"
        visible: false
    }

    Item {
        width: parent.width
        height: 48

        Column {
            anchors.fill: parent
            spacing: 4

            Row {
                width: parent.width

                StyledText {
                    text: "Visible Symbol Rows"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                }

                Item { width: Theme.spacingS; height: 1 }

                StyledText {
                    text: popoutSlider.value.toFixed(0)
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Bold
                    color: Theme.primary
                }
            }

            Item {
                width: parent.width
                height: 24

                Rectangle {
                    id: sliderTrack
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 4
                    radius: 2
                    color: Theme.surfaceContainerHighest

                    Rectangle {
                        width: (popoutSlider.value - 1) / 49 * parent.width
                        height: parent.height
                        radius: 2
                        color: Theme.primary
                    }
                }

                Rectangle {
                    id: sliderHandle
                    width: 18; height: 18; radius: 9
                    color: sliderMouse.pressed ? Theme.primary : Theme.surfaceContainerHighest
                    border.color: Theme.primary; border.width: 2
                    x: (popoutSlider.value - 1) / 49 * (parent.width - width)
                    anchors.verticalCenter: parent.verticalCenter

                    property real value: {
                        var v = parseInt(popoutRowsInput.value || "5")
                        return (isNaN(v) || v < 1) ? 5 : Math.min(v, 50)
                    }
                }

                QtObject {
                    id: popoutSlider
                    property real value: sliderHandle.value
                }

                MouseArea {
                    id: sliderMouse
                    anchors.fill: parent
                    anchors.topMargin: -8
                    anchors.bottomMargin: -8
                    cursorShape: Qt.PointingHandCursor

                    function updateValue(mouseX) {
                        var ratio = Math.max(0, Math.min(1, mouseX / width))
                        var val   = Math.round(1 + ratio * 49)
                        popoutSlider.value = val
                    }

                    onPressed: function(mouse) { updateValue(mouse.x) }
                    onPositionChanged: function(mouse) { if (pressed) updateValue(mouse.x) }
                    onReleased: {
                        root.saveValue("popoutRows", popoutSlider.value.toFixed(0))
                        Qt.callLater(function() { root.refreshSymbolsList() })
                    }
                }
            }
        }
    }

    Rectangle { width: parent.width; height: 1; color: Theme.outlineVariant }

    // ═══════════════════════════════════════════════════════════════════════
    //  SYMBOL SEARCH + ADD/EDIT
    // ═══════════════════════════════════════════════════════════════════════

    StyledText {
        width: parent.width
        text: root.editIndex >= 0 ? "Edit Symbol" : "Add New Symbol"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.DemiBold
        color: Theme.surfaceText
        topPadding: Theme.spacingM
    }

    SymbolSearch {
        id: symbolSearch
        width: parent.width
        providerId: providerSelect.value || Providers.getDefaultProviderId()

        onSymbolSelected: function(symbolId, symbolName) {
            root.saveValue("_addTicker", symbolId)
            root.saveValue("_addName", symbolName)
            Qt.callLater(function() { root.refreshSymbolsList() })
        }
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
        visible: Providers.getProviderIds().length > 1
        options: Providers.getProviderOptions()
        defaultValue: Providers.getDefaultProviderId()
    }

    SelectionSetting {
        id: priceRangeSelect
        settingKey: "_addPriceRange"
        label: "Price Range"
        description: "Candle period for price display and change calculation"
        options: [
            { label: "1 Minute",   value: "1m"  },
            { label: "5 Minutes",  value: "5m"  },
            { label: "15 Minutes", value: "15m" },
            { label: "1 Hour",     value: "1h"  },
            { label: "1 Day",      value: "1d"  },
            { label: "1 Week",     value: "1w"  },
            { label: "1 Month",    value: "1M"  }
        ]
        defaultValue: "1h"
    }

    SelectionSetting {
        id: chartRangeSelect
        settingKey: "_addChartRange"
        label: "Chart Range"
        description: "How much historical data to show in the popup sparkline"
        options: [
            { label: "1 Week",    value: "1W"  },
            { label: "1 Month",   value: "1M"  },
            { label: "3 Months",  value: "3M"  },
            { label: "6 Months",  value: "6M"  },
            { label: "1 Year",    value: "1Y"  },
            { label: "2 Years",   value: "2Y"  },
            { label: "5 Years",   value: "5Y"  },
            { label: "10 Years",  value: "10Y" }
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

    ToggleSetting {
        id: invertToggle
        settingKey: "_addInvert"
        label: "Invert Value (1/x)"
        description: "Show and chart the reciprocal of the price (e.g., USD/EUR instead of EUR/USD)"
        defaultValue: false
    }

    // ── Add / Update / Cancel buttons ────────────────────────────────────────
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

    Rectangle { width: parent.width; height: 1; color: Theme.outlineVariant }

    // ═══════════════════════════════════════════════════════════════════════
    //  CONFIGURED SYMBOLS LIST
    // ═══════════════════════════════════════════════════════════════════════

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

        delegate: ConfiguredSymbol {
            width: root.width
            symbolData: modelData
            isEditing:  root.editIndex === index
            isFirst:    index === 0
            isLast:     index === root.symbolsList.length - 1

            onClicked:   root.editSymbol(index)
            onRemoved:   root.removeSymbolAt(index)
            onMovedUp:   root.moveSymbol(index, -1)
            onMovedDown: root.moveSymbol(index, 1)
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

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

        // Validate symbol exists via the selected provider
        var provider = providerSelect.value || Providers.getDefaultProviderId()
        var url = Providers.buildValidationUrl(provider, ticker)
        if (!url) { doSaveSymbol(ticker, name); return }

        var xhr = new XMLHttpRequest()
        isValidating = true

        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                isValidating = false
                if (xhr.status === 200 && xhr.responseText) {
                    var result = Providers.parseValidationResponse(provider, xhr.responseText)
                    if (result.valid) {
                        doSaveSymbol(ticker, name)
                    } else {
                        ToastService.showError("Markets", "Symbol '" + ticker + "' — " + (result.message || "not found"))
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
        var provider   = providerSelect.value || Providers.getDefaultProviderId()
        var priceRange = priceRangeSelect.value || "1h"
        var chartRange = chartRangeSelect.value || "1M"
        var showChange = showChangeToggle.value || false
        var invert     = invertToggle.value || false

        var syms  = JSON.parse(JSON.stringify(symbolsList))
        var entry = {
            id:                   ticker,
            name:                 name,
            provider:             provider,
            priceInterval:        priceRange,
            graphInterval:        chartRange,
            showChangeWhenPinned: showChange,
            invert:               invert,
            pinned:               false
        }

        if (editIndex >= 0 && editIndex < syms.length) {
            entry.pinned     = syms[editIndex].pinned
            syms[editIndex]  = entry
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
        var sym  = symbolsList[idx]
        editIndex = idx
        root.saveValue("_addTicker",     sym.id || "")
        root.saveValue("_addName",       sym.name || "")
        root.saveValue("_addProvider",   sym.provider || Providers.getDefaultProviderId())
        root.saveValue("_addPriceRange", sym.priceInterval || "1h")
        root.saveValue("_addChartRange", sym.graphInterval || "1M")
        root.saveValue("_addShowChange", sym.showChangeWhenPinned ? true : false)
        root.saveValue("_addInvert",     sym.invert ? true : false)
        Qt.callLater(function() { refreshSymbolsList() })
    }

    function cancelEdit() { clearForm() }

    function clearForm() {
        editIndex = -1
        root.saveValue("_addTicker", "")
        root.saveValue("_addName", "")
        root.saveValue("_addPriceRange", "1h")
        root.saveValue("_addChartRange", "1M")
        root.saveValue("_addShowChange", false)
        root.saveValue("_addInvert", false)
        refreshSymbolsList()
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
        var syms   = JSON.parse(JSON.stringify(symbolsList))
        if (newIdx < 0 || newIdx >= syms.length) return
        var tmp        = syms[idx]
        syms[idx]      = syms[newIdx]
        syms[newIdx]   = tmp
        root.saveValue("symbols", JSON.stringify(syms))
        symbolsList = syms
        if (editIndex === idx) editIndex = newIdx
        else if (editIndex === newIdx) editIndex = idx
    }
}
