// ConfiguredSymbol.qml — Row for a configured symbol in the settings list
//
// Shows symbol name, metadata, pin indicator, and move/delete action buttons.
// All sizes come from Constants so the layout has no magic numbers.

import QtQuick
import qs.Common
import qs.Widgets
import "../Helpers"

Item {
    id: configRow

    Constants { id: c }

    property var  symbolData: ({})
    property bool isEditing:  false
    property bool isFirst:    false
    property bool isLast:     false

    signal clicked()
    signal removed()
    signal movedUp()
    signal movedDown()

    width:  parent ? parent.width : 200
    height: c.configRowHeight

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: configRow.isEditing
               ? Theme.primaryContainer
               : (rowHover.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)

        MouseArea {
            id: rowHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape:  Qt.PointingHandCursor
            onClicked:    configRow.clicked()
        }

        Row {
            anchors.fill:    parent
            anchors.margins: Theme.spacingS
            spacing:         Theme.spacingS

            // ── Pin indicator ────────────────────────────────────────────
            DankIcon {
                name:     "push_pin"
                size:     c.configIconSize
                color:    symbolData.pinned ? Theme.primary : Theme.surfaceContainerHighest
                rotation: symbolData.pinned ? 0 : 45
                anchors.verticalCenter: parent.verticalCenter
            }

            // ── Symbol info (name + metadata) ────────────────────────────
            Column {
                anchors.verticalCenter: parent.verticalCenter
                // width = total - pin - (3 buttons × size + 2 gaps) - 3 spacings
                width: parent.width
                       - c.configIconSize
                       - (c.configActionSize * 3 + c.configButtonSpacing * 2)
                       - Theme.spacingS * 3

                StyledText {
                    text:           symbolData.name || symbolData.id || ""
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight:    Font.Medium
                    color:          Theme.surfaceText
                    elide:          Text.ElideRight
                    width:          parent.width
                }

                StyledText {
                    text: {
                        var parts = (symbolData.id || "") + "  |  "
                                    + (symbolData.provider || "") + "  |  price "
                                    + (symbolData.priceInterval || "1M") + "  |  chart "
                                    + (symbolData.graphInterval || "1M")
                        if (symbolData.invert)              parts += "  |  1/x"
                        if (symbolData.showChangeWhenPinned) parts += "  |  Δ on bar"
                        return parts
                    }
                    font.pixelSize: Theme.fontSizeSmall
                    color:          Theme.surfaceVariantText
                    elide:          Text.ElideRight
                    width:          parent.width
                }
            }

            // ── Action buttons (move up / move down / delete) ─────────────
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: c.configButtonSpacing

                MouseArea {
                    width: c.configActionSize; height: c.configActionSize
                    cursorShape:  !configRow.isFirst ? Qt.PointingHandCursor : Qt.ArrowCursor
                    hoverEnabled: true
                    enabled:      !configRow.isFirst
                    onClicked:    configRow.movedUp()

                    DankIcon {
                        anchors.centerIn: parent
                        name:  "arrow_upward"
                        size:  c.configArrowIconSize
                        color: !configRow.isFirst
                               ? (parent.containsMouse ? Theme.primary : Theme.surfaceVariantText)
                               : Theme.surfaceContainerHighest
                    }
                }

                MouseArea {
                    width: c.configActionSize; height: c.configActionSize
                    cursorShape:  !configRow.isLast ? Qt.PointingHandCursor : Qt.ArrowCursor
                    hoverEnabled: true
                    enabled:      !configRow.isLast
                    onClicked:    configRow.movedDown()

                    DankIcon {
                        anchors.centerIn: parent
                        name:  "arrow_downward"
                        size:  c.configArrowIconSize
                        color: !configRow.isLast
                               ? (parent.containsMouse ? Theme.primary : Theme.surfaceVariantText)
                               : Theme.surfaceContainerHighest
                    }
                }

                MouseArea {
                    width: c.configActionSize; height: c.configActionSize
                    cursorShape:  Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked:    configRow.removed()

                    DankIcon {
                        anchors.centerIn: parent
                        name:  "delete"
                        size:  c.configIconSize
                        color: parent.containsMouse ? Theme.error : Theme.surfaceVariantText
                    }
                }
            }
        }
    }
}
