import QtQuick

// As DMS's SliderSetting: integer value, loaded once the settings have a plugin service.
Column {
    id: root

    property int defaultValue: 0
    property string description: ""
    property bool isInitialized: false
    required property string label
    property string leftIcon: ""
    property int maximum: 100
    property int minimum: 0
    property string rightIcon: ""
    required property string settingKey
    property string unit: ""
    property int value: defaultValue

    function findSettings(item) {
        while (item) {
            if (item.saveValue !== undefined && item.loadValue !== undefined)
                return item;
            item = item.parent;
        }
        return null;
    }
    function loadValue() {
        var settings = findSettings(root.parent);
        if (settings && settings.pluginService) {
            value = settings.loadValue(settingKey, defaultValue);
            isInitialized = true;
        }
    }

    width: parent.width

    Component.onCompleted: Qt.callLater(loadValue)
}
