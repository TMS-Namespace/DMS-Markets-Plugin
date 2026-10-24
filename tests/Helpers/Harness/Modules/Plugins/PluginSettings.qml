// As DMS's PluginSettings: children go into a default list<QtObject> and are re-parented into a column (a child sees a
// null parent while it is created); when the plugin service is set, and whenever the service reports changed plugin data,
// the child controls reload their values; saveValue / loadValue do nothing without a service.
import QtQuick

Item {
    id: root

    default property list<QtObject> content
    required property string pluginId
    property var pluginService: null

    signal settingChanged

    function loadValue(key, defaultValue) {
        if (pluginService && pluginService.loadPluginData)
            return pluginService.loadPluginData(pluginId, key, defaultValue);
        return defaultValue;
    }
    function reloadChildValues() {
        for (let i = 0; i < content.length; i++)
            if (content[i].loadValue)
                content[i].loadValue();
    }
    function saveValue(key, value) {
        if (!pluginService)
            return;
        if (pluginService.savePluginData) {
            pluginService.savePluginData(pluginId, key, value);
            settingChanged();
        }
    }

    height: implicitHeight
    implicitHeight: settingsColumn.implicitHeight

    onContentChanged: {
        for (let i = 0; i < content.length; i++)
            if (content[i] instanceof Item)
                content[i].parent = settingsColumn;
    }
    onPluginServiceChanged: {
        if (pluginService)
            reloadChildValues();
    }

    Connections {
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === root.pluginId)
                root.reloadChildValues();
        }

        enabled: root.pluginService !== null
        target: root.pluginService
    }
    Column {
        id: settingsColumn

        width: parent.width
    }
}
