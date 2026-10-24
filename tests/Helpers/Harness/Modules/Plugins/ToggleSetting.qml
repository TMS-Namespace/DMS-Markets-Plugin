import QtQuick

// As DMS's ToggleSetting: loads (later) once the settings have a plugin service; saves value changes after that.
Row {
    id: root

    property bool defaultValue: false
    property string description: ""
    property bool isInitialized: false
    required property string label
    required property string settingKey
    property bool value: defaultValue

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
    onValueChanged: {
        if (!isInitialized)
            return;
        var settings = findSettings(root.parent);
        if (settings)
            settings.saveValue(settingKey, value);
    }
}
