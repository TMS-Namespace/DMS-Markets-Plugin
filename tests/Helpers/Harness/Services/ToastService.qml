// Stand-in for DMS's ToastService: records what it was asked to show.
pragma Singleton
import QtQuick

QtObject {
    property var errors: []
    property var infos: []

    function showError(title, message, command, category) {
        errors = errors.concat([
            {
                title: title,
                message: message,
                category: category
            }
        ]);
    }
    function showInfo(title, message) {
        infos = infos.concat([
            {
                title: title,
                message: message
            }
        ]);
    }
}
