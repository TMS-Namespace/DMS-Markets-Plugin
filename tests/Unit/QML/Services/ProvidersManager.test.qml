import QtQml
import "../../../../src/QML/Contracts"
import "../../../../src/QML/Services"
import "../../../Helpers"

TestSuite {
    function setup() {
        ProvidersManager.reload(ProvidersManager.sources);
    }
    function test_a_broken_provider_does_not_take_the_others_down() {
        let good = ProvidersManager.sources[0];
        function declared(change) {
            return {
                create: function () {
                    var properties = good.properties.create();
                    for (let field in change)
                        properties[field] = change[field];
                    return properties;
                }
            };
        }
        let broken = [good,
            {
                type: ProviderType.Stooq,
                id: "stooq",
                name: "Ghost",
                properties: {
                    create: function () {
                        throw new Error("cannot even declare itself");
                    }
                },
                api: good.api
            },
            {
                type: ProviderType.Wise,
                id: "wise",
                name: "Wrong id",
                properties: good.properties,
                api: good.api
            }                                  // declares 'yahoo'
            ,
            {
                type: 10,
                id: "p2",
                name: "Bad pattern",
                properties: declared({
                    providerId: "p2",
                    symbolPattern: "^.+$"
                }),
                api: good.api
            },
            {
                type: 11,
                id: "p3",
                name: "No resolutions",
                properties: declared({
                    providerId: "p3",
                    priceResolutions: []
                }),
                api: good.api
            },
            {
                type: 12,
                id: "p4",
                name: "No API",
                properties: declared({
                    providerId: "p4"
                }),
                api: {}
            },
            {
                type: 13,
                id: "p5",
                name: "Unknown field",
                properties: declared({
                    providerId: "p5",
                    surprise: 1
                }),
                api: good.api
            }
        ];
        ProvidersManager.reload(broken);
        equal(ProvidersManager.types, [ProviderType.Yahoo], "only the sound provider starts");
        equal(ProvidersManager.loadErrors.map(function (loadError) {
            return loadError.id;
        }), ["stooq", "wise", "p2", "p3", "p4", "p5"]);
        check(ProvidersManager.loadErrors[0].userMessage.indexOf("Ghost couldn't be loaded") === 0);
        check(ProvidersManager.loadErrors[2].error.details.indexOf("must not allow") !== -1);
        check(ProvidersManager.handlerFor(ProviderType.Yahoo).validateSymbol("EURUSD=X").valid, "the sound one still works");
    }
    function test_it_hands_out_one_handler_per_type_that_exposes_its_type_and_properties() {
        ProvidersManager.types.forEach(function (type) {
            let handler = ProvidersManager.handlerFor(type);
            same(handler.type, type, "the handler exposes its type");
            same(handler.properties.providerId, ProvidersManager.idOf(type), "...and its properties");
            same(ProvidersManager.handlerFor(type), handler, "the same handler every time");
        });
        same(ProvidersManager.handlerFor(ProviderType.Wise).properties.name, "Wise");
        same(ProvidersManager.handlerFor(99), null, "an unknown type has no handler");
    }
    function test_saved_text_ids_convert_to_types_and_back() {
        same(ProvidersManager.typeOf("wise"), ProviderType.Wise);
        same(ProvidersManager.idOf(ProviderType.Wise), "wise");
        same(ProvidersManager.typeOf("ghost"), -1);
        same(ProvidersManager.idOf(99), "");
        same(ProvidersManager.handlerFromId("yahoo").type, ProviderType.Yahoo);
        same(ProvidersManager.handlerFromId("ghost"), null);
        same(ProvidersManager.nameOf("wise"), "Wise");
        same(ProvidersManager.nameOf("ghost"), "ghost");
        same(ProvidersManager.aliasOf("yahoo"), "YHF");
        same(ProvidersManager.aliasOf("wise"), "WIS");
        same(ProvidersManager.aliasOf("stooq"), "STK");
        same(ProvidersManager.aliasOf("ghost"), "GHO", "an unknown provider still gets three letters");
        same(ProvidersManager.aliasOf(undefined), "");
        ProvidersManager.types.forEach(function (type) {
            check(/^[A-Z]{3}$/.test(ProvidersManager.handlerFor(type).properties.alias), "every provider has an alias");
        });
        let error = throws(function () {
            ProvidersManager.requireFromId("ghost");
        }, "ghost");
        same(error.code, "unknownProvider");
        equal(ProvidersManager.options(), [
            {
                label: "Yahoo Finance",
                value: "yahoo"
            },
            {
                label: "Stooq",
                value: "stooq"
            },
            {
                label: "Wise",
                value: "wise"
            }
        ]);
    }
    function test_the_enum_lists_the_supported_providers_and_the_manager_starts_them() {
        equal(ProvidersManager.types, [ProviderType.Yahoo, ProviderType.Stooq, ProviderType.Wise]);
        equal(ProvidersManager.loadErrors.length, 0);
        same(ProvidersManager.defaultType, ProviderType.Yahoo);
        same(ProvidersManager.defaultId, "yahoo");
    }
    function test_the_manager_does_no_provider_work_itself() {
        let source = readFile("src/QML/Services/ProvidersManager.qml");
        check(!/priceUrl|historyUrl|parsePrice|parseHistory|\.pageUrl|FetchCommand|ResponseInterpreter|SymbolRules|SelectionPolicy|SymbolMigration|migrateSymbols/.test(source.replace(/\/\/.*$/gm, "")), "requests, parsing and checks are the handler's job");
    }
}
