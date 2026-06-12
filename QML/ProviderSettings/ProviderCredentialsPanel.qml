// ProviderCredentialsPanel.qml — hosts provider-specific credential settings.

import QtQuick
import "../Helpers"

Column {
    id: root

    required property var settingsRoot

    width: parent ? parent.width : c.providerSettingsWidth
    spacing: 0

    signal credentialChanged(string providerId, string credential)

    StooqProviderSettings {
        width: parent.width
        settingsRoot: root.settingsRoot
        onProviderCredentialChanged: function(providerId, credential) {
            root.credentialChanged(providerId, credential)
        }
    }

    YahooProviderSettings {
        width: parent.width
    }

    Constants { id: c }
}
