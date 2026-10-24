// Dux button contract used by the maintenance view; activation is driven explicitly in UI tests.
import QtQuick

Item {
    property string text: ""
    property color textColor: "black"

    signal clicked

    implicitHeight: 32
    implicitWidth: 220
}
