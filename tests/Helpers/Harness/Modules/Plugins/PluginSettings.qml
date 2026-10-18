// As DMS's PluginSettings: children go into a default list<QtObject> and are re-parented into a column (a child sees a
// null parent while it is created); when the plugin service is set, and whenever the service reports changed plugin data,
// the child controls reload their values; saveValue / loadValue do nothing without a service.
import QtQuick
Item {
    id: root
    required property string pluginId
    property var pluginService: null
    default property list<QtObject> content
    signal settingChanged
    implicitHeight: settingsColumn.implicitHeight
    height: implicitHeight
    onContentChanged: {
        for (let i = 0; i < content.length; i++)
            if (content[i] instanceof Item) content[i].parent = settingsColumn
    }
    onPluginServiceChanged: { if (pluginService) reloadChildValues() }
    Connections {
        target: root.pluginService
        enabled: root.pluginService !== null
        function onPluginDataChanged(changedPluginId) { if (changedPluginId === root.pluginId) root.reloadChildValues() }
    }
    function reloadChildValues() { for (let i = 0; i < content.length; i++) if (content[i].loadValue) content[i].loadValue() }
    function saveValue(key, value) { if (!pluginService) return; if (pluginService.savePluginData) { pluginService.savePluginData(pluginId, key, value); settingChanged() } }
    function loadValue(key, defaultValue) { if (pluginService && pluginService.loadPluginData) return pluginService.loadPluginData(pluginId, key, defaultValue); return defaultValue }
    Column { id: settingsColumn; width: parent.width }
}
