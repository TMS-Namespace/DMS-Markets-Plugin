import QtQuick

Item {
    property alias maximumLength: field.maximumLength
    property string placeholderText: ""
    property alias text: field.text

    signal editingFinished

    implicitHeight: 32

    TextInput {
        id: field

        onEditingFinished: parent.editingFinished()
    }
}
