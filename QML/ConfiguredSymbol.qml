// ConfiguredSymbol.qml — Row for a configured symbol in settings
//
// Shows symbol name, metadata, pin indicator, and up/down/delete buttons.

import QtQuick
import qs.Common
import qs.Widgets

Item {
    id: configRow

    property var  symbolData: ({})
    property bool isEditing:  false
    property bool isFirst:    false
    property bool isLast:     false

    signal clicked()
    signal removed()
    signal movedUp()
    signal movedDown()

    width: parent ? parent.width : 200
    height: 56

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: configRow.isEditing
            ? Theme.primaryContainer
            : (symRowMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)

        MouseArea {
            id: symRowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: configRow.clicked()
        }

        Row {
            anchors.fill: parent
            anchors.margins: Theme.spacingS
            spacing: Theme.spacingS

            DankIcon {
                name: "push_pin"
                size: 18
                color: symbolData.pinned ? Theme.primary : Theme.surfaceContainerHighest
                anchors.verticalCenter: parent.verticalCenter
                rotation: symbolData.pinned ? 0 : 45
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 18 - 80 - Theme.spacingS * 3

                StyledText {
                    text: symbolData.name || symbolData.id || ""
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    elide: Text.ElideRight
                    width: parent.width
                }

                StyledText {
                    text: {
                        var parts = (symbolData.id || "") + "  |  "
                            + (symbolData.provider || "") + "  |  price "
                            + (symbolData.priceInterval || "1M") + "  |  chart "
                            + (symbolData.graphInterval || "1M")
                        if (symbolData.invert)
                            parts += "  |  1/x"
                        if (symbolData.showChangeWhenPinned)
                            parts += "  |  Δ on bar"
                        return parts
                    }
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    elide: Text.ElideRight
                    width: parent.width
                }
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                // Move up button
                MouseArea {
                    width: 24; height: 24
                    cursorShape: !configRow.isFirst ? Qt.PointingHandCursor : Qt.ArrowCursor
                    hoverEnabled: true
                    enabled: !configRow.isFirst
                    onClicked: configRow.movedUp()

                    DankIcon {
                        anchors.centerIn: parent
                        name: "arrow_upward"
                        size: 16
                        color: !configRow.isFirst
                            ? (parent.containsMouse ? Theme.primary : Theme.surfaceVariantText)
                            : Theme.surfaceContainerHighest
                    }
                }

                // Move down button
                MouseArea {
                    width: 24; height: 24
                    cursorShape: !configRow.isLast ? Qt.PointingHandCursor : Qt.ArrowCursor
                    hoverEnabled: true
                    enabled: !configRow.isLast
                    onClicked: configRow.movedDown()

                    DankIcon {
                        anchors.centerIn: parent
                        name: "arrow_downward"
                        size: 16
                        color: !configRow.isLast
                            ? (parent.containsMouse ? Theme.primary : Theme.surfaceVariantText)
                            : Theme.surfaceContainerHighest
                    }
                }

                // Delete button
                MouseArea {
                    width: 24; height: 24
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: configRow.removed()

                    DankIcon {
                        anchors.centerIn: parent
                        name: "delete"
                        size: 18
                        color: parent.containsMouse ? Theme.error : Theme.surfaceVariantText
                    }
                }
            }
        }
    }
}
