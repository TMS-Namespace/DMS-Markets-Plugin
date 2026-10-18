// IconButton.qml - a small round button with an icon: translucent background, optional hover tint,
// optional spinning icon (used while something is loading). One component for every such button.
//
//   iconName, iconSize, iconColor, iconRotation   the icon
//   buttonSize, buttonRadius                      the button
//   hoverTint                                     background tint while hovered ("transparent" = none)
//   spinning                                      the icon turns until this is false (then rests at 0°)
//   pressable                                     false: shown, but not clickable
//   hovered (read-only), clicked()
import QtQuick
import "../Helpers"
import qs.Common
import qs.Widgets

Rectangle {
    id: button

    property real buttonRadius: constants.actionButtonRadius
    property int buttonSize: constants.actionButtonSize
    property color hoverTint: "transparent"
    readonly property bool hovered: mouseArea.containsMouse
    property color iconColor: Theme.surfaceVariantText
    property string iconName: ""
    property real iconRotation: 0
    property int iconSize: constants.actionIconSize
    property bool pressable: true
    property bool spinning: false

    signal clicked

    color: hovered && hoverTint.a > 0 ? Qt.rgba(hoverTint.r, hoverTint.g, hoverTint.b, constants.buttonHoverAlpha) : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, constants.actionButtonBgOpacity)
    height: buttonSize
    radius: buttonRadius
    width: buttonSize

    onSpinningChanged: if (!spinning)
        spinner.rotation = 0

    Constants {
        id: constants
    }
    MouseArea {
        id: mouseArea

        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        enabled: button.pressable
        hoverEnabled: true

        onClicked: button.clicked()
    }

    // The spinner turns; the icon inside keeps its own fixed rotation (for example a tilted pin).
    Item {
        id: spinner

        anchors.centerIn: parent
        height: icon.height
        width: icon.width

        RotationAnimation on rotation {
            duration: constants.headerAnimDurationMs
            from: 0
            loops: Animation.Infinite
            running: button.spinning
            to: constants.fullRotationDeg
        }

        DankIcon {
            id: icon

            anchors.centerIn: parent
            color: button.iconColor
            name: button.iconName
            rotation: button.iconRotation
            size: button.iconSize
        }
    }
}
