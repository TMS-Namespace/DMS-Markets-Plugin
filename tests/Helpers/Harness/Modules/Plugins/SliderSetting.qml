import QtQuick
// As DMS's SliderSetting: integer value, loaded once the settings have a plugin service.
Column {
    id: root
    required property string settingKey
    required property string label
    property string description: ""
    property int defaultValue: 0
    property int value: defaultValue
    property int minimum: 0
    property int maximum: 100
    property string leftIcon: ""
    property string rightIcon: ""
    property string unit: ""
    property bool isInitialized: false
    width: parent.width
    function findSettings(item) { while (item) { if (item.saveValue !== undefined && item.loadValue !== undefined) return item; item = item.parent } return null }
    function loadValue() { var settings = findSettings(root.parent); if (settings && settings.pluginService) { value = settings.loadValue(settingKey, defaultValue); isInitialized = true } }
    Component.onCompleted: Qt.callLater(loadValue)
}
