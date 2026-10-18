// VerticalBarPill.qml - Vertical bar-pill content for the Markets widget
//
// Displays a chart icon above a short label (first pinned symbol or "MKT").
// Intended to be returned from the PluginComponent.verticalBarPill property.

import QtQuick
import "../Helpers"
import qs.Common
import qs.Widgets

Column {
    id: pill

    // ── Required bindings (set by Widget.qml) ────────────────────────────────
    property int iconSize: constants.defaultBarIconSize
    property string shortLabel: "MKT"

    spacing: Theme.spacingXS

    Constants {
        id: constants
    }
    DankIcon {
        anchors.horizontalCenter: parent.horizontalCenter
        color: Theme.primary
        name: "show_chart"
        size: pill.iconSize
    }
    StyledText {
        anchors.horizontalCenter: parent.horizontalCenter
        color: Theme.surfaceText
        font.pixelSize: Theme.fontSizeSmall
        horizontalAlignment: Text.AlignHCenter
        text: pill.shortLabel
    }
}
