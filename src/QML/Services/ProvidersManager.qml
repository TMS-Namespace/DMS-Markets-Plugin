// ProvidersManager.qml - manages the providers: which ones are supported, starting them, handing them out
// (QML singleton, shared by the widget and the settings).
//
// UI needs a provider → asks the manager for it by ProviderType → gets it wrapped in a ProviderHandler,
// which does every query. The manager itself never queries a provider's JS API:
//   • it lists the supported providers (the ProviderType enum; `sources` maps each to its two JS modules,
//     both in the provider's own folder: <Name>Properties.js, plain data, and <Name>Api.js)
//   • it initiates each one: checks its declaration (ProviderRules.assertDeclaration), builds its
//     ProviderProperties contract and creates its ProviderHandler
//   • a provider that fails to start is recorded (`loadErrors`) and shown in the settings instead of
//     taking the others down
// Saved symbols name their provider as text; `typeOf` / `idOf` convert at that boundary.
pragma Singleton
import QtQml
import "../../JS/Contracts/PluginError.js" as PluginError
import "../../JS/Helpers/ProviderRules.js" as ProviderRules
import "../../JS/Providers/Stooq/StooqApi.js" as StooqApi
import "../../JS/Providers/Stooq/StooqProperties.js" as StooqProperties
import "../../JS/Providers/Wise/WiseApi.js" as WiseApi
import "../../JS/Providers/Wise/WiseProperties.js" as WiseProperties
import "../../JS/Providers/Yahoo/YahooApi.js" as YahooApi
import "../../JS/Providers/Yahoo/YahooProperties.js" as YahooProperties
import "../Contracts"

QtObject {
    id: root

    property Component _handlerType: Component {
        ProviderHandler {
        }
    }
    property var _ids: ({})           // ProviderType → saved text id (of every source, started or not)

    property Component _loadErrorType: Component {
        ProviderLoadError {
        }
    }
    property Component _propertiesType: Component {
        ProviderProperties {
        }
    }
    readonly property string defaultId: idOf(defaultType)         // the default provider as saved text

    readonly property int defaultType: types.length > 0 ? types[0] : -1
    property var handlers: ({})       // ProviderType → ProviderHandler, for the providers that started
    property var loadErrors: []       // ProviderLoadError, for the ones that did not

    // The supported providers, in order (the first that starts is the default): { type, id, name, properties, api }.
    property var sources: [
        {
            type: ProviderType.Yahoo,
            id: "yahoo",
            name: "Yahoo Finance",
            properties: YahooProperties,
            api: YahooApi
        },
        {
            type: ProviderType.Stooq,
            id: "stooq",
            name: "Stooq",
            properties: StooqProperties,
            api: StooqApi
        },
        {
            type: ProviderType.Wise,
            id: "wise",
            name: "Wise",
            properties: WiseProperties,
            api: WiseApi
        }
    ]
    readonly property var types: Object.keys(handlers).map(Number)      // started providers, in enum order

    // Three-letter alias of a provider by its saved text id (what charts show; the id in capitals when it is not available).
    function aliasOf(id) {
        var handler = handlerFromId(id);
        return handler ? handler.properties.alias : String(id || "").slice(0, 3).toUpperCase();
    }

    // ── Handing out ──────────────────────────────────────────────────────────

    // The handler of a provider; null when that provider did not start.
    function handlerFor(type) {
        return handlers[type] || null;
    }
    // Find the provider facade by its persisted text identifier.
    function handlerFromId(id) {
        return handlerFor(typeOf(id));
    }
    // Convert a provider type into its persisted text identifier.
    function idOf(type) {
        return _ids[type] || "";
    }

    // Display name of a provider by its saved text id (the id itself when it is not available).
    function nameOf(id) {
        var handler = handlerFromId(id);
        return handler ? handler.properties.name : id;
    }

    // Dropdown entries for DMS's SelectionSetting: { label, value }; the value is the saved text id.
    function options() {
        return types.map(function (type) {
            return {
                label: handlers[type].properties.name,
                value: idOf(type)
            };
        });
    }

    // (Re)starts every source with fresh handlers; used at start-up and by tests.
    function reload(list) {
        for (let previousType in handlers)
            handlers[previousType].destroy();
        let started = {}, failed = [];
        list.forEach(function (source) {
            try {
                let declared = source.properties.create();
                ProviderRules.assertDeclaration(source.id, declared, source.api);
                let properties = _propertiesType.createObject(null) as ProviderProperties;
                for (let key in declared) {
                    if (!(key in properties))
                        throw new PluginError.PluginError(PluginError.Code.PROVIDER_CONFIG, "A data provider is misconfigured and was not loaded.", "Provider '" + source.id + "': unknown property '" + key + "' in its declaration");
                    properties[key] = declared[key];
                }
                let handler = _handlerType.createObject(null, {
                    type: source.type,
                    properties: properties
                }) as ProviderHandler;
                handler.api = source.api;         // assigned, not passed to createObject: that would flatten the module's functions away
                started[source.type] = handler;
                Logger.debug("providers", "started " + source.id + " (" + properties.name + ")");
            } catch (caughtError) {
                Logger.debug("providers", "could not start " + source.id + ": " + String(caughtError && caughtError.message));
                let error = PluginError.from(caughtError, PluginError.Code.PROVIDER_CONFIG);
                failed.push(_loadErrorType.createObject(null, {
                    id: source.id,
                    name: source.name,
                    error: error,
                    userMessage: source.name + " couldn't be loaded and is unavailable. " + error.userMessage
                }));
            }
        });
        let ids = {};
        list.forEach(function (source) {
            ids[source.type] = source.id;
        });
        _ids = ids;                       // assigned whole, so bindings that read it update
        handlers = started;
        loadErrors = failed;
        Logger.debug("providers", Object.keys(started).length + " of " + list.length + " providers started");
    }

    // Like handlerFromId, but a provider that is not available is an error (UNKNOWN_PROVIDER).
    function requireFromId(id) {
        let handler = handlerFromId(id);
        if (!handler)
            throw new PluginError.PluginError(PluginError.Code.UNKNOWN_PROVIDER, "This data provider isn't available.", "Unknown provider '" + id + "'");
        return handler;
    }

    // Saved symbols hold the provider as text: the type for it, or -1 when it is not a supported provider.
    function typeOf(id) {
        for (let type in _ids)
            if (_ids[type] === id)
                return Number(type);
        return -1;
    }

    Component.onCompleted: reload(sources)
}
