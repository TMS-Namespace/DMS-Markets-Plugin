// ProviderLoadError.qml - contract: a provider that failed to load, listed in the settings.
//
//   id, name      the provider        error   the PluginError that stopped it
//   userMessage   "<name> couldn't be loaded and is unavailable. <reason>"
import QtQml

QtObject {
    property var error: null
    property string name: ""
    property string id: ""
    property string userMessage: ""
}
