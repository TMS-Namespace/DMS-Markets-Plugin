import QtQml
import "../../../Helpers"

TestSuite {
    function test_assertions_work() {
        check(true)
        equal({ a: [1, 2] }, { a: [1, 2] })
        same(3, 3)
        near(0.1 + 0.2, 0.3, 1e-9)
        throws(function() { throw new Error("boom here") }, "boom")
        doesNotThrow(function() {})
    }
    function test_failures_are_reported() {
        var thrown = throws(function() { check(false, "nope") }, "nope")
        check(thrown instanceof Error)
        throws(function() { equal(1, 2) }, "values differ")
        throws(function() { same(1, "1") }, "not identical")
        throws(function() { throws(function() {}) }, "nothing was thrown")
    }
}
