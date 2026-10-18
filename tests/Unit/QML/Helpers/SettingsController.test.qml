// Exercise the actual settings controller with plain form data and a storage service, without creating views.
import QtQuick
import "../../../../src/QML/Helpers"
import "../../../../src/QML/Services"
import "../../../Helpers"

TestSuite {
    property Component controllerType: Component {
        SettingsController {
        }
    }
    property Component serviceType: Component {
        QtObject {
            property var data: ({
                    symbols: "[]"
                })

            signal pluginDataChanged(string pluginId)

            function loadPluginData(pluginId, key, fallback) {
                return key in data ? data[key] : fallback;
            }
            function savePluginData(pluginId, key, value) {
                data = Object.assign({}, data, {
                    [key]: value
                });
                pluginDataChanged(pluginId);
            }
        }
    }

    function setup() {
        ErrorHandler.reset();
        Logger.configure({
            devMode: false
        });
        ProvidersManager.reload(ProvidersManager.sources);
    }

    // An emitted draft can cause control-like callbacks; they must not overwrite flags during loading.
    function test_loading_a_draft_does_not_save_partially_updated_flags() {
        let savedSymbol = {
            uid: "11111111-1111-4111-8111-111111111111",
            ticker: "BRLPLN",
            name: "Real",
            provider: "wise",
            priceResolution: "1h",
            changeResolution: "1d",
            chartResolution: "1d",
            chartRange: "1M",
            showChangeWhenPinned: true,
            invert: true,
            pinned: true
        };
        let service = serviceType.createObject(null, {
            data: {
                symbols: JSON.stringify([savedSymbol])
            }
        });
        let controller = controllerType.createObject(null, {
            pluginService: service
        }) as SettingsController;
        check(controller !== null);
        controller.draftRequested.connect(function (draft) {
            controller.formState = Object.assign({}, draft, {
                invert: false
            });
            controller.saveEditedSymbolFlags();
            controller.formState = draft;
        });
        controller.editSymbol(0);
        same(controller.editIndex, 0);
        same(controller.formState.invert, true);
        equal(JSON.parse(controller.loadValue("symbols", "[]")), [savedSymbol], "loading is not a user edit");
        controller.formState = Object.assign({}, controller.formState, {
            invert: false
        });
        controller.saveEditedSymbolFlags();
        same(JSON.parse(controller.loadValue("symbols", "[]"))[0].invert, false, "a later user edit is still saved");
        same(JSON.parse(controller.loadValue("symbols", "[]"))[0].pinned, true);
        controller.destroy();
        service.destroy();
    }

    // Validation, saving, and user messages must work with no editor or host widgets present.
    function test_plain_form_data_can_be_validated_and_saved_without_views() {
        let service = serviceType.createObject(null);
        let controller = controllerType.createObject(null, {
            pluginService: service
        }) as SettingsController;
        let errors = [], infos = [];
        controller.errorRequested.connect(function (message) {
            errors.push(message);
        });
        controller.infoRequested.connect(function (message) {
            infos.push(message);
        });
        controller.formState = {
            ticker: "INVALID",
            name: "Real",
            provider: "wise",
            priceResolution: "1h",
            changeResolution: "1d",
            chartResolution: "1d",
            chartRange: "1M",
            showChange: true,
            invert: false
        };
        controller.addOrUpdateSymbol();
        same(errors.length, 1);
        equal(JSON.parse(controller.loadValue("symbols", "[]")), []);
        controller.formState = Object.assign({}, controller.formState, {
            ticker: "BRLPLN"
        });
        controller.addOrUpdateSymbol();
        let saved = JSON.parse(controller.loadValue("symbols", "[]"));
        same(saved.length, 1);
        same(saved[0].ticker, "BRLPLN");
        same(saved[0].showChangeWhenPinned, true);
        same(infos.length, 1);
        controller.addOrUpdateSymbol();
        same(errors.length, 2, "the saved list is reloaded and duplicates are refused");
        same(JSON.parse(controller.loadValue("symbols", "[]")).length, 1);
        controller.destroy();
        service.destroy();
    }
}
