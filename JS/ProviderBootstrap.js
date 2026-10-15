// ProviderBootstrap.js — imports provider modules so they self-register.

.pragma library
.import "ProviderInterface.js" as PI
.import "YahooProvider.js" as YahooProvider
.import "StooqProvider.js" as StooqProvider
.import "WiseProvider.js" as WiseProvider

function ensureProvidersRegistered() {
    return PI.getProviderIds().length;
}
