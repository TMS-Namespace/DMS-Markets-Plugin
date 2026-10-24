// Dux's popup header and vertical layout; implicit heights must match the real Column contract.
import QtQuick
import qs.Common
import qs.DCommon.Widgets

Column {
    id: root

    property var closePopout: null
    readonly property int detailsHeight: details.visible ? details.implicitHeight : 0
    property string detailsText: ""
    readonly property int headerHeight: header.visible ? header.height : 0
    property string headerText: ""
    property var parentPopout: null
    property bool showCloseButton: false

    spacing: 0

    Item {
        id: header

        height: 40
        visible: root.headerText.length > 0
        width: parent.width
    }
    StyledText {
        id: details

        bottomPadding: Theme.spacingS
        font.pixelSize: Theme.fontSizeMedium
        leftPadding: Theme.spacingS
        text: root.detailsText
        visible: text.length > 0
        width: parent.width
        wrapMode: Text.WordWrap
    }
}
