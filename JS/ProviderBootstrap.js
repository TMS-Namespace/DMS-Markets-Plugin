// ProviderBootstrap.js — imports provider modules so they self-register.

.pragma library
.import "ProviderInterface.js" as PI
.import "YahooProvider.js" as YahooProvider
.import "StooqProvider.js" as StooqProvider

function ensureProvidersRegistered() {
    return PI.getProviderIds().length;
}
