// ConfiguredSymbol.qml — Row for a configured symbol in the settings list
//
// Shows symbol name, metadata, pin indicator, and move/delete action buttons.
// All sizes come from Constants so the layout has no magic numbers.

import QtQuick
import qs.Common
import qs.Widgets
import "../../JS/Helpers/Helpers.js" as Helpers
import "../Services"
import "../Helpers"
import "../../JS/Contracts/Resolution.js" as Resolution
import "../../JS/Contracts/ChartSpan.js" as ChartSpan

Item {
    id: configRow

    Constants { id: constants }

    property var  symbolData: ({})
    property bool isEditing:  false
    property bool isFirst:    false
    property bool isLast:     false

    signal clicked()
    signal removed()
    signal movedUp()
    signal movedDown()

    width:  parent ? parent.width : constants.configDefaultWidth
    height: constants.configRowHeight

    Rectangle {
        anchors.fill: parent
        radius:       Theme.cornerRadius
        color: configRow.isEditing
               ? Theme.primaryContainer
               : (rowHover.containsMouse ? Theme.surfaceContainerHighest : Theme.nestedSurface)
        border.color: configRow.isEditing ? Theme.primary : Theme.outlineMedium
        border.width: 1

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
                size:     constants.configIconSize
                color:    symbolData.pinned ? Theme.primary : Theme.surfaceContainerHighest
                rotation: symbolData.pinned ? 0 : constants.unpinnedRotationDeg
                anchors.verticalCenter: parent.verticalCenter
            }

            // ── Symbol info (name + metadata) ────────────────────────────
            Column {
                anchors.verticalCenter: parent.verticalCenter
                // width = total - pin - (3 buttons × size + 2 gaps) - 3 spacings
                width: parent.width
                       - constants.configIconSize
                       - (constants.configActionSize * 3 + constants.configButtonSpacing * 2)
                       - Theme.spacingS * 3

                StyledText {
                    text:           symbolData.name || symbolData.ticker || ""
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight:    Font.Medium
                    color:          Theme.surfaceText
                    elide:          Text.ElideRight
                    width:          parent.width
                }

                StyledText {
                    text: {
                        var parts = (symbolData.ticker || "") + "  |  "
                                    + ProvidersManager.nameOf(symbolData.provider || ProvidersManager.defaultId) + "  |  price "
                                    + Resolution.label(symbolData.priceResolution) + "  |  change "
                                    + Resolution.label(symbolData.changeResolution) + "  |  chart "
                                    + Resolution.label(symbolData.chartResolution) + " over "
                                    + ChartSpan.label(symbolData.chartRange)
                        if (Helpers.boolValue(symbolData.invert, false))              parts += "  |  1/x"
                        if (Helpers.boolValue(symbolData.showChangeWhenPinned, false)) parts += "  |  Δ on bar"
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
                spacing: constants.configButtonSpacing

                MouseArea {
                    width: constants.configActionSize; height: constants.configActionSize
                    cursorShape:  !configRow.isFirst ? Qt.PointingHandCursor : Qt.ArrowCursor
                    hoverEnabled: true
                    enabled:      !configRow.isFirst
                    onClicked:    configRow.movedUp()

                    DankIcon {
                        anchors.centerIn: parent
                        name:  "arrow_upward"
                        size:  constants.configArrowIconSize
                        color: !configRow.isFirst
                               ? (parent.containsMouse ? Theme.primary : Theme.surfaceVariantText)
                               : Theme.surfaceContainerHighest
                    }
                }

                MouseArea {
                    width: constants.configActionSize; height: constants.configActionSize
                    cursorShape:  !configRow.isLast ? Qt.PointingHandCursor : Qt.ArrowCursor
                    hoverEnabled: true
                    enabled:      !configRow.isLast
                    onClicked:    configRow.movedDown()

                    DankIcon {
                        anchors.centerIn: parent
                        name:  "arrow_downward"
                        size:  constants.configArrowIconSize
                        color: !configRow.isLast
                               ? (parent.containsMouse ? Theme.primary : Theme.surfaceVariantText)
                               : Theme.surfaceContainerHighest
                    }
                }

                MouseArea {
                    width: constants.configActionSize; height: constants.configActionSize
                    cursorShape:  Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked:    configRow.removed()

                    DankIcon {
                        anchors.centerIn: parent
                        name:  "delete"
                        size:  constants.configIconSize
                        color: parent.containsMouse ? Theme.error : Theme.surfaceVariantText
                    }
                }
            }
        }
    }
}
