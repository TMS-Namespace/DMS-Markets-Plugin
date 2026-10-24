// DisplaySettings.qml - Chart colors, popup height, and shared symbol visibility controls.
// Host setting controls reach the owning settings page through their visual parent chain.
pragma ComponentBehavior: Bound
import QtQuick
import "../Helpers"
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

Column {
    id: root

    readonly property int popoutRowsValue: popoutRowsSetting.value

    spacing: Theme.spacingS

    Constants {
        id: constants
    }
    StyledText {
        color: Theme.surfaceText
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        text: "Chart Colors"
        topPadding: Theme.spacingM
        width: parent.width
    }
    ColorSettingRow {
        defaultColor: constants.defaultUpColor.toString()
        description: "Hex color for positive changes (e.g., " + constants.defaultUpColor + ")"
        label: "Up / Positive Color"
        settingKey: "upColor"
    }
    ColorSettingRow {
        defaultColor: constants.defaultDownColor.toString()
        description: "Hex color for negative changes (e.g., " + constants.defaultDownColor + ")"
        label: "Down / Negative Color"
        settingKey: "downColor"
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  POPUP LAYOUT
    // ═══════════════════════════════════════════════════════════════════════

    StyledText {
        color: Theme.surfaceText
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        text: "Popup Height"
        topPadding: Theme.spacingM
        width: parent.width
    }
    ValueSliderRow {
        id: popoutRowsSetting

        defaultValue: constants.defaultPopoutRows
        label: "Visible Symbol Rows without scrolling"
        maximum: constants.maxPopoutRows
        minimum: constants.minPopoutRows
        settingKey: "popoutRows"
    }
    StyledText {
        color: Theme.surfaceText
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        text: "Global symbol settings"
        topPadding: Theme.spacingM
        width: parent.width
    }
    StyledText {
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall
        text: "Choose which details to show for all of the configured symbols"
        width: parent.width
        wrapMode: Text.WordWrap
    }
    ToggleSetting {
        defaultValue: true
        description: "Show the ticker ID and price resolution below the symbol name"
        label: "Show Symbol Ticker"
        settingKey: "showTicker"
    }
    ToggleSetting {
        defaultValue: true
        description: "Show the price change amount and percentage"
        label: "Show Price Change"
        settingKey: "showPriceChange"
    }
    ToggleSetting {
        defaultValue: true
        description: "Show the time range on the chart"
        label: "Show Chart Range"
        settingKey: "showChartRange"
    }
    ToggleSetting {
        defaultValue: true
        description: "Show the data provider's three-letter alias on the chart"
        label: "Show Provider Alias"
        settingKey: "showProviderName"
    }
    ToggleSetting {
        defaultValue: true
        description: "Show how long ago the symbol data was last refreshed"
        label: "Show Refreshed Since"
        settingKey: "showRefreshedSince"
    }
}
