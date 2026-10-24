// Load the real widget with damaged host settings: preserve the original and back it up without a binding/write loop.
import QtQuick
import "../../../src/QML/Services"
import "../../Helpers"

TestSuite {
    property Component serviceType: Component {
        QtObject {
            property var data: ({
                    symbols: "{broken"
                })
            property int saves: 0

            function loadPluginData(pluginId, key, fallback) {
                return key in data ? data[key] : fallback;
            }
            function savePluginData(pluginId, key, value) {
                saves++;
                let next = Object.assign({}, data);
                next[key] = value;
                data = next;
                return true;
            }
        }
    }
    property var widget: null

    function async_damaged_host_data_is_preserved_and_backed_up_once(done) {
        Logger.configure({
            sink: function () {}
        });
        let service = serviceType.createObject(null);
        let component = Qt.createComponent("file://" + repoRoot + "/src/QML/Widget.qml");
        check(component.status === Component.Ready, component.errorString());
        widget = component.createObject(null, {
            pluginId: "markets",
            pluginService: service,
            pluginData: Qt.binding(function () {
                return service.data;
            }),
            cacheDirectory: freshDirectory("damaged-settings")
        });
        waitUntil(function () {
            return service.data.symbolsBackup === "{broken";
        }, function (problem) {
            if (problem) {
                done(problem);
                return;
            }
            done(service.saves === 1 && service.data.symbols === "{broken" && widget.symbols.length === 0 ? "" : "the original was overwritten or its backup was written repeatedly");
        });
    }
    function teardown() {
        if (widget) {
            widget.destroy();
            widget = null;
        }
    }
}
