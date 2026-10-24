// Dux tooltip host contract; use a real Qt tooltip for deterministic multiline rendering checks.
import QtQuick
import QtQuick.Controls as Controls
import qs.Common

Item {
    id: root

    property MouseArea hoverArea: null
    readonly property bool hoverAreaHovered: hoverArea ? hoverArea.containsMouse : false
    property bool multiline: false
    property bool shown: false
    property string side: "bottom"
    property Item target: null
    property var text: null

    // Close stale errors when text, visibility, or the hover target disappears.
    function dismiss() {
        tooltip.close();
        shown = false;
    }

    // Refresh an already visible tooltip when a provider failure changes.
    function refresh() {
        if (shown)
            showNow();
    }
    // The host normally delays hover display; explicit activation keeps tests deterministic.
    function schedule() {
        showNow();
    }
    // Open against the source item, including while its clicks are blocked by a fetch.
    function showNow() {
        if (!enabled || !visible || !text || !target || !target.visible)
            return;
        tooltip.open();
        shown = true;
    }

    onEnabledChanged: if (!enabled)
        dismiss()
    onHoverAreaHoveredChanged: hoverAreaHovered ? schedule() : dismiss()
    onTargetChanged: target ? refresh() : dismiss()
    onTextChanged: text ? refresh() : dismiss()
    onVisibleChanged: if (!visible)
        dismiss()

    Controls.ToolTip {
        id: tooltip

        parent: root.target
        text: root.text || ""

        contentItem: StyledText {
            font.pixelSize: Theme.fontSizeSmall
            text: tooltip.text
            textFormat: root.multiline ? Text.PlainText : Text.AutoText
            wrapMode: root.multiline ? Text.WrapAnywhere : Text.NoWrap
        }
    }
}
