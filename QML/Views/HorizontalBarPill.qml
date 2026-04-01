// HorizontalBarPill.qml — Horizontal bar-pill content for the Markets widget
//
// Displays a chart icon followed by the current bar label text.
// Intended to be returned from the PluginComponent.horizontalBarPill property.

import QtQuick
import qs.Common
import qs.Widgets

Row {
    // ── Required bindings (set by Widget.qml) ────────────────────────────────
    property int    iconSize:    16
    property string displayText: "Markets"

    spacing: Theme.spacingS

    DankIcon {
        name: "show_chart"
        size: iconSize
        color: Theme.primary
        anchors.verticalCenter: parent.verticalCenter
    }

    StyledText {
        text: displayText
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceText
        anchors.verticalCenter: parent.verticalCenter
    }
}
