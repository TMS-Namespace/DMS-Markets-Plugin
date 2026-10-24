// The host's outer popup padding; the compact wrapper compensates this without modifying the global theme.
pragma Singleton
import QtQuick

QtObject {
    readonly property real contentPadding: Theme.spacingL
}
