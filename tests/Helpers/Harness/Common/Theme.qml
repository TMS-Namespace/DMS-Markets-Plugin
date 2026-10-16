// Stand-in for DMS's Theme (only what the plugin reads).
pragma Singleton
import QtQuick
QtObject {
    readonly property color primary: "#6750a4"
    readonly property color primaryContainer: "#eaddff"
    readonly property color surfaceText: "#1c1b1f"
    readonly property color surfaceVariantText: "#49454f"
    readonly property color surfaceContainer: "#f3edf7"
    readonly property color surfaceContainerHigh: "#ece6f0"
    readonly property color surfaceContainerHighest: "#e6e0e9"
    readonly property color nestedSurface: "#f7f2fa"
    readonly property color outlineVariant: "#cac4d0"
    readonly property color outlineMedium: "#79747e"
    readonly property color error: "#b3261e"
    readonly property color warning: "#e8a200"
    readonly property real cornerRadius: 12
    readonly property int spacingXS: 4
    readonly property real popupTransparency: 1.0
    function withAlpha(color, alpha) { return Qt.rgba(color.r, color.g, color.b, alpha) }
    readonly property int spacingS: 8
    readonly property int spacingM: 12
    readonly property int spacingXL: 24
    readonly property int fontSizeSmall: 12
    readonly property int fontSizeMedium: 14
    readonly property int fontSizeLarge: 16
}
