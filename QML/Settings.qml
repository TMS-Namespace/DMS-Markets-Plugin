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
import "./Helpers"
import "./Views"

PluginSettings {
    id: root
    pluginId: "markets"

    Constants { id: c }

    property var  symbolsList:  []
    property bool isValidating: false
    property int  editIndex:    -1    // -1 = adding new, >= 0 = editing existing
    property string _currentApiKey: ""
    property bool   hasApiKey:      _currentApiKey.trim() !== ""

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
        if (pluginService) {
            refreshSymbolsList()
            _initApiKey()
        }
    }

    Component.onCompleted: {
        refreshSymbolsList()
        _initApiKey()
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
        text: "Track live prices for currencies, stocks, commodities, and crypto.\nNote: futures (.f) symbols show prices but charts may be unavailable."
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
                opacity: githubMouseArea.containsMouse ? 1.0 : 0.65
            }

            StyledText {
                text: "Source on GitHub"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.primary
                opacity: githubMouseArea.containsMouse ? 1.0 : 0.65
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: githubMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Qt.openUrlExternally("https://github.com/TMS-Namespace/DMS-Markets-Plugin")
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  API KEY
    // ═══════════════════════════════════════════════════════════════════════

    StyledText {
        width: parent.width
        text: "Data Provider API Key"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingM
    }

    StyledText {
        width: parent.width
        text: "A free Stooq API key is required to fetch market data."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    Item {
        id: apiKeyFieldContainer
        width: parent.width
        height: c.compactRowHeight

        Timer {
            id: apiKeySaveTimer
            interval: c.apiKeySaveDebounceMs
            repeat: false
            onTriggered: {
                var newKey = apiKeyField.text.trim()
                root.saveValue(c.stooqApiKeySettingKey, newKey)
                root._currentApiKey = newKey
                Providers.setApiKey(c.stooqProviderId, newKey)
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.cornerRadius
            color: Theme.surfaceContainer
            border.color: apiKeyField.activeFocus ? Theme.primary : Theme.outlineVariant
            border.width: apiKeyField.activeFocus ? 2 : 1

            TextInput {
                id: apiKeyField
                anchors {
                    left: parent.left
                    right: apiKeyRevealBtn.left
                    top: parent.top
                    bottom: parent.bottom
                    leftMargin: Theme.spacingS
                    rightMargin: Theme.spacingXS
                }
                verticalAlignment: TextInput.AlignVCenter
                echoMode: apiKeyRevealBtn.revealed ? TextInput.Normal : TextInput.Password
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
                clip: true
                selectByMouse: true

                property bool _initializing: false
                onTextChanged: { if (!_initializing) apiKeySaveTimer.restart() }

                Text {
                    anchors.fill: parent
                    text: "Paste your Stooq API key here"
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeMedium
                    verticalAlignment: Text.AlignVCenter
                    visible: apiKeyField.text.length === 0
                }
            }

            Rectangle {
                id: apiKeyRevealBtn
                property bool revealed: false
                width: c.compactRowHeight
                height: c.compactRowHeight
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                color: "transparent"

                DankIcon {
                    name: apiKeyRevealBtn.revealed ? "visibility_off" : "visibility"
                    size: Theme.fontSizeMedium
                    color: apiKeyRevealMouse.containsMouse ? Theme.primary : Theme.surfaceVariantText
                    anchors.centerIn: parent
                }

                MouseArea {
                    id: apiKeyRevealMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: apiKeyRevealBtn.revealed = !apiKeyRevealBtn.revealed
                }
            }
        }
    }

    Column {
        width: parent.width
        spacing: 0

        Item {
            id: apiKeyHelpHeader
            width: parent.width
            height: c.compactRowHeight
            property bool expanded: false

            Row {
                id: apiKeyHelpRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                DankIcon {
                    name: apiKeyHelpHeader.expanded ? "expand_less" : "expand_more"
                    size: Theme.fontSizeSmall
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: "How to get a free Stooq API key"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: apiKeyHelpHeader.expanded = !apiKeyHelpHeader.expanded
            }
        }

        Column {
            id: apiKeyHelpContent
            width: parent.width
            visible: apiKeyHelpHeader.expanded
            spacing: Theme.spacingXS
            topPadding: Theme.spacingXS

            Text {
                width: parent.width
                textFormat: Text.RichText
                text: "1.  Open <a href='https://stooq.com/q/d/?s=eurusd&amp;get_apikey'>stooq.com/q/d/?s=eurusd&amp;get_apikey</a> in your browser."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                linkColor: Theme.primary
                wrapMode: Text.WordWrap
                onLinkActivated: function(link) { Qt.openUrlExternally(link) }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                }
            }
            StyledText {
                width: parent.width
                text: "2.  Enter the captcha code shown on the page."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }
            StyledText {
                width: parent.width
                text: "3.  Copy the CSV download link at the bottom of the page (it contains your apikey value)."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }
            StyledText {
                width: parent.width
                text: "4.  Paste the link in some text editor, and copy the last part (the key) of the link after `apikey=`, and paste it in the above field."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }
        }
    }

    Rectangle { width: parent.width; height: 1; color: Theme.outlineVariant }

    // ═══════════════════════════════════════════════════════════════════════
    //  CHART COLORS
    // ═══════════════════════════════════════════════════════════════════════

    Column {
        id: settingsBody
        width: parent.width
        spacing: Theme.spacingS
        enabled: root.hasApiKey
        opacity: root.hasApiKey ? 1.0 : 0.5
        Behavior on opacity { NumberAnimation { duration: c.apiKeyOpacityAnimMs } }

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
            description: "Hex color for positive changes (e.g., #4CAF50)"
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
            description: "Hex color for negative changes (e.g., #F44336)"
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
                        width: (popoutSlider.value - 1) / 49 * parent.width
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
                    x: (popoutSlider.value - 1) / 49 * (parent.width - width)
                    anchors.verticalCenter: parent.verticalCenter

                    property real value: {
                        var rowCount = parseInt(popoutRowsInput.value || c.defaultPopoutRows)
                        return (isNaN(rowCount) || rowCount < 1) ? c.defaultPopoutRows : Math.min(rowCount, 50)
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
                        var sliderValue = Math.round(1 + ratio * 49)
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
    //  SYMBOL SEARCH + ADD/EDIT
    // ═══════════════════════════════════════════════════════════════════════

    StyledText {
        width: parent.width
        text: root.editIndex >= 0 ? "Edit Symbol" : "Add New Symbol"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
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
        height: c.compactRowHeight

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
                    return ticker !== "" && displayName !== "" && !root.isValidating
                }

                color: canAdd
                    ? (addButtonMouseArea.containsMouse ? Theme.primary : Theme.surfaceContainerHighest)
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
                    onClicked: root.validateAndAdd()
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

    function validateAndAdd() {
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

        // When editing and ticker unchanged, skip re-validation
        if (editIndex >= 0 && symbolsList[editIndex].id === ticker) {
            doSaveSymbol(ticker, name)
            return
        }

        // Validate symbol exists via the selected provider
        var provider = providerSelect.value || Providers.getDefaultProviderId()
        var url = Providers.buildValidationUrl(provider, ticker)
        if (!url) { doSaveSymbol(ticker, name); return }

        var httpRequest = new XMLHttpRequest()
        isValidating = true

        httpRequest.onreadystatechange = function() {
            if (httpRequest.readyState === XMLHttpRequest.DONE) {
                isValidating = false
                if (httpRequest.status === 200 && httpRequest.responseText) {
                    if (Providers.isApiKeyError(httpRequest.responseText)) {
                        ToastService.showError("Markets", "API key missing or invalid — check plugin settings")
                        return
                    }
                    var result = Providers.parseValidationResponse(provider, httpRequest.responseText)
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
        httpRequest.open("GET", url)
        httpRequest.send()
    }

    function doSaveSymbol(ticker, name) {
        var provider   = providerSelect.value || Providers.getDefaultProviderId()
        var priceRange = priceRangeSelect.value || "1h"
        var chartRange = chartRangeSelect.value || "1M"
        var showChange = showChangeToggle.value || false
        var invert     = invertToggle.value || false

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
        root.saveValue("_addTicker",     symbol.id || "")
        root.saveValue("_addName",       symbol.name || "")
        root.saveValue("_addProvider",   symbol.provider || Providers.getDefaultProviderId())
        root.saveValue("_addPriceRange", symbol.priceInterval || "1h")
        root.saveValue("_addChartRange", symbol.graphInterval || "1M")
        root.saveValue("_addShowChange", symbol.showChangeWhenPinned ? true : false)
        root.saveValue("_addInvert",     symbol.invert ? true : false)
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

    function _initApiKey() {
        if (!pluginService) return
        var key = loadValue(c.stooqApiKeySettingKey, "")
        _currentApiKey = key
        Providers.setApiKey(c.stooqProviderId, key)
        if (apiKeyField.text !== key) {
            apiKeyField._initializing = true
            apiKeyField.text = key
            apiKeyField._initializing = false
        }
    }
}
