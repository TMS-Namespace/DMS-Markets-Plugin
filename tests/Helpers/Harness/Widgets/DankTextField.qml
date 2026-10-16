import QtQuick
Item { property alias text: field.text; property alias maximumLength: field.maximumLength; property string placeholderText: ""; signal editingFinished(); TextInput { id: field; onEditingFinished: parent.editingFinished() } implicitHeight: 32 }
