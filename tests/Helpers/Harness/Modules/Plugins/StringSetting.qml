import QtQuick

// As DMS's StringSetting (without the text field): loads its value once the settings have a plugin service.
Column {
    id: root

    property string defaultValue: ""
    property string description: ""
    property bool isInitialized: false
    required property string label
    property string placeholder: ""
    required property string settingKey
    property string value: defaultValue

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
