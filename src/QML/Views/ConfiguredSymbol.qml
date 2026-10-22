// ConfiguredSymbol.qml - Row for a configured symbol in the settings list
//
// Shows symbol name, metadata, pin indicator, and move/delete action buttons.
// All sizes come from Constants so the layout has no magic numbers.

import QtQuick
import "../../JS/Contracts/ChartSpan.js" as ChartSpan
import "../../JS/Contracts/Resolution.js" as Resolution
import "../Helpers"
import "../Services"
import qs.Common
import qs.DCommon.Widgets

Item {
    id: configRow

    property bool isEditing: false
    property bool isFirst: false
    property bool isLast: false
    property var symbolData: ({})

    signal clicked
    signal movedDown
    signal movedUp
    signal removed

    height: constants.configRowHeight
    width: parent ? parent.width : constants.configDefaultWidth

    Constants {
        id: constants
    }
    Rectangle {
        anchors.fill: parent
        border.color: configRow.isEditing ? Theme.primary : Theme.outlineMedium
        border.width: 1
        color: configRow.isEditing ? Theme.primaryContainer : (rowHover.containsMouse ? Theme.surfaceContainerHighest : Theme.nestedSurface)
        radius: Theme.cornerRadius

        MouseArea {
            id: rowHover

            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true

            onClicked: configRow.clicked()
        }
        Row {
            anchors.fill: parent
            anchors.margins: Theme.spacingS
            spacing: Theme.spacingS

            // ── Pin indicator ────────────────────────────────────────────
            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                color: configRow.symbolData.pinned ? Theme.primary : Theme.surfaceContainerHighest
                name: "push_pin"
                rotation: configRow.symbolData.pinned ? 0 : constants.unpinnedRotationDeg
                size: constants.configIconSize
            }

            // ── Symbol info (name + metadata) ────────────────────────────
            Column {
                anchors.verticalCenter: parent.verticalCenter
                // width = total - pin - (3 buttons × size + 2 gaps) - 3 spacings
                width: parent.width - constants.configIconSize - (constants.configActionSize * 3 + constants.configButtonSpacing * 2) - Theme.spacingS * 3

                // One line: name | ticker | provider alias | price resolution | chart resolution / range
                StyledText {
                    color: Theme.surfaceText
                    elide: Text.ElideRight
                    font.pixelSize: Theme.fontSizeSmall + constants.configTextFontSizeDelta
                    text: {
                        return (configRow.symbolData.name || configRow.symbolData.ticker || "") + "  |  " + (configRow.symbolData.ticker || "") + "  |  " + ProvidersManager.aliasOf(configRow.symbolData.provider || ProvidersManager.defaultId) + "  |  " + Resolution.shortLabel(configRow.symbolData.priceResolution) + "  |  " + Resolution.shortLabel(configRow.symbolData.chartResolution) + " / " + ChartSpan.shortLabel(configRow.symbolData.chartRange);
                    }
                    width: parent.width
                    wrapMode: Text.NoWrap
                }
            }

            // ── Action buttons (move up / move down / delete) ─────────────
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: constants.configButtonSpacing

                MouseArea {
                    cursorShape: !configRow.isFirst ? Qt.PointingHandCursor : Qt.ArrowCursor
                    enabled: !configRow.isFirst
                    height: constants.configActionSize
                    hoverEnabled: true
                    width: constants.configActionSize

                    onClicked: configRow.movedUp()

                    DIcon {
                        anchors.centerIn: parent
                        color: !configRow.isFirst ? (parent.containsMouse ? Theme.primary : Theme.surfaceVariantText) : Theme.surfaceContainerHighest
                        name: "arrow_upward"
                        size: constants.configArrowIconSize
                    }
                }
                MouseArea {
                    cursorShape: !configRow.isLast ? Qt.PointingHandCursor : Qt.ArrowCursor
                    enabled: !configRow.isLast
                    height: constants.configActionSize
                    hoverEnabled: true
                    width: constants.configActionSize

                    onClicked: configRow.movedDown()

                    DIcon {
                        anchors.centerIn: parent
                        color: !configRow.isLast ? (parent.containsMouse ? Theme.primary : Theme.surfaceVariantText) : Theme.surfaceContainerHighest
                        name: "arrow_downward"
                        size: constants.configArrowIconSize
                    }
                }
                MouseArea {
                    cursorShape: Qt.PointingHandCursor
                    height: constants.configActionSize
                    hoverEnabled: true
                    width: constants.configActionSize

                    onClicked: configRow.removed()

                    DIcon {
                        anchors.centerIn: parent
                        color: parent.containsMouse ? Theme.error : Theme.surfaceVariantText
                        name: "delete"
                        size: constants.configIconSize
                    }
                }
            }
        }
    }
}
