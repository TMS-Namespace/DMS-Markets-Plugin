// ProviderApi.js - Base contract for provider implementations. Override every required method in a subclass.
// Methods are synchronous and pure: build URLs, parse responses, and return data; never fetch or store anything.
.pragma library
.import "PluginError.js" as PluginError

var RequiredMethods = Object.freeze([
    "priceUrl",
    "historyUrl",
    "changeUrl",
    "parsePrice",
    "parseHistory",
    "parseChange",
    "pageUrl"
]);
var OptionalMethods = Object.freeze(["extractApiError", "fetchScript"]);

// Report an inherited abstract method if an unchecked provider is called directly.
function missing(method) {
    throw new PluginError.PluginError(
        PluginError.Code.PROVIDER_CONFIG,
        "A data provider is misconfigured.",
        "Provider API must override " + method
    );
}

// Extend this class and export create() returning the concrete instance. Lint rejects missing overrides.
var ProviderApi = class ProviderApi {
    // Return a URL for the latest price candles. Credential may be ignored by anonymous providers.
    priceUrl(symbol, resolution, credential) {
        return missing("priceUrl");
    }
    // Return a URL for chart candles covering span at resolution.
    historyUrl(symbol, resolution, span, credential) {
        return missing("historyUrl");
    }
    // Return a URL for the previous-period reference close.
    changeUrl(symbol, resolution, credential) {
        return missing("changeUrl");
    }
    // Return at most limit validated OHLC candles, oldest first; limit <= 0 means all.
    parsePrice(responseText, limit) {
        return missing("parsePrice");
    }
    // Return at most limit validated chart candles, oldest first; limit <= 0 means all.
    parseHistory(responseText, limit) {
        return missing("parseHistory");
    }
    // Return a finite previous-period reference close as a number.
    parseChange(responseText) {
        return missing("parseChange");
    }
    // Return the browser page URL for a symbol.
    pageUrl(symbol) {
        return missing("pageUrl");
    }
    // Optional: return the provider's error message, or an empty string when absent.
    extractApiError(status, body) {
        return "";
    }
    // Optional: return a custom fetch script, or an empty string to use the common fetcher.
    fetchScript(tailLines) {
        return "";
    }
};
