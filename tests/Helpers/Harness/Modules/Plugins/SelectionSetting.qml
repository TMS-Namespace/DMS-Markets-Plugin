import QtQuick
// As DMS's SelectionSetting: loads its value once the settings have a plugin service, and SAVES on every value change
// (including before the service exists).
Column {
    id: root
    required property string settingKey
    required property string label
    property string description: ""
    required property var options
    property string defaultValue: ""
    property string value: defaultValue
    width: parent.width
    function findSettings(item) { while (item) { if (item.saveValue !== undefined && item.loadValue !== undefined) return item; item = item.parent } return null }
    function loadValue() { var settings = findSettings(root.parent); if (settings && settings.pluginService) value = settings.loadValue(settingKey, defaultValue) }
    Component.onCompleted: loadValue()
    onValueChanged: { var settings = findSettings(root.parent); if (settings) settings.saveValue(settingKey, value) }
}
