import QtQuick
// As DMS's DankSlider for what the plugin uses: an integer value between minimum and maximum, reported through sliderValueChanged.
Item {
    property int value: 50
    property int minimum: 0
    property int maximum: 100
    property string unit: "%"
    property string leftIcon: ""
    property string rightIcon: ""
    property bool wheelEnabled: true
    property color thumbOutlineColor: "transparent"
    signal sliderValueChanged(int newValue)
    implicitHeight: 32
}
