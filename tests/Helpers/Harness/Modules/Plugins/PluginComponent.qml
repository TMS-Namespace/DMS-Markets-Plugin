// Stand-in for DMS's PluginComponent: the properties and functions the widget uses.
import QtQuick

Item {
    property int closedPopouts: 0
    property Component horizontalBarPill: null
    property int iconSize: 20
    property string layerNamespacePlugin: ""
    property var pluginData: ({})
    property string pluginId: ""
    property var pluginService: null
    property Component popoutContent: null
    property real popoutHeight: 0
    property real popoutWidth: 0
    property bool surfaceLive: true
    property int textSize: 12
    property Component verticalBarPill: null
    property bool visibilityOverride: true

    function closePopout() {
        closedPopouts++;
    }
    function setVisibilityOverride(visible) {
        visibilityOverride = visible;
    }
}
