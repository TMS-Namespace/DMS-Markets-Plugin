// ColorSettingRow.qml — a hex-colour text setting with a swatch showing the colour (or the default while empty).
//
//   settingKey, label, description, defaultColor   as for DMS's StringSetting
//   value (read-only)                              the text typed
import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

Row {
    id: row

    property string settingKey: ""
    property string label: ""
    property string description: ""
    property string defaultColor: ""
    readonly property string value: input.value

    width: parent ? parent.width : implicitWidth
    spacing: Theme.spacingS

    readonly property real swatchSize: Math.round(Theme.fontSizeMedium * 3.4)

    StringSetting {
        id: input
        settingKey: row.settingKey
        label: row.label
        description: row.description
        placeholder: row.defaultColor
        defaultValue: row.defaultColor
        width: row.width - row.swatchSize - row.spacing
    }

    Rectangle {
        width: row.swatchSize; height: row.swatchSize
        radius: Theme.cornerRadius
        anchors.bottom: parent.bottom
        color: (input.value || "").trim() !== "" ? input.value.trim() : row.defaultColor
        border.color: Theme.outlineVariant; border.width: 1
    }
}
