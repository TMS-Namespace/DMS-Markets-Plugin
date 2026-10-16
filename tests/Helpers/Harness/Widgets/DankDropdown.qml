import QtQuick
// As DMS's DankDropdown for what the plugin uses. Like the real one it ASSIGNS currentValue itself when an option is chosen
// (which destroys a plain binding on it): choose() does exactly that.
Item {
    property string text: ""
    property string description: ""
    property string currentValue: ""
    property var options: []
    signal valueChanged(string newValue)
    function choose(optionLabel) { currentValue = optionLabel; valueChanged(optionLabel) }
    implicitHeight: 40
}
