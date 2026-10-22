import QtQuick

// As DMS's DSlider for what the plugin uses: an integer value between minimum and maximum, reported through sliderValueChanged.
Item {
    property string leftIcon: ""
    property int maximum: 100
    property int minimum: 0
    property string rightIcon: ""
    property color thumbOutlineColor: "transparent"
    property string unit: "%"
    property int value: 50
    property bool wheelEnabled: true

    signal sliderValueChanged(int newValue)

    implicitHeight: 32
}
