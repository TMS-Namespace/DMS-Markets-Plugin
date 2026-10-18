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
import QtQuick.Controls as Controls
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
    property string tooltipText: ""
    property bool warning: false

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

        acceptedButtons: button.pressable ? Qt.LeftButton : Qt.NoButton
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true

        onClicked: if (button.pressable)
            button.clicked()
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

    // Keep the badge outside the rotating icon, so failures remain legible during retries.
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        color: Theme.error
        height: constants.refreshWarningBadgeSize
        radius: width / 2
        visible: button.warning
        width: height

        StyledText {
            anchors.centerIn: parent
            color: Theme.surfaceContainer
            font.pixelSize: constants.refreshWarningBadgeSize - 2
            font.weight: Font.Bold
            text: "!"
        }
    }

    // DMS's current tooltip clips to one line; fetch failures need wrapping and explicit line breaks.
    Controls.ToolTip {
        id: buttonTooltip

        padding: Theme.spacingS
        parent: button
        text: button.tooltipText
        visible: button.hovered && text !== ""

        background: Rectangle {
            border.color: Theme.outlineVariant
            border.width: 1
            color: Theme.surfaceContainerHigh
            radius: Theme.cornerRadius
        }
        contentItem: Text {
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeSmall
            text: buttonTooltip.text
            textFormat: Text.PlainText
            width: Math.min(implicitWidth, constants.errorTooltipMaxWidth)
            wrapMode: Text.Wrap
        }
    }
}
