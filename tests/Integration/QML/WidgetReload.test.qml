// WidgetReload.test.qml - Dux reloads revisioned entry URLs while Qt retains the previously imported view module.
import QtQuick
import "../../Helpers"

TestSuite {
    id: suite

    property var previousComponent: null
    property var widget: null

    // Reproduce a long-running shell whose module inventory predates the failed CompactPopout addition.
    function async_widget_loads_with_the_previous_view_inventory_cached(done) {
        let directory = freshDirectory("widget-reload");
        let baseline = 'import QtQuick\nimport "./Views"\nItem { PopoutPanel { width: 400; height: 100 } }\n';
        shell('mkdir -p -- "$2" && cp -R -- "$1/src/." "$2/" && cp -- "$2/QML/Widget.qml" "$2/saved-entry" && printf %s "$3" > "$2/QML/Widget.qml" && sed "/^CompactPopout[[:space:]]/d" "$2/QML/Views/qmldir" > "$2/previous-qmldir" && cp -- "$2/previous-qmldir" "$2/QML/Views/qmldir"', [repoRoot, directory, baseline], function (code, output) {
            try {
                suite.same(code, 0, output);
                suite.previousComponent = Qt.createComponent("file://" + directory + "/QML/Widget.qml?revision=1");
                suite.check(suite.previousComponent.status === Component.Ready, suite.previousComponent.errorString());
                let previous = suite.previousComponent.createObject(null);
                suite.check(previous !== null);
                previous.destroy();
            } catch (error) {
                done(error.message);
                return;
            }
            // Restore the current entry and inventory on disk; the engine still holds the earlier module metadata.
            suite.shell('cp -- "$2/saved-entry" "$2/QML/Widget.qml" && cp -- "$1/src/QML/Views/qmldir" "$2/QML/Views/qmldir"', [suite.repoRoot, directory], function (restoreCode, restoreOutput) {
                try {
                    suite.same(restoreCode, 0, restoreOutput);
                    let current = Qt.createComponent("file://" + directory + "/QML/Widget.qml?revision=2");
                    suite.check(current.status === Component.Ready, current.errorString());
                    suite.widget = current.createObject(null, {
                        cacheDirectory: suite.freshDirectory("reloaded-market-cache")
                    });
                    suite.check(suite.widget !== null, current.errorString());
                    let popup = suite.widget.popoutContent.createObject(suite.widget);
                    suite.check(popup !== null, "the reloaded popup content also loads");
                    popup.destroy();
                    done("");
                } catch (error) {
                    done(error.message);
                }
            });
        });
    }

    // Release both revisions after the case; the runner owns the isolated temporary cache directory.
    function teardown() {
        if (widget)
            widget.destroy();
        widget = null;
        previousComponent = null;
    }
}
