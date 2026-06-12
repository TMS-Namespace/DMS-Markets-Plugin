// StooqProviderSettings.qml — Stooq-specific credential settings.

import QtQuick
import qs.Common
import qs.Widgets
import "../Helpers"
import "../../JS/Helpers.js" as Helpers
import "../../JS/ProviderInterface.js" as Providers
import "../../JS/Constants.js" as JsK

Column {
    id: root

    required property var settingsRoot

    width: parent ? parent.width : c.providerSettingsWidth
    spacing: Theme.spacingS

    readonly property var meta: Providers.getProviderMeta(JsK.STOOQ_PROVIDER_ID)
    property string credential: ""
    property bool credentialFormatInvalid: credential.trim().length > 0
                                           && !Providers.isValidCredential(JsK.STOOQ_PROVIDER_ID, credential)

    signal providerCredentialChanged(string providerId, string credential)

    Component.onCompleted: Qt.callLater(loadCredential)

    function loadCredential() {
        if (!meta.credentialSettingKey)
            return
        var stored = settingsRoot.loadValue(meta.credentialSettingKey, "")
        credential = Helpers.deobfuscate(stored)
        Providers.setCredential(JsK.STOOQ_PROVIDER_ID, credential)
        if (credentialField.text !== credential) {
            credentialField._initializing = true
            credentialField.text = credential
            credentialField._initializing = false
        }
        providerCredentialChanged(JsK.STOOQ_PROVIDER_ID, credential)
    }

    function saveCredential(value) {
        if (!meta.credentialSettingKey)
            return
        var newCredential = (value || "").trim()
        if (newCredential !== "" && !Providers.isValidCredential(JsK.STOOQ_PROVIDER_ID, newCredential))
            return
        settingsRoot.saveValue(meta.credentialSettingKey, Helpers.obfuscate(newCredential))
        credential = newCredential
        Providers.setCredential(JsK.STOOQ_PROVIDER_ID, newCredential)
        providerCredentialChanged(JsK.STOOQ_PROVIDER_ID, newCredential)
    }

    StyledText {
        width: parent.width
        text: meta.credentialLabel
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingM
    }

    StyledText {
        width: parent.width
        text: meta.providerSettingsText || ("Required only for symbols that use the " + meta.name + " provider.")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    Item {
        width: parent.width
        height: c.compactRowHeight

        Timer {
            id: saveTimer
            interval: c.credentialSaveDebounceMs
            repeat: false
            onTriggered: root.saveCredential(credentialField.text)
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.cornerRadius
            color: Theme.surfaceContainer
            border.color: credentialField.activeFocus
                          ? Theme.primary
                          : (root.credentialFormatInvalid ? Theme.error : Theme.outlineVariant)
            border.width: credentialField.activeFocus ? 2 : 1

            TextInput {
                id: credentialField
                anchors {
                    left: parent.left
                    right: revealBtn.left
                    top: parent.top
                    bottom: parent.bottom
                    leftMargin: Theme.spacingS
                    rightMargin: Theme.spacingXS
                }
                verticalAlignment: TextInput.AlignVCenter
                echoMode: revealBtn.revealed ? TextInput.Normal : TextInput.Password
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
                clip: true
                selectByMouse: true

                property bool _initializing: false
                onTextChanged: {
                    root.credential = text
                    if (!_initializing) saveTimer.restart()
                }

                Text {
                    anchors.fill: parent
                    text: meta.credentialPlaceholder
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeMedium
                    verticalAlignment: Text.AlignVCenter
                    visible: credentialField.text.length === 0
                }
            }

            Rectangle {
                id: revealBtn
                property bool revealed: false
                width: c.compactRowHeight
                height: c.compactRowHeight
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                color: "transparent"

                DankIcon {
                    name: revealBtn.revealed ? "visibility_off" : "visibility"
                    size: Theme.fontSizeMedium
                    color: revealMouse.containsMouse ? Theme.primary : Theme.surfaceVariantText
                    anchors.centerIn: parent
                }

                MouseArea {
                    id: revealMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: revealBtn.revealed = !revealBtn.revealed
                }
            }
        }
    }

    Text {
        width: parent.width
        visible: root.credentialFormatInvalid
        text: "Invalid key: expected " + meta.credentialMinLength + "-"
              + meta.credentialMaxLength + " characters"
        font.pixelSize: Theme.fontSizeSmall
        color: c.validationErrorColor
        wrapMode: Text.WordWrap
    }

    Column {
        width: parent.width
        spacing: 0

        Item {
            id: helpHeader
            width: parent.width
            height: c.compactRowHeight
            property bool expanded: false

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                DankIcon {
                    name: helpHeader.expanded ? "expand_less" : "expand_more"
                    size: Theme.fontSizeSmall
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: meta.credentialHelpTitle
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: helpHeader.expanded = !helpHeader.expanded
            }
        }

        StyledText {
            width: parent.width
            visible: helpHeader.expanded
            text: meta.credentialHelpText
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }
    }

    Constants { id: c }
}
