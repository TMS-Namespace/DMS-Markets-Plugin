import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "marketsPlugin"

    property var symbolsList: []

    function refreshSymbolsList() {
        try { symbolsList = JSON.parse(pluginData.symbols || "[]") }
        catch (e) { symbolsList = [] }
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
        text: "Track live prices for currencies, stocks, commodities, and crypto.\nCommon Stooq tickers: dx.f (USDX), eurusd, gbpusd, gc.f (Gold), si.f (Silver), cl.f (Oil), btcusd, ^spx (S&P 500), ^dji (Dow)"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledText {
        width: parent.width
        text: "Add New Symbol"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.DemiBold
        color: Theme.surfaceText
        topPadding: Theme.spacingM
    }

    StringSetting {
        id: tickerInput
        settingKey: "_addTicker"
        label: "Symbol Ticker"
        description: "Provider-specific symbol (e.g., dx.f, eurusd, gc.f, ^spx)"
        placeholder: "dx.f"
        defaultValue: ""
    }

    StringSetting {
        id: nameInput
        settingKey: "_addName"
        label: "Display Name"
        description: "Short label shown in the bar and popup (e.g., USDX, EUR/USD)"
        placeholder: "USDX"
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
        id: priceIntervalSelect
        settingKey: "_addPriceInterval"
        label: "Price Interval"
        description: "Candle period and update frequency for the displayed price"
        options: [
            { label: "5 minutes",  value: "5m"  },
            { label: "15 minutes", value: "15m" },
            { label: "1 hour",     value: "1h"  },
            { label: "1 day",      value: "1d"  }
        ]
        defaultValue: "1h"
    }

    SelectionSetting {
        id: graphIntervalSelect
        settingKey: "_addGraphInterval"
        label: "Chart Interval"
        description: "Candle period and update frequency for the popup sparkline"
        options: [
            { label: "15 minutes", value: "15m" },
            { label: "1 hour",     value: "1h"  },
            { label: "1 day",      value: "1d"  },
            { label: "1 week",     value: "1w"  }
        ]
        defaultValue: "1d"
    }

    Item {
        width: parent.width
        height: 44

        Rectangle {
            anchors.fill: parent
            radius: Theme.cornerRadius
            color: addBtnMouse.containsMouse ? Theme.primary : Theme.surfaceContainerHighest
            border.color: Theme.primary
            border.width: 1

            StyledText {
                anchors.centerIn: parent
                text: "Add Symbol"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: addBtnMouse.containsMouse ? Theme.surfaceContainer : Theme.primary
            }

            MouseArea {
                id: addBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.addSymbol()
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
                color: Theme.surfaceContainerHigh

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
                        width: parent.width - 18 - 28 - Theme.spacingS * 3

                        StyledText {
                            text: modelData.name || modelData.id || ""
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        StyledText {
                            text: (modelData.id || "") + "  |  " + (modelData.provider || "stooq") + "  |  price " + (modelData.priceInterval || "1h") + "  |  chart " + (modelData.graphInterval || "1d")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    MouseArea {
                        width: 28
                        height: 28
                        anchors.verticalCenter: parent.verticalCenter
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: root.removeSymbolAt(index)

                        DankIcon {
                            anchors.centerIn: parent
                            name: "delete"
                            size: 20
                            color: parent.containsMouse ? Theme.error : Theme.surfaceVariantText
                        }
                    }
                }
            }
        }
    }

    function addSymbol() {
        var ticker = (tickerInput.value || "").trim()
        var name = (nameInput.value || "").trim()
        var provider = providerSelect.value || "stooq"
        var pInt = priceIntervalSelect.value || "1h"
        var gInt = graphIntervalSelect.value || "1d"

        if (!ticker) {
            ToastService.showError("Markets", "Symbol ticker is required")
            return
        }
        if (!name) name = ticker.toUpperCase()

        for (var i = 0; i < symbolsList.length; i++) {
            if (symbolsList[i].id === ticker) {
                ToastService.showError("Markets", "'" + ticker + "' is already added")
                return
            }
        }

        var syms = JSON.parse(JSON.stringify(symbolsList))
        syms.push({
            id: ticker,
            name: name,
            provider: provider,
            priceInterval: pInt,
            graphInterval: gInt,
            pinned: false
        })

        root.saveValue("symbols", JSON.stringify(syms))
        symbolsList = syms
        root.saveValue("_addTicker", "")
        root.saveValue("_addName", "")
        ToastService.showInfo("Markets", "Added " + name + " (" + ticker + ")")
    }

    function removeSymbolAt(idx) {
        var syms = JSON.parse(JSON.stringify(symbolsList))
        if (idx < 0 || idx >= syms.length) return
        var removed = syms[idx]
        syms.splice(idx, 1)
        root.saveValue("symbols", JSON.stringify(syms))
        symbolsList = syms
        ToastService.showInfo("Markets", "Removed " + (removed.name || removed.id))
    }
}
