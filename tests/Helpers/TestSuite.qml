// TestSuite.qml — base type of every QML test: assertion helpers. Define test_* functions in the root.
import QtQml
import Quickshell
import Quickshell.Io

QtObject {
    id: suite

    function _fail(message) { throw new Error(message) }

    function check(condition, message) {
        if (!condition) _fail(message || "check failed")
    }

    // Compares by value (JSON), so arrays/objects can be compared.
    function equal(actual, expected, message) {
        var actualJson = JSON.stringify(actual), expectedJson = JSON.stringify(expected)
        if (actualJson !== expectedJson) _fail((message || "values differ") + "\n  actual:   " + actualJson + "\n  expected: " + expectedJson)
    }

    function same(actual, expected, message) {
        if (actual !== expected)
            _fail((message || "values are not identical") + "\n  actual:   " + String(actual) + "\n  expected: " + String(expected))
    }

    function near(actual, expected, tolerance, message) {
        if (Math.abs(actual - expected) > (tolerance === undefined ? 1e-9 : tolerance))
            _fail((message || "numbers differ") + "\n  actual:   " + actual + "\n  expected: " + expected)
    }

    // Passes when action throws and the error's message contains `fragment`; returns the error.
    function throws(action, fragment, message) {
        var caught = null
        try { action() } catch (error) { caught = error }
        if (!caught) _fail((message || "expected an error") + " — nothing was thrown")
        if (fragment && String(caught.message).indexOf(fragment) === -1)
            _fail((message || "unexpected error") + "\n  expected to contain: " + fragment + "\n  got: " + caught.message)
        return caught
    }

    function doesNotThrow(action, message) {
        try { action() } catch (error) { _fail((message || "unexpected error") + ": " + error.message) }
    }

    // ── Waiting and running programs (for async_* tests) ─────────────────────
    // Calls done("") as soon as condition() is true, or done("timed out: <what>") after timeoutMs.
    property var _waits: []
    property Component _waitType: Component {
        Timer {
            property var condition
            property var done
            property var describe
            property real deadline: 0
            interval: 20; repeat: true; running: true
            onTriggered: {
                var result = null
                try { if (condition()) result = "" } catch (error) { result = "condition threw: " + error.message }
                if (result === null && Date.now() > deadline) result = "timed out: " + (describe ? describe() : "")
                if (result !== null) { running = false; var callback = done; suite._forget(this); destroy(); callback(result) }
            }
        }
    }
    function waitUntil(condition, done, timeoutMs, describe) {
        _keep(_waitType.createObject(null, { condition: condition, done: done, describe: describe || null, deadline: Date.now() + (timeoutMs || 10000) }))
    }
    // Objects made without a parent belong to the JS engine and would be collected while still waiting: keep them.
    property var _alive: []
    function _keep(object) { _alive = _alive.concat([object]) }
    function _forget(object) { _alive = _alive.filter(function(other) { return other !== object }) }

    // A directory of its own for one test, below the cache root the runner gives every QML run (XDG_CACHE_HOME).
    property int _directoryCounter: 0
    function freshDirectory(label) {
        return Quickshell.env("XDG_CACHE_HOME") + "/" + (label || "t") + "-" + Date.now() + "-" + (++_directoryCounter)
    }

    property Component _shellType: Component {
        Process {
            property var done
            property string _text: ""
            property bool _exited: false
            property bool _streamed: false
            property int _code: -1
            function _finish() { if (_exited && _streamed) { var callback = done; suite._forget(this); destroy(); callback(_code, _text) } }
            stdout: StdioCollector { onStreamFinished: { _text = text; _streamed = true; _finish() } }
            onExited: code => { _code = code; _exited = true; _finish() }
        }
    }
    // Runs `sh -c script` with the given arguments; done(exitCode, stdout).
    function shell(script, args, done) {
        _keep(_shellType.createObject(null, { command: ["sh", "-c", script, "sh"].concat(args || []), done: done, running: true }))
    }

    // ── Reading source files and extracting QML functions ────────────────────
    // The repository root (the harness is started on one test file under <root>/tests/).
    readonly property string repoRoot: Quickshell.env("TEST_FILE").split("/tests/")[0]

    property Component _viewType: Component { FileView { blockLoading: true } }

    function readFile(relativePath) {
        var view = _viewType.createObject(null, { path: repoRoot + "/" + relativePath })
        var text = view.text()
        view.destroy()
        return text
    }

    // Source of `function name(...) { ... }` found in `text` (brace matched).
    function functionSource(text, name) {
        var start = text.search(new RegExp("function\\s+" + name + "\\s*\\("))
        if (start === -1) _fail("function " + name + " not found")
        var open = text.indexOf("{", text.indexOf(")", start))
        var depth = 0
        for (var i = open; i < text.length; i++) {
            if (text[i] === "{") depth++
            else if (text[i] === "}" && --depth === 0) return text.slice(start, i + 1)
        }
        _fail("unbalanced braces in " + name)
    }

    // Compiles a function of a QML file with `scope` ({ identifier: value }) as its free variables, so
    // a test can run the REAL function against the real singletons and stub controls. Assignments to
    // names in `scope` land on the scope object (it is passed as `scope`).
    function loadFunction(relativePath, name, scope) {
        var keys = Object.keys(scope)
        var body = functionSource(readFile(relativePath), name)
        // identifiers resolve through `with (scope)` so assignments (e.g. editIndex = 3) are visible to the test
        var factory = new Function("scope", "with (scope) { " + body + "; return " + name + " }")
        return factory(scope)
    }
}
