// HorizontalBarPill.qml - Horizontal bar-pill content for the Markets widget
//
// Displays a chart icon followed by the current bar label text.
// Intended to be returned from the PluginComponent.horizontalBarPill property.

import QtQuick
import qs.Common
import qs.Widgets
import "../Helpers"

Row {
    id: pill
    Constants { id: constants }

    // ── Required bindings (set by Widget.qml) ────────────────────────────────
    property int    iconSize:    constants.defaultBarIconSize
    property string displayText: constants.barDefaultLabel

    spacing: Theme.spacingS

    DankIcon {
        name: "show_chart"
        size: pill.iconSize
        color: Theme.primary
        anchors.verticalCenter: parent.verticalCenter
    }

    StyledText {
        text: pill.displayText
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceText
        anchors.verticalCenter: parent.verticalCenter
    }
}
