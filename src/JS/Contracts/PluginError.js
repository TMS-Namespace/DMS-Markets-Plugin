// PluginError.js - the one error type the plugin throws.
//
// An error has two audiences, so it carries two messages:
//   userMessage  short, friendly, free of internals - what the symbol card / toast shows
//   message      developer detail (and `details`) - what goes to the log in devMode
//
// JS modules throw PluginError and never touch the UI; the QML layers catch, log
// (devMode) and display it through ErrorHandler.qml. DMS has no plugin error API of its
// own beyond ToastService, so this type is the plugin's own.
//
// ES5 constructor + prototype, like the rest of the JS here (works in QML's engine).

.pragma library
var Code = Object.freeze({
    INVALID_SYMBOL: "invalidSymbol", // not acceptable for the provider (format / length)
    UNSUPPORTED: "unsupported", // resolution / range / pull rate the provider cannot serve
    POLL_TOO_FAST: "pollTooFast", // refresh faster than the provider allows
    UNKNOWN_PROVIDER: "unknownProvider",
    PROVIDER_CONFIG: "providerConfig", // a provider is declared wrongly (developer error)
    NETWORK: "network", // cannot reach the provider
    TIMEOUT: "timeout",
    HTTP: "http", // the provider answered with an error status
    NOT_FOUND: "notFound", // unknown symbol at the provider
    RATE_LIMITED: "rateLimited",
    CREDENTIAL: "credential",
    PROCESS: "process", // curl / bash cannot be run
    PARSE: "parse", // the answer could not be understood
    NO_DATA: "noData", // understood, but nothing in it
    STORAGE: "storage", // saved data unreadable / cannot be written
    INTERNAL: "internal", // the plugin broke one of its own contracts (a bug, never the user's fault)
    UNKNOWN: "unknown" // anything that was not a PluginError
});

var _GENERIC_MESSAGE = "Something went wrong.";

// fields: { status?: number (HTTP status), retryable?: boolean, cause?: any }
function PluginError(code, userMessage, details, fields) {
    let extra = fields || {};
    this.name = "PluginError";
    this.code = code || Code.UNKNOWN;
    this.userMessage = userMessage || _GENERIC_MESSAGE;
    this.details = details || "";
    this.message = this.details ? this.userMessage + " - " + this.details : this.userMessage;
    this.status = typeof extra.status === "number" ? extra.status : 0;
    this.retryable = extra.retryable === true;
    this.cause = extra.cause;
    this.stack = new Error(this.message).stack || "";
}
PluginError.prototype = Object.create(Error.prototype);
PluginError.prototype.constructor = PluginError;

// A contract broken by the plugin's own code. Users get a neutral line; `detail` names the contract.
function internal(detail) {
    return new PluginError(Code.INTERNAL, "Something went wrong inside the plugin.", detail);
}

// Recognize errors created by the shared PluginError constructor.
function isPluginError(value) {
    return !!value && value instanceof PluginError;
}

// Any thrown value → PluginError. Foreign errors keep their message as developer
// detail and get the generic user message: raw exception text is never shown to users.
function from(value, fallbackCode) {
    if (isPluginError(value)) return value;
    let detail = value && value.message !== undefined ? String(value.message) : String(value);
    return new PluginError(fallbackCode || Code.UNKNOWN, _GENERIC_MESSAGE, detail, { cause: value });
}
