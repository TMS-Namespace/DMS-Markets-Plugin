// SelectionRow.qml - a dropdown setting like DMS's SelectionSetting, which keeps showing the value it is SET to.
//
//   settingKey, label, description, options ([{ label, value }]), defaultValue   as for DMS's SelectionSetting
//   value                                                                        the selected value (read it, or set it)
//
// Why this exists: DMS's SelectionSetting binds its dropdown's shown text to `value`, but DankDropdown assigns that text
// itself as soon as the user picks an option, which silently destroys the binding. From then on setting `value` from code
// (e.g. filling the form from a symbol picked in the list) changes `value` but not what the dropdown shows. A Binding
// element is not destroyed by such an assignment, so the dropdown follows `value` always.
//
// Like DMS's own setting controls it loads its saved value when the settings page asks (loadValue, also when the plugin
// service attaches or the data changes) and saves every change, through the page it sits in (the nearest parent that has
// saveValue and loadValue).
import QtQuick
import qs.Common
import qs.Widgets

Column {
    id: root

    property string settingKey: ""
    property string label: ""
    property string description: ""
    property var    options: []
    property string defaultValue: ""
    property string value: defaultValue
    property alias  dropdown: field

    width: parent ? parent.width : implicitWidth
    spacing: Theme.spacingS

    // The page this row sits in (the nearest parent that can save and load values), or null.
    function _settings() {
        var item = root.parent
        while (item) {
            if (item.saveValue !== undefined && item.loadValue !== undefined) return item
            item = item.parent
        }
        return null
    }

    // Takes the saved value (called by the page when its plugin service attaches or its data changes).
    function loadValue() {
        var settings = _settings()
        if (settings && settings.pluginService) value = settings.loadValue(settingKey, defaultValue)
    }

    Component.onCompleted: loadValue()

    onValueChanged: {
        var settings = _settings()
        if (settings) settings.saveValue(settingKey, value)
    }

    readonly property var optionLabels: {
        var labels = []
        for (var i = 0; i < options.length; i++) labels.push(options[i].label || options[i])
        return labels
    }
    readonly property var valueToLabel: {
        var map = {}
        for (var i = 0; i < options.length; i++) {
            var option = options[i]
            if (typeof option === "object") map[option.value] = option.label
            else map[option] = option
        }
        return map
    }
    readonly property var labelToValue: {
        var map = {}
        for (var i = 0; i < options.length; i++) {
            var option = options[i]
            if (typeof option === "object") map[option.label] = option.value
            else map[option] = option
        }
        return map
    }

    DankDropdown {
        id: field
        width: parent.width
        text: root.label
        description: root.description
        options: root.optionLabels
        onValueChanged: newValue => root.value = root.labelToValue[newValue] || newValue
    }

    // The dropdown's shown text always follows `value` (see the note at the top).
    Binding {
        target: field
        property: "currentValue"
        value: root.valueToLabel[root.value] || root.value
    }
}
