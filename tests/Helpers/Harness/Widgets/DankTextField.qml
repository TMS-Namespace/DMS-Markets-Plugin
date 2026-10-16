import QtQuick
Item { property alias text: field.text; property string placeholderText: ""; signal editingFinished(); TextInput { id: field; onEditingFinished: parent.editingFinished() } implicitHeight: 32 }
