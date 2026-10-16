// ProviderType.qml - contract: the market-data providers the plugin supports.
//
// The one list of what exists. Everything that needs a provider names it with this enum and asks
// ProvidersManager for its ProviderHandler; nothing else enumerates providers. (Saved symbols store a
// provider as text - `ProvidersManager.typeOf` / `idOf` convert at that boundary.)
import QtQml

QtObject {
    enum Type { Yahoo, Stooq, Wise }
}
