// Dux collapsible-section contract: content stays instantiated and becomes hidden and disabled when collapsed.
import QtQuick
import QtQuick.Layouts

Column {
    id: root

    default property alias content: body.data
    property string description: ""
    property bool expanded: false
    required property string title

    signal toggleRequested

    // Mirror the host's public toggle action, including its disabled-state guard.
    function toggle() {
        if (!enabled)
            return;
        toggleRequested();
        expanded = !expanded;
    }

    Item {
        height: 48
        width: parent.width
    }
    ColumnLayout {
        id: body

        enabled: root.expanded
        visible: root.expanded
        width: parent.width
    }
}
