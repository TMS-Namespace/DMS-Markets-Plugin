import QtQuick

// As DMS's SelectionSetting: loads its value once the settings have a plugin service, and SAVES on every value change
// (including before the service exists).
Column {
    id: root

    property string defaultValue: ""
    property string description: ""
    required property string label
    required property var options
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
        if (settings && settings.pluginService)
            value = settings.loadValue(settingKey, defaultValue);
    }

    width: parent.width

    Component.onCompleted: loadValue()
    onValueChanged: {
        var settings = findSettings(root.parent);
        if (settings)
            settings.saveValue(settingKey, value);
    }
}
