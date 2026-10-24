// A dropdown setting must keep showing the value it is set to, also after the user picked an option in it. (DMS's own
// SelectionSetting loses that: DDropdown assigns its shown text itself when the user picks, destroying the binding, so a
// symbol picked in the list no longer updated the dropdowns the user had touched.)
import QtQuick
import "../../../../src/QML/Views"
import "../../../Helpers"
import qs.DCommon.Widgets

TestSuite {
    property var made: []
    property Component pageType: Component {
        Item {
            property var pluginService: ({})
            property alias row: selection
            property var saved: ({})

            function loadValue(key, fallback) {
                return key in saved ? saved[key] : fallback;
            }
            function saveValue(key, value) {
                saved[key] = value;
            }

            SelectionRow {
                id: selection

                defaultValue: "1d"
                label: "Range"
                options: [
                    {
                        label: "1 Day",
                        value: "1d"
                    },
                    {
                        label: "1 Week",
                        value: "1w"
                    },
                    {
                        label: "1 Month",
                        value: "1M"
                    }
                ]
                settingKey: "_k"
            }
        }
    }
    // The way DMS's SelectionSetting wires the dropdown: a plain binding (for comparison).
    property Component plainType: Component {
        Item {
            property alias dropdown: field
            readonly property var labels: ({
                    "1d": "1 Day",
                    "1w": "1 Week",
                    "1M": "1 Month"
                })
            property string value: "1d"

            DDropdown {
                id: field

                currentValue: parent.labels[parent.value]
            }
        }
    }

    function make(type) {
        var item = type.createObject(null);
        made.push(item);
        return item;
    }
    function teardown() {
        made.forEach(function (item) {
            item.destroy();
        });
        made = [];
    }
    function test_a_choice_by_the_user_sets_value_and_is_saved() {
        let page = make(pageType), row = page.row;
        row.dropdown.choose("1 Week");
        same(row.value, "1w");
        same(page.saved._k, "1w");
    }
    function test_after_the_user_picked_an_option_the_dropdown_still_follows_value_set_from_code() {
        let row = make(pageType).row;
        row.dropdown.choose("1 Month");                                // the user's choice (the real dropdown assigns its text)
        same(row.dropdown.currentValue, "1 Month");
        row.value = "1d";                                              // e.g. a symbol picked in the list
        same(row.dropdown.currentValue, "1 Day", "the dropdown shows the symbol's value, not the user's earlier choice");
        row.dropdown.choose("1 Week");
        row.value = "1M";
        same(row.dropdown.currentValue, "1 Month", "...every time");
    }
    function test_changed_options_keep_the_shown_text_right() {
        let row = make(pageType).row;
        row.dropdown.choose("1 Week");
        row.options = [
            {
                label: "1 Day",
                value: "1d"
            },
            {
                label: "One Week",
                value: "1w"
            }
        ];
        same(row.dropdown.currentValue, "One Week");
    }
    function test_it_loads_the_saved_value_when_the_page_asks() {
        let page = make(pageType);
        page.saved._k = "1M";
        page.row.loadValue();
        same(page.row.value, "1M");
        same(page.row.dropdown.currentValue, "1 Month");
    }
    function test_the_dropdown_shows_the_default_and_follows_value_set_from_code() {
        let row = make(pageType).row;
        same(row.dropdown.currentValue, "1 Day");
        row.value = "1w";
        same(row.dropdown.currentValue, "1 Week");
        row.value = "1M";
        same(row.dropdown.currentValue, "1 Month");
    }
    function test_the_plain_binding_of_dms_s_setting_does_lose_the_value_after_a_choice() {
        // Documents WHY SelectionRow exists: this is the behaviour that caused the bug.
        let plain = make(plainType);
        plain.dropdown.choose("1 Month");
        plain.value = "1d";
        same(plain.dropdown.currentValue, "1 Month", "the plain binding is gone after the user's choice");
    }
}
