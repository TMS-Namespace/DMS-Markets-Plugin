// FetchCommand.js - logic: the process command line that fetches one URL.
//
// The URL is always passed as a separate argument (never spliced into shell text). The default
// script prints one envelope line (curl exit code, HTTP status) and then the body, and exits 0
// whenever the script itself ran, so HTTP and network failures reach ResponseInterpreter with
// their real status instead of being lost in an exit code (no `curl -f`).
//
//   FetchCommand.build(url, tailLines, customScript)  → string[]   argv for a Quickshell Process
//   `customScript` (optional) replaces the default script text (Stooq); `tailLines` > 0 keeps only
//   the last N lines of the body.

.pragma library
.import "Constants.js" as Constants
.import "../Contracts/PluginError.js" as PluginError
.import "ResponseInterpreter.js" as ResponseInterpreter
// Compare complete fetch commands, including credentials and output limits, without exposing them in logs.
function transferKey(url, command) {
    return JSON.stringify([url, command]);
}

// Build a fetch script that prints its status before the response body.
function plainScript(tailLines) {
    let script = "";
    script += "set -e\n";
    script +=
        "if command -v ionice >/dev/null 2>&1; then ionice -c" +
        Constants.PROCESS_IONICE_CLASS +
        " -p $$ >/dev/null 2>&1 || true; fi\n";
    script +=
        "if command -v renice >/dev/null 2>&1; then renice -n " +
        Constants.PROCESS_NICE_LEVEL +
        " -p $$ >/dev/null 2>&1 || true; fi\n";
    script += 'body_file="$(mktemp)"\n';
    script += 'cleanup() { rm -f "$body_file"; }\n';
    script += "trap cleanup EXIT\n";
    script += 'url="$1"\n';
    script += "curl_exit=0\n";
    script += "http_status=$(curl -sSL --connect-timeout " + Constants.CURL_CONNECT_TIMEOUT_SECONDS;
    script += " --max-time " + Constants.CURL_MAX_TIME_SECONDS;
    script += " -H 'User-Agent: " + Constants.FETCH_USER_AGENT + "'";
    script += ' -w \'%{http_code}\' "$url" -o "$body_file") || curl_exit=$?\n';
    script += "printf '" + ResponseInterpreter.ENVELOPE_PREFIX + ' %s %s\\n\' "$curl_exit" "$http_status"\n';
    script += 'if [ "$curl_exit" -eq 0 ]; then\n';
    script += tailLines > 0 ? "  tail -n " + tailLines + ' "$body_file"\n' : '  cat "$body_file"\n';
    script += "fi\n";
    return script;
}

// Validate the fetch arguments and pass the URL separately from shell text.
function build(url, tailLines, customScript) {
    if (typeof url !== "string" || url.indexOf("https://") !== 0)
        throw PluginError.internal("a fetch URL must be https, got " + JSON.stringify(url));
    if (typeof tailLines !== "number" || tailLines < 0 || Math.floor(tailLines) !== tailLines)
        throw PluginError.internal("tailLines must be a non-negative integer");
    let script = customScript || plainScript(tailLines);
    return Constants.FETCH_SHELL_COMMAND.concat([script, "markets-fetch", url]);
}
