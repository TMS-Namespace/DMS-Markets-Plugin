// Dux scrollbar contract; Qt's attached ScrollBar must supply size, position, and dragging behavior.
import QtQuick
import QtQuick.Controls as Controls

Controls.ScrollBar {
    property bool allowed: true
    property Flickable targetFlickable: null

    height: targetFlickable ? targetFlickable.height : 0
    visible: allowed && size < 1
}
