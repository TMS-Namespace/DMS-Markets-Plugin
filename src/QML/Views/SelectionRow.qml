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

    property string defaultValue: ""
    property string description: ""
    property alias dropdown: field
    property string label: ""
    readonly property var labelToValue: {
        let map = {};
        for (let i = 0; i < options.length; i++) {
            let option = options[i];
            if (typeof option === "object")
                map[option.label] = option.value;
            else
                map[option] = option;
        }
        return map;
    }
    readonly property var optionLabels: {
        let labels = [];
        for (let i = 0; i < options.length; i++)
            labels.push(options[i].label || options[i]);
        return labels;
    }
    property var options: []
    property string settingKey: ""
    property string value: defaultValue
    readonly property var valueToLabel: {
        let map = {};
        for (let i = 0; i < options.length; i++) {
            let option = options[i];
            if (typeof option === "object")
                map[option.value] = option.label;
            else
                map[option] = option;
        }
        return map;
    }

    // The page this row sits in (the nearest parent that can save and load values), or null.
    function _settings() {
        let item = root.parent;
        while (item) {
            if ("saveValue" in item && "loadValue" in item)
                return item;
            item = item.parent;
        }
        return null;
    }

    // Takes the saved value (called by the page when its plugin service attaches or its data changes).
    function loadValue() {
        let settings = _settings();
        if (settings && settings.pluginService)
            value = settings.loadValue(settingKey, defaultValue);
    }

    spacing: Theme.spacingS
    width: parent ? parent.width : implicitWidth

    Component.onCompleted: loadValue()
    onValueChanged: {
        let settings = _settings();
        if (settings)
            settings.saveValue(settingKey, value);
    }

    DankDropdown {
        id: field

        description: root.description
        options: root.optionLabels
        text: root.label
        width: parent.width

        onValueChanged: newValue => root.value = root.labelToValue[newValue] || newValue
    }

    // The dropdown's shown text always follows `value` (see the note at the top).
    Binding {
        property: "currentValue"
        target: field
        value: root.valueToLabel[root.value] || root.value
    }
}
