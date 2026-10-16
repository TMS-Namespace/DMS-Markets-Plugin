import QtQuick
import "../../../Helpers"

TestSuite {
    id: suite
    property Timer delayTimer: Timer { id: timer; interval: 30; onTriggered: suite.fired = true }
    property bool fired: false

    function async_waits_for_a_timer(done) {
        fired = false
        timer.triggered.connect(function() { done(fired ? "" : "did not fire") })
        timer.start()
    }
    function test_sync_still_works() { check(true) }
}
