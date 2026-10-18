// HorizontalBarPill.qml - Horizontal bar-pill content for the Markets widget
//
// Displays a chart icon followed by the current bar label text.
// Intended to be returned from the PluginComponent.horizontalBarPill property.

import QtQuick
import "../Helpers"
import qs.Common
import qs.Widgets

Row {
    id: pill

    property string displayText: constants.barDefaultLabel

    // ── Required bindings (set by Widget.qml) ────────────────────────────────
    property int iconSize: constants.defaultBarIconSize

    spacing: Theme.spacingS

    Constants {
        id: constants
    }
    DankIcon {
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.primary
        name: "show_chart"
        size: pill.iconSize
    }
    StyledText {
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.surfaceText
        font.pixelSize: Theme.fontSizeSmall
        text: pill.displayText
    }
}
