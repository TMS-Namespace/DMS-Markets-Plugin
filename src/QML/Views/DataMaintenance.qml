// DataMaintenance.qml - collapsible cleanup actions; clearing symbols always needs a second confirmation.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.DCommon.Widgets

DCollapsibleSection {
    id: root

    property bool cacheClearing: false
    property bool confirmRemoval: false
    property bool serviceReady: false
    property int symbolCount: 0

    signal clearCacheRequested
    signal removeAllRequested

    description: "Clear cached prices and charts, or remove all configured symbols. Display settings are kept."
    title: "CleanUp"

    onExpandedChanged: if (!expanded)
        confirmRemoval = false
    onSymbolCountChanged: confirmRemoval = false

    Column {
        Layout.fillWidth: true
        spacing: Theme.spacingS

        StyledText {
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
            text: "Clear all " + root.symbolCount + " configured symbols?"
            visible: root.confirmRemoval
            width: parent.width
            wrapMode: Text.WordWrap
        }
        Flow {
            spacing: Theme.spacingS
            width: parent.width

            DButton {
                enabled: root.serviceReady && !root.cacheClearing
                text: root.cacheClearing ? "Clearing Cache…" : "Clear Cache"

                onClicked: root.clearCacheRequested()
            }
            DButton {
                enabled: root.serviceReady && root.symbolCount > 0 && !root.cacheClearing
                text: root.confirmRemoval ? "Confirm Clear Symbols" : "Clear Symbols"

                onClicked: {
                    if (!root.confirmRemoval) {
                        root.confirmRemoval = true;
                        return;
                    }
                    root.confirmRemoval = false;
                    root.removeAllRequested();
                }
            }
            DButton {
                text: "Cancel"
                visible: root.confirmRemoval

                onClicked: root.confirmRemoval = false
            }
        }
    }
}
