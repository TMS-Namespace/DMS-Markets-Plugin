import QtQuick
// As DMS's StringSetting (without the text field): loads its value once the settings have a plugin service.
Column {
    id: root
    required property string settingKey
    required property string label
    property string description: ""
    property string placeholder: ""
    property string defaultValue: ""
    property string value: defaultValue
    property bool isInitialized: false
    width: parent.width
    function findSettings(item) { while (item) { if (item.saveValue !== undefined && item.loadValue !== undefined) return item; item = item.parent } return null }
    function loadValue() { var settings = findSettings(root.parent); if (settings && settings.pluginService) { value = settings.loadValue(settingKey, defaultValue); isInitialized = true } }
    Component.onCompleted: Qt.callLater(loadValue)
}
