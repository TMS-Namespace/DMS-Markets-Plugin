// Stand-in for DMS's PluginComponent: the properties and functions the widget uses.
import QtQuick
Item {
    property string pluginId: ""
    property var pluginService: null
    property var pluginData: ({})
    property string layerNamespacePlugin: ""
    property Component horizontalBarPill: null
    property Component verticalBarPill: null
    property Component popoutContent: null
    property real popoutWidth: 0
    property real popoutHeight: 0
    property int iconSize: 20
    property bool visibilityOverride: true
    function setVisibilityOverride(visible) { visibilityOverride = visible }
    function closePopout() { }
}
