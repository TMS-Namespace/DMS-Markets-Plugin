// ValueSliderRow.qml - a plugin slider setting (like DMS's SliderSetting) with its current value to the right of the bar,
// vertically centred on it.
//
//   settingKey, label, description, minimum, maximum, defaultValue   as for DMS's SliderSetting
//   value                                                             the current value
//
// Like DMS's own setting controls it loads its saved value when the settings page asks (loadValue, also when the plugin
// service attaches or the data changes) and saves every change, through the page it sits in (the nearest parent that has
// saveValue and loadValue).
import QtQuick
import qs.Common
import qs.Widgets

Column {
    id: root

    property string settingKey: ""
    property string label: ""
    property string description: ""
    property int minimum: 0
    property int maximum: 100
    property int defaultValue: 0
    property int value: defaultValue

    width: parent ? parent.width : implicitWidth
    spacing: Theme.spacingS

    // Room for the widest value, sized from the font so it follows the theme.
    readonly property real valueWidth: Math.round(Theme.fontSizeMedium * 2.5)

    // Find the nearest host settings page that owns this control.
    // The page this row sits in (the nearest parent that can save and load values), or null.
    function _settings() {
        var item = root.parent
        while (item) {
            if (item.saveValue !== undefined && item.loadValue !== undefined) return item
            item = item.parent
        }
        return null
    }

    // Read the saved value after the settings service becomes available.
    function loadValue() {
        var settings = _settings()
        if (settings && settings.pluginService) value = settings.loadValue(settingKey, defaultValue)
    }

    // The page's plugin service can arrive after this row exists (DMS attaches it after creating the page), and the page's
    // own storage follows it a moment later: load again then, or the default would stay shown.
    property var _page: null
    Component.onCompleted: { _page = _settings(); loadValue() }
    onParentChanged: _page = _settings()
    Connections {
        target: root._page
        ignoreUnknownSignals: true
        // Reload saved control values after the host attaches its service.
        function onPluginServiceChanged() { Qt.callLater(root.loadValue) }
    }

    onValueChanged: {
        var settings = _settings()
        if (settings) settings.saveValue(settingKey, value)
    }

    StyledText {
        text: root.label
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        visible: root.description !== ""
        text: root.description
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        width: parent.width
        wrapMode: Text.WordWrap
    }

    Row {
        id: sliderRow
        width: parent.width
        spacing: Theme.spacingS

        DankSlider {
            id: slider
            anchors.verticalCenter: parent.verticalCenter
            width: sliderRow.width - root.valueWidth - sliderRow.spacing
            value: root.value
            minimum: root.minimum
            maximum: root.maximum
            unit: ""
            wheelEnabled: false
            thumbOutlineColor: Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency)
            onSliderValueChanged: newValue => root.value = newValue
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            width: root.valueWidth
            text: root.value
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
            horizontalAlignment: Text.AlignRight
        }
    }
}
