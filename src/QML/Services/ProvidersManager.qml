// ProvidersManager.qml — manages the providers: which ones are supported, starting them, handing them out
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
import "../Contracts"
import "../../JS/Contracts/PluginError.js" as PluginError
import "../../JS/Helpers/ProviderRules.js" as ProviderRules
import "../../JS/Helpers/SymbolMigration.js" as SymbolMigration
import "../../JS/Providers/Yahoo/YahooProperties.js" as YahooProperties
import "../../JS/Providers/Yahoo/YahooApi.js" as YahooApi
import "../../JS/Providers/Stooq/StooqProperties.js" as StooqProperties
import "../../JS/Providers/Stooq/StooqApi.js" as StooqApi
import "../../JS/Providers/Wise/WiseProperties.js" as WiseProperties
import "../../JS/Providers/Wise/WiseApi.js" as WiseApi

QtObject {
    id: root

    // The supported providers, in order (the first that starts is the default): { type, id, name, properties, api }.
    property var sources: [
        { type: ProviderType.Yahoo, id: "yahoo", name: "Yahoo Finance", properties: YahooProperties, api: YahooApi },
        { type: ProviderType.Stooq, id: "stooq", name: "Stooq",         properties: StooqProperties, api: StooqApi },
        { type: ProviderType.Wise,  id: "wise",  name: "Wise",          properties: WiseProperties,  api: WiseApi }
    ]

    property var handlers: ({})       // ProviderType → ProviderHandler, for the providers that started
    property var loadErrors: []       // ProviderLoadError, for the ones that did not
    readonly property var types: Object.keys(handlers).map(Number)      // started providers, in enum order
    readonly property int defaultType: types.length > 0 ? types[0] : -1
    readonly property string defaultId: idOf(defaultType)         // the default provider as saved text

    property Component _handlerType: Component { ProviderHandler {} }
    property Component _propertiesType: Component { ProviderProperties {} }
    property Component _loadErrorType: Component { ProviderLoadError {} }

    Component.onCompleted: reload(sources)

    // (Re)starts every source with fresh handlers; used at start-up and by tests.
    function reload(list) {
        for (var previousType in handlers) handlers[previousType].destroy()
        var started = {}, failed = []
        list.forEach(function(source) {
            try {
                var declared = source.properties.create()
                ProviderRules.assertDeclaration(source.id, declared, source.api)
                var properties = _propertiesType.createObject(null)
                for (var key in declared) {
                    if (!(key in properties))
                        throw new PluginError.PluginError(PluginError.Code.PROVIDER_CONFIG, "A data provider is misconfigured and was not loaded.",
                                                          "Provider '" + source.id + "': unknown property '" + key + "' in its declaration")
                    properties[key] = declared[key]
                }
                var handler = _handlerType.createObject(null, { type: source.type, properties: properties })
                handler.api = source.api         // assigned, not passed to createObject: that would flatten the module's functions away
                started[source.type] = handler
                Logger.debug("providers", "started " + source.id + " (" + properties.name + ")")
            } catch (e) {
                Logger.debug("providers", "could not start " + source.id + ": " + String(e && e.message))
                failed.push(_loadErrorType.createObject(null, { id: source.id, name: source.name,
                                                                error: PluginError.from(e, PluginError.Code.PROVIDER_CONFIG) }))
            }
        })
        var ids = {}
        list.forEach(function(source) { ids[source.type] = source.id })
        _ids = ids                       // assigned whole, so bindings that read it update
        handlers = started
        loadErrors = failed
        Logger.debug("providers", Object.keys(started).length + " of " + list.length + " providers started")
    }

    property var _ids: ({})           // ProviderType → saved text id (of every source, started or not)

    // ── Handing out ──────────────────────────────────────────────────────────

    // The handler of a provider; null when that provider did not start.
    function handlerFor(type) { return handlers[type] || null }

    // Saved symbols hold the provider as text: the type for it, or -1 when it is not a supported provider.
    function typeOf(id) {
        for (var type in _ids) if (_ids[type] === id) return Number(type)
        return -1
    }
    function idOf(type) { return _ids[type] || "" }
    function handlerFromId(id) { return handlerFor(typeOf(id)) }

    // Like handlerFromId, but a provider that is not available is an error (UNKNOWN_PROVIDER).
    function requireFromId(id) {
        var handler = handlerFromId(id)
        if (!handler)
            throw new PluginError.PluginError(PluginError.Code.UNKNOWN_PROVIDER, "This data provider isn't available.", "Unknown provider '" + id + "'")
        return handler
    }

    // Display name of a provider by its saved text id (the id itself when it is not available).
    function nameOf(id) { var handler = handlerFromId(id); return handler ? handler.properties.name : id }

    // Dropdown entries for DMS's SelectionSetting: { label, value }; the value is the saved text id.
    function options() {
        return types.map(function(type) { return { label: handlers[type].properties.name, value: idOf(type) } })
    }

    // ── Across providers ─────────────────────────────────────────────────────

    // Brings a saved symbol list up to the current format and moves each symbol's ranges to what its
    // provider serves (SymbolMigration). Returns { symbols, changed }.
    function migrateSymbols(list) {
        return SymbolMigration.migrate(list, defaultId, function(id) {
            var handler = handlerFromId(id)
            return handler ? handler.properties : null
        })
    }
}
