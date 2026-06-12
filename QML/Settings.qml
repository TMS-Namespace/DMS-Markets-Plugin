// Settings.qml — Plugin settings page
//
// Provides the configuration interface for the Markets plugin:
// - Chart colors (up/down)
// - Popup layout (visible rows slider)
// - Add/edit symbol form
// - Configured symbols list (via ConfiguredSymbol component)

import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Plugins
import qs.Widgets
import "../JS/Helpers.js" as Helpers
import "../JS/ProviderInterface.js" as Providers
import "../JS/ProviderBootstrap.js" as ProviderBootstrap
import "./Helpers"
import "./ProviderSettings"
import "./Views"

PluginSettings {
    id: root
    pluginId: "markets"

    Constants { id: c }

    readonly property int providerRegistrationCount: ProviderBootstrap.ensureProvidersRegistered()
    property var  symbolsList:  []
    property int  editIndex:    -1    // -1 = adding new, >= 0 = editing existing
    property var  providerCredentials: ({})
    readonly property string selectedProviderId: providerSelect.value || Providers.getDefaultProviderId()
    readonly property bool selectedProviderDisabled: Providers.providerIsDisabled(selectedProviderId)

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

    function setProviderCredential(providerId, credential) {
        var copy = {}
        for (var id in providerCredentials) copy[id] = providerCredentials[id]
        copy[providerId] = credential || ""
        providerCredentials = copy
    }

    onPluginServiceChanged: {
        if (pluginService) {
            refreshSymbolsList()
        }
    }

    Component.onCompleted: {
        refreshSymbolsList()
    }

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
        text: c.pluginSubtitle
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    Item {
        width: githubRow.width
        height: githubRow.height

        Row {
            id: githubRow
            spacing: Theme.spacingXS

            DankIcon {
                name: "code"
                size: Theme.fontSizeSmall
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
                opacity: githubMouseArea.containsMouse ? 1.0 : c.linkIdleOpacity
            }

            StyledText {
                text: "Source on GitHub"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.primary
                opacity: githubMouseArea.containsMouse ? 1.0 : c.linkIdleOpacity
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: githubMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Qt.openUrlExternally(c.sourceUrl)
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  CHART COLORS
    // ═══════════════════════════════════════════════════════════════════════

    Column {
        id: settingsBody
        width: parent.width
        spacing: Theme.spacingS

    StyledText {
        width: parent.width
        text: "Chart Colors"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingM
    }

    Row {
        width: parent.width
        spacing: Theme.spacingS

        property real swatchSize: Math.round(Theme.fontSizeMedium * 3.4)

        StringSetting {
            id: upColorInput
            settingKey: "upColor"
            label: "Up / Positive Color"
            description: "Hex color for positive changes (e.g., " + c.defaultUpColor + ")"
            placeholder: c.defaultUpColor
            defaultValue: c.defaultUpColor
            width: parent.width - parent.swatchSize - Theme.spacingS
        }

        Rectangle {
            width: parent.swatchSize; height: parent.swatchSize
            radius: Theme.cornerRadius
            anchors.bottom: parent.bottom
            color: (upColorInput.value || "").trim() !== "" ? upColorInput.value.trim() : c.defaultUpColor
            border.color: Theme.outlineVariant; border.width: 1
        }
    }

    Row {
        width: parent.width
        spacing: Theme.spacingS

        property real swatchSize: Math.round(Theme.fontSizeMedium * 3.4)

        StringSetting {
            id: downColorInput
            settingKey: "downColor"
            label: "Down / Negative Color"
            description: "Hex color for negative changes (e.g., " + c.defaultDownColor + ")"
            placeholder: c.defaultDownColor
            defaultValue: c.defaultDownColor
            width: parent.width - parent.swatchSize - Theme.spacingS
        }

        Rectangle {
            width: parent.swatchSize; height: parent.swatchSize
            radius: Theme.cornerRadius
            anchors.bottom: parent.bottom
            color: (downColorInput.value || "").trim() !== "" ? downColorInput.value.trim() : c.defaultDownColor
            border.color: Theme.outlineVariant; border.width: 1
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  POPUP LAYOUT
    // ═══════════════════════════════════════════════════════════════════════

    StyledText {
        width: parent.width
        text: "Popup Layout"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingM
    }

    StringSetting {
        id: popoutRowsInput
        settingKey: "popoutRows"
        label: "Visible Symbol Rows"
        description: ""
        placeholder: c.defaultPopoutRows
        defaultValue: c.defaultPopoutRows
        visible: false
    }

    Item {
        width: parent.width
        height: c.sliderContainerHeight

        Column {
            anchors.fill: parent
            spacing: 4

            Row {
                width: parent.width

                StyledText {
                    text: "Visible Symbol Rows"
                    font.pixelSize: Theme.fontSizeLarge
                    color: Theme.surfaceText
                }

                Item { width: Theme.spacingS; height: 1 }

                StyledText {
                    text: popoutSlider.value.toFixed(0)
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.Bold
                    color: Theme.primary
                }
            }

            Item {
                width: parent.width
                height: c.sliderAreaHeight

                Rectangle {
                    id: sliderTrack
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: c.sliderTrackHeight
                    radius: c.sliderTrackHeight / 2
                    color: Theme.surfaceContainerHighest

                    Rectangle {
                        width: (popoutSlider.value - c.minPopoutRows)
                               / (c.maxPopoutRows - c.minPopoutRows) * parent.width
                        height: parent.height
                        radius: parent.radius
                        color: Theme.primary
                    }
                }

                Rectangle {
                    id: sliderHandle
                    width: c.sliderHandleSize; height: c.sliderHandleSize; radius: c.sliderHandleSize / 2
                    color: sliderMouse.pressed ? Theme.primary : Theme.surfaceContainerHighest
                    border.color: Theme.primary; border.width: 2
                    x: (popoutSlider.value - c.minPopoutRows)
                       / (c.maxPopoutRows - c.minPopoutRows) * (parent.width - width)
                    anchors.verticalCenter: parent.verticalCenter

                    property real value: {
                        var rowCount = parseInt(popoutRowsInput.value || c.defaultPopoutRows)
                        return (isNaN(rowCount) || rowCount < c.minPopoutRows)
                               ? c.defaultPopoutRows
                               : Math.min(rowCount, c.maxPopoutRows)
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
                        var ratio       = Math.max(0, Math.min(1, mouseX / width))
                        var sliderValue = Math.round(c.minPopoutRows
                                                     + ratio * (c.maxPopoutRows - c.minPopoutRows))
                        popoutSlider.value = sliderValue
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

    StyledText {
        width: parent.width
        text: "Symbol Row Display"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingM
    }

    StyledText {
        width: parent.width
        text: "Choose which details to show for each symbol in the popup"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        settingKey: "showTicker"
        label: "Show Symbol Ticker"
        description: "Show the ticker ID and price interval below the symbol name"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showPriceRange"
        label: "Show Price Change"
        description: "Show the price change amount and percentage"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showChartRange"
        label: "Show Chart Time Range"
        description: "Show the time range label on the sparkline chart"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showRefreshedSince"
        label: "Show Refreshed Since"
        description: "Show how long ago the symbol data was last refreshed"
        defaultValue: true
    }

    Rectangle { width: parent.width; height: 1; color: Theme.outlineVariant }

    // ═══════════════════════════════════════════════════════════════════════
    //  SYMBOL LOOKUP + ADD/EDIT
    // ═══════════════════════════════════════════════════════════════════════

    StyledText {
        width: parent.width
        text: root.editIndex >= 0 ? "Edit Symbol" : "Add New Symbol"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingM
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

    StyledText {
        width: parent.width
        visible: root.selectedProviderDisabled
        text: Providers.getProviderMeta(root.selectedProviderId).disabledMessage
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    Column {
        id: tickerInput
        width: parent.width
        visible: !root.selectedProviderDisabled
        height: visible ? implicitHeight : 0
        spacing: Theme.spacingS

        property alias value: tickerField.text

        Component.onCompleted: Qt.callLater(function() {
            tickerInput.value = root.loadValue("_addTicker", "")
        })

        StyledText {
            text: "Symbol Ticker"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        StyledText {
            text: Providers.getProviderMeta(providerSelect.value || Providers.getDefaultProviderId()).symbolHelpText
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            width: parent.width
            wrapMode: Text.WordWrap
        }

        Row {
            width: parent.width
            height: c.compactRowHeight
            spacing: Theme.spacingS

            DankTextField {
                id: tickerField
                width: parent.width - providerSearchButton.width - Theme.spacingS
                placeholderText: Providers.getProviderMeta(providerSelect.value || Providers.getDefaultProviderId()).symbolPlaceholder
                onEditingFinished: root.saveValue("_addTicker", text.trim())
            }

            Rectangle {
                id: providerSearchButton
                width: Math.min(c.symbolSearchButtonWidth, Math.round(parent.width * 0.48))
                height: parent.height
                radius: Theme.cornerRadius
                color: providerSearchMouseArea.containsMouse ? Theme.primary : Theme.surfaceContainerHighest
                border.color: Theme.primary
                border.width: 1

                Row {
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: c.symbolSearchButtonPadding
                        rightMargin: c.symbolSearchButtonPadding
                    }
                    spacing: Theme.spacingXS

                    DankIcon {
                        name: "open_in_new"
                        size: Theme.fontSizeMedium
                        color: providerSearchMouseArea.containsMouse ? Theme.surfaceContainer : Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "Open symbols search..."
                        width: parent.width - x
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: providerSearchMouseArea.containsMouse ? Theme.surfaceContainer : Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: providerSearchMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var meta = Providers.getProviderMeta(providerSelect.value || Providers.getDefaultProviderId())
                        if (meta.symbolSearchUrl) Qt.openUrlExternally(meta.symbolSearchUrl)
                    }
                }
            }
        }
    }

    Column {
        id: nameInput
        width: parent.width
        visible: !root.selectedProviderDisabled
        height: visible ? implicitHeight : 0
        spacing: Theme.spacingS

        property alias value: nameField.text

        Component.onCompleted: Qt.callLater(function() {
            nameInput.value = root.loadValue("_addName", "")
        })

        StyledText {
            text: "Display Name"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        StyledText {
            text: "Short label shown in the bar and popup (e.g., EUR/USD, Gold)"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            width: parent.width
            wrapMode: Text.WordWrap
        }

        DankTextField {
            id: nameField
            width: parent.width
            placeholderText: "EUR/USD"
            onEditingFinished: root.saveValue("_addName", text.trim())
        }
    }

    SelectionSetting {
        id: priceRangeSelect
        settingKey: "_addPriceRange"
        label: "Price Range"
        description: "Candle period for price display and change calculation"
        visible: !root.selectedProviderDisabled
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
        visible: !root.selectedProviderDisabled
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
        visible: !root.selectedProviderDisabled
        onValueChanged: {
            if (!isInitialized) return
            root.saveEditedSymbolFlags()
        }
    }

    ToggleSetting {
        id: invertToggle
        settingKey: "_addInvert"
        label: "Invert Value (1/x)"
        description: "Show and chart the reciprocal of the price (e.g., USD/EUR instead of EUR/USD)"
        defaultValue: false
        visible: !root.selectedProviderDisabled
        onValueChanged: {
            if (!isInitialized) return
            root.saveEditedSymbolFlags()
        }
    }

    // ── Add / Update / Cancel buttons ────────────────────────────────────────
    Item {
        width: parent.width
        visible: !root.selectedProviderDisabled
        height: visible ? c.compactRowHeight : 0

        Row {
            anchors.fill: parent
            spacing: Theme.spacingS

            Rectangle {
                id: addButton
                width: root.editIndex >= 0 ? parent.width - cancelButton.width - Theme.spacingS : parent.width
                height: parent.height
                radius: Theme.cornerRadius

                property bool canAdd: {
                    var ticker      = (tickerInput.value || "").trim()
                    var displayName = (nameInput.value || "").trim()
                    var provider    = providerSelect.value || Providers.getDefaultProviderId()
                    return ticker !== "" && displayName !== "" && !Providers.providerIsDisabled(provider)
                }

                color: canAdd
                    ? (addButtonMouseArea.containsMouse ? Theme.primary : Theme.surfaceContainerHighest)
                    : Theme.surfaceContainerHigh
                border.color: canAdd ? Theme.primary : Theme.outlineVariant
                border.width: 1
                opacity: canAdd ? 1.0 : 0.5

                StyledText {
                    anchors.centerIn: parent
                    text: root.editIndex >= 0 ? "Update Symbol" : "Add Symbol"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: addButton.canAdd
                        ? (addButtonMouseArea.containsMouse ? Theme.surfaceContainer : Theme.primary)
                        : Theme.surfaceVariantText
                }

                MouseArea {
                    id: addButtonMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: addButton.canAdd ? Qt.PointingHandCursor : Qt.ArrowCursor
                    enabled: addButton.canAdd
                    onClicked: root.addOrUpdateSymbol()
                }
            }

            Rectangle {
                id: cancelButton
                width: c.smallButtonWidth
                height: parent.height
                radius: Theme.cornerRadius
                visible: root.editIndex >= 0
                color: cancelButtonMouseArea.containsMouse ? Theme.error : Theme.surfaceContainerHighest
                border.color: Theme.error
                border.width: 1

                StyledText {
                    anchors.centerIn: parent
                    text: "Cancel"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: cancelButtonMouseArea.containsMouse ? Theme.surfaceContainer : Theme.error
                }

                MouseArea {
                    id: cancelButtonMouseArea
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
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
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

    } // settingsBody

    // ═══════════════════════════════════════════════════════════════════════
    //  FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function addOrUpdateSymbol() {
        var ticker = (tickerInput.value || "").trim()
        var name   = (nameInput.value || "").trim()
        if (!ticker || !name) return

        // Duplicate check (skip the entry being edited)
        for (var symbolIndex = 0; symbolIndex < symbolsList.length; symbolIndex++) {
            if (symbolIndex === editIndex) continue
            if (symbolsList[symbolIndex].id === ticker) {
                ToastService.showError("Markets", "'" + ticker + "' is already added")
                return
            }
        }

        doSaveSymbol(ticker, name)
    }

    function doSaveSymbol(ticker, name) {
        var provider   = providerSelect.value || Providers.getDefaultProviderId()
        var priceRange = priceRangeSelect.value || "1h"
        var chartRange = chartRangeSelect.value || "1M"
        var showChange = Helpers.boolValue(showChangeToggle.value, false)
        var invert     = Helpers.boolValue(invertToggle.value, false)

        var symbolsCopy = JSON.parse(JSON.stringify(symbolsList))
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

        if (editIndex >= 0 && editIndex < symbolsCopy.length) {
            entry.pinned              = symbolsCopy[editIndex].pinned
            symbolsCopy[editIndex]    = entry
            ToastService.showInfo("Markets", "Updated " + name + " (" + ticker + ")")
        } else {
            symbolsCopy.push(entry)
            ToastService.showInfo("Markets", "Added " + name + " (" + ticker + ")")
        }

        root.saveValue("symbols", JSON.stringify(symbolsCopy))
        Qt.callLater(clearForm)
    }

    function editSymbol(symbolIndex) {
        if (symbolIndex < 0 || symbolIndex >= symbolsList.length) return
        // Toggle: clicking the already-selected symbol deselects it
        if (editIndex === symbolIndex) { cancelEdit(); return }
        var symbol = symbolsList[symbolIndex]
        editIndex  = symbolIndex
        setDraftValues(symbol.id || "",
                       symbol.name || "",
                       symbol.provider || Providers.getDefaultProviderId(),
                       symbol.priceInterval || "1h",
                       symbol.graphInterval || "1M",
                       Helpers.boolValue(symbol.showChangeWhenPinned, false),
                       Helpers.boolValue(symbol.invert, false))
        Qt.callLater(function() { refreshSymbolsList() })
    }

    function cancelEdit() { clearForm() }

    function clearForm() {
        editIndex = -1
        setDraftValues("", "",
                       Providers.getDefaultProviderId(),
                       "1h", "1M",
                       false, false)
        refreshSymbolsList()
    }

    function setDraftValues(ticker, name, provider, priceRange, chartRange, showChange, invert) {
        tickerInput.value = ticker
        nameInput.value = name
        providerSelect.value = provider
        priceRangeSelect.value = priceRange
        chartRangeSelect.value = chartRange
        showChangeToggle.value = Helpers.boolValue(showChange, false)
        invertToggle.value = Helpers.boolValue(invert, false)

        root.saveValue("_addTicker", ticker)
        root.saveValue("_addName", name)
        root.saveValue("_addProvider", provider)
        root.saveValue("_addPriceRange", priceRange)
        root.saveValue("_addChartRange", chartRange)
        root.saveValue("_addShowChange", showChangeToggle.value)
        root.saveValue("_addInvert", invertToggle.value)
    }

    function saveEditedSymbolFlags() {
        if (editIndex < 0 || editIndex >= symbolsList.length) return

        var symbolsCopy = JSON.parse(JSON.stringify(symbolsList))
        symbolsCopy[editIndex].showChangeWhenPinned = Helpers.boolValue(showChangeToggle.value, false)
        symbolsCopy[editIndex].invert = Helpers.boolValue(invertToggle.value, false)

        root.saveValue("symbols", JSON.stringify(symbolsCopy))
        refreshSymbolsList()
    }

    function removeSymbolAt(symbolIndex) {
        var symbolsCopy = JSON.parse(JSON.stringify(symbolsList))
        if (symbolIndex < 0 || symbolIndex >= symbolsCopy.length) return
        var removed = symbolsCopy[symbolIndex]
        symbolsCopy.splice(symbolIndex, 1)
        root.saveValue("symbols", JSON.stringify(symbolsCopy))
        var wasEditing = (editIndex === symbolIndex)
        if (editIndex > symbolIndex) editIndex--
        ToastService.showInfo("Markets", "Removed " + (removed.name || removed.id))
        if (wasEditing) Qt.callLater(clearForm)
        else Qt.callLater(refreshSymbolsList)
    }

    function moveSymbol(symbolIndex, direction) {
        var targetIndex = symbolIndex + direction
        var symbolsCopy = JSON.parse(JSON.stringify(symbolsList))
        if (targetIndex < 0 || targetIndex >= symbolsCopy.length) return
        var tempSymbol              = symbolsCopy[symbolIndex]
        symbolsCopy[symbolIndex]    = symbolsCopy[targetIndex]
        symbolsCopy[targetIndex]    = tempSymbol
        root.saveValue("symbols", JSON.stringify(symbolsCopy))
        if (editIndex === symbolIndex) editIndex = targetIndex
        else if (editIndex === targetIndex) editIndex = symbolIndex
        Qt.callLater(refreshSymbolsList)
    }

}
