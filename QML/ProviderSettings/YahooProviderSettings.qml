// YahooProviderSettings.qml — Yahoo Finance provider settings.

import QtQuick
import qs.Common
import qs.Widgets
import "../Helpers"
import "../../JS/ProviderInterface.js" as Providers
import "../../JS/Constants.js" as JsK

Column {
    id: root

    width: parent ? parent.width : c.providerSettingsWidth
    spacing: Theme.spacingS

    readonly property var meta: Providers.getProviderMeta(JsK.YAHOO_PROVIDER_ID)

    StyledText {
        width: parent.width
        text: meta.name
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingM
    }

    StyledText {
        width: parent.width
        text: meta.providerSettingsText
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    Constants { id: c }
}
