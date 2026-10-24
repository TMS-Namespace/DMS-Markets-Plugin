import QtQuick

// As DMS's DDropdown for what the plugin uses. Like the real one it ASSIGNS currentValue itself when an option is chosen
// (which destroys a plain binding on it): choose() does exactly that.
Item {
    property string currentValue: ""
    property string description: ""
    property var options: []
    property string text: ""

    signal valueChanged(string newValue)

    function choose(optionLabel) {
        currentValue = optionLabel;
        valueChanged(optionLabel);
    }

    implicitHeight: 40
}
