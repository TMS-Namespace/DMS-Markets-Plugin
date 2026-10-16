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
import qs.Common
import qs.Widgets
import "../Helpers"

Rectangle {
    id: button

    property string iconName: ""
    property int    iconSize: constants.actionIconSize
    property color  iconColor: Theme.surfaceVariantText
    property real   iconRotation: 0
    property int    buttonSize: constants.actionButtonSize
    property real   buttonRadius: constants.actionButtonRadius
    property color  hoverTint: "transparent"
    property bool   spinning: false
    property bool   pressable: true
    readonly property bool hovered: mouseArea.containsMouse

    signal clicked()

    Constants { id: constants }

    width: buttonSize
    height: buttonSize
    radius: buttonRadius
    color: hovered && hoverTint.a > 0
           ? Qt.rgba(hoverTint.r, hoverTint.g, hoverTint.b, constants.buttonHoverAlpha)
           : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, constants.actionButtonBgOpacity)

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: button.pressable
        onClicked: button.clicked()
    }

    // The spinner turns; the icon inside keeps its own fixed rotation (for example a tilted pin).
    Item {
        id: spinner
        anchors.centerIn: parent
        width: icon.width
        height: icon.height

        RotationAnimation on rotation {
            running: button.spinning
            from: 0; to: constants.fullRotationDeg
            duration: constants.headerAnimDurationMs
            loops: Animation.Infinite
        }

        DankIcon {
            id: icon
            anchors.centerIn: parent
            name: button.iconName
            size: button.iconSize
            color: button.iconColor
            rotation: button.iconRotation
        }
    }

    onSpinningChanged: if (!spinning) spinner.rotation = 0
}
