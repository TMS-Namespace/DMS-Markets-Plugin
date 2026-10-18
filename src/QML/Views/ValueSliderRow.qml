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

    // The page's plugin service can arrive after this row exists (DMS attaches it after creating the page), and the page's
    // own storage follows it a moment later: load again then, or the default would stay shown.
    property var _page: null
    property int defaultValue: 0
    property string description: ""
    property string label: ""
    property int maximum: 100
    property int minimum: 0
    property string settingKey: ""
    property int value: defaultValue

    // Room for the widest value, sized from the font so it follows the theme.
    readonly property real valueWidth: Math.round(Theme.fontSizeMedium * 2.5)

    // Find the nearest host settings page that owns this control.
    // The page this row sits in (the nearest parent that can save and load values), or null.
    function _settings() {
        let item = root.parent;
        while (item) {
            if ("saveValue" in item && "loadValue" in item)
                return item;
            item = item.parent;
        }
        return null;
    }

    // Read the saved value after the settings service becomes available.
    function loadValue() {
        let settings = _settings();
        if (settings && settings.pluginService)
            value = settings.loadValue(settingKey, defaultValue);
    }

    spacing: Theme.spacingS
    width: parent ? parent.width : implicitWidth

    Component.onCompleted: {
        _page = _settings();
        loadValue();
    }
    onParentChanged: _page = _settings()
    onValueChanged: {
        let settings = _settings();
        if (settings)
            settings.saveValue(settingKey, value);
    }

    Connections {
        // Reload saved control values after the host attaches its service.
        function onPluginServiceChanged() {
            Qt.callLater(root.loadValue);
        }

        ignoreUnknownSignals: true
        target: root._page
    }
    StyledText {
        color: Theme.surfaceText
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
        text: root.label
    }
    StyledText {
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall
        text: root.description
        visible: root.description !== ""
        width: parent.width
        wrapMode: Text.WordWrap
    }
    Row {
        id: sliderRow

        spacing: Theme.spacingS
        width: parent.width

        DankSlider {
            id: slider

            anchors.verticalCenter: parent.verticalCenter
            maximum: root.maximum
            minimum: root.minimum
            thumbOutlineColor: Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency)
            unit: ""
            value: root.value
            wheelEnabled: false
            width: sliderRow.width - root.valueWidth - sliderRow.spacing

            onSliderValueChanged: newValue => root.value = newValue
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignRight
            text: root.value
            width: root.valueWidth
        }
    }
}
