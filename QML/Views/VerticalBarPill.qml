// VerticalBarPill.qml — Vertical bar-pill content for the Markets widget
//
// Displays a chart icon above a short label (first pinned symbol or "MKT").
// Intended to be returned from the PluginComponent.verticalBarPill property.

import QtQuick
import qs.Common
import qs.Widgets
import "../Helpers"

Column {
    Constants { id: c }

    // ── Required bindings (set by Widget.qml) ────────────────────────────────
    property int    iconSize:   c.defaultBarIconSize
    property string shortLabel: "MKT"

    spacing: Theme.spacingXS

    DankIcon {
        name: "show_chart"
        size: iconSize
        color: Theme.primary
        anchors.horizontalCenter: parent.horizontalCenter
    }

    StyledText {
        text: shortLabel
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceText
        anchors.horizontalCenter: parent.horizontalCenter
        horizontalAlignment: Text.AlignHCenter
    }
}
