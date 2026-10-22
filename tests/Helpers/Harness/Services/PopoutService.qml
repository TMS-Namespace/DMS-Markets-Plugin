// Record settings navigation through the same API that handles Dux's lazy settings window.
pragma Singleton
import QtQuick

QtObject {
    property string requestedPage: ""

    // Record the page requested by a widget; real Dux opens its settings window at that page.
    function openSettingsWithTab(tabName, returnOrigin, reopen) {
        requestedPage = tabName;
    }
}
