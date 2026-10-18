// The files DMS loads (the widget, the settings and the views) must load: they import DMS's own qs.* modules,
// which the harness stands in for (tests/Helpers/Harness/Common, Widgets, Services, Modules).
import QtQuick
import "../../Helpers"

TestSuite {
    function load(relativePath) {
        let component = Qt.createComponent("file://" + repoRoot + "/" + relativePath);
        check(component.status === Component.Ready, relativePath + ": " + component.errorString());
        return component;
    }
    function test_every_qml_file_of_the_plugin_loads() {
        ["Widget", "Settings", "Views/SymbolRow", "Views/PopoutPanel", "Views/PriceChart", "Views/ConfiguredSymbol", "Views/IconButton", "Views/ColorSettingRow", "Views/HorizontalBarPill", "Views/VerticalBarPill"].forEach(function (name) {
            load("src/QML/" + name + ".qml");
        });
    }
}
