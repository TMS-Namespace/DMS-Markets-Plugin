// shell.qml — runs one QML test file on the real Qt6 / Quickshell runtime, headless.
//
//   QT_QPA_PLATFORM=offscreen NO_COLOR=1 TEST_FILE=/abs/path/Thing.test.qml quickshell -p tests/QML/Helpers/Harness
//
// The test file's root is a TestSuite; every function named test_* is run. Results are printed as
// lines the runner (tests/RunAll.js) parses:  T:PASS name | T:FAIL name :: message | T:SUMMARY passed=N failed=M
import QtQuick
import Quickshell

ShellRoot {
    id: root

    property int passed: 0
    property int failed: 0

    function fail(name, message) {
        failed++
        console.warn("T:FAIL " + name + " :: " + message)
    }

    function run() {
        var file = Quickshell.env("TEST_FILE")
        var component = Qt.createComponent("file://" + file)
        if (component.status !== Component.Ready) {
            console.warn("T:LOAD-ERROR " + component.errorString())
            console.warn("T:SUMMARY passed=0 failed=1")
            Qt.quit()
            return
        }
        var suite = component.createObject(root)
        if (!suite) {
            console.warn("T:LOAD-ERROR could not create the suite")
            console.warn("T:SUMMARY passed=0 failed=1")
            Qt.quit()
            return
        }
        var names = []
        for (var key in suite)
            if ((key.indexOf("test_") === 0 || key.indexOf("async_") === 0) && typeof suite[key] === "function") names.push(key)
        names.sort()
        if (names.length === 0) fail("(no tests)", "the suite defines no test_* functions")
        root.suiteObject = suite
        root.testNames = names
        runNext(0)
    }

    property var suiteObject: null
    property var testNames: []
    property int currentIndex: -1
    property bool currentDone: false

    function finish() {
        console.warn("T:SUMMARY passed=" + passed + " failed=" + failed)
        Qt.quit()
    }

    function pass(name) { passed++; console.warn("T:PASS " + name) }

    // test_* run synchronously. async_* receive `done(errorMessage?)` and may finish later (timers,
    // processes); they time out after 15 seconds.
    function runNext(index) {
        if (index >= testNames.length) { finish(); return }
        var name = testNames[index]
        var suite = suiteObject
        try {
            if (typeof suite.setup === "function") suite.setup()
            if (name.indexOf("async_") === 0) {
                currentIndex = index
                currentDone = false
                asyncTimeout.restart()
                suite[name](function(error) { root.asyncFinished(index, error) })
                return
            }
            suite[name]()
            pass(name)
        } catch (error) {
            fail(name, (error && error.message !== undefined) ? error.message : String(error))
        }
        runNext(index + 1)
    }

    function asyncFinished(index, error) {
        if (index !== currentIndex || currentDone) return
        currentDone = true
        asyncTimeout.stop()
        var name = testNames[index]
        if (error) fail(name, String(error)); else pass(name)
        Qt.callLater(function() { root.runNext(index + 1) })
    }

    Timer {
        id: asyncTimeout
        interval: parseInt(Quickshell.env("TEST_ASYNC_TIMEOUT_MS") || "15000")
        onTriggered: root.asyncFinished(root.currentIndex, "async test timed out")
    }

    Timer { interval: 20; running: true; onTriggered: root.run() }
    Timer { interval: parseInt(Quickshell.env("TEST_TIMEOUT_MS") || "60000"); running: true; onTriggered: { console.warn("T:SUMMARY passed=0 failed=1"); console.warn("T:FAIL (timeout) :: the suite did not finish"); Qt.quit() } }
}
