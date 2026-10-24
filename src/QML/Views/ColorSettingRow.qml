// ColorSettingRow.qml - a hex-colour text setting with a swatch showing the colour (or the default while empty).
//
//   settingKey, label, description, defaultColor   as for DMS's StringSetting
//   value (read-only)                              the text typed
import QtQuick
import qs.Common
import qs.Modules.Plugins

Row {
    id: row

    property string defaultColor: ""
    property string description: ""
    property string label: ""
    property string settingKey: ""
    readonly property real swatchSize: Math.round(Theme.fontSizeMedium * 3.4)
    readonly property string value: input.value

    spacing: Theme.spacingS
    width: parent ? parent.width : implicitWidth

    StringSetting {
        id: input

        defaultValue: row.defaultColor
        description: row.description
        label: row.label
        placeholder: row.defaultColor
        settingKey: row.settingKey
        width: row.width - row.swatchSize - row.spacing
    }
    Rectangle {
        anchors.bottom: parent.bottom
        border.color: Theme.outlineVariant
        border.width: 1
        color: (input.value || "").trim() !== "" ? input.value.trim() : row.defaultColor
        height: row.swatchSize
        radius: Theme.cornerRadius
        width: row.swatchSize
    }
}
