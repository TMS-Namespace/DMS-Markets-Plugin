// SymbolSearch.qml — Provider-agnostic symbol search panel (view)
//
// Renders the search input, button, and results list.
// All network/XHR logic lives in QML/Helpers/SymbolSearcher.qml.
// Settings.qml instantiates this component and reacts to symbolSelected.

import QtQuick
import qs.Common
import qs.Widgets
import "../Helpers"

Item {
    id: searchPanel

    Constants { id: c }

    // ── Public API ────────────────────────────────────────────────────────────
    property string providerId: ""

    signal symbolSelected(string symbolId, string symbolName)

    implicitHeight: contentCol.height

    // ── Logic helper ──────────────────────────────────────────────────────────
    SymbolSearcher {
        id: searcher
        providerId: searchPanel.providerId
        onSymbolSelected: function(id, name) { searchPanel.symbolSelected(id, name) }
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    Column {
        id: contentCol
        width: parent.width
        spacing: Theme.spacingS

        StyledText {
            text: "Search Symbols"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        StyledText {
            text: "Type to search for symbols (e.g., eur, gold, btc, apple)"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            width: parent.width
            wrapMode: Text.WordWrap
        }

        // ── Search input row ─────────────────────────────────────────────
        Row {
            width: parent.width
            spacing: Theme.spacingS

            DankTextField {
                id: searchTextField
                width: parent.width - searchButton.width - Theme.spacingS
                leftIconName: "search"
                placeholderText: "Search…"
                backgroundColor: Theme.surfaceVariant
                normalBorderColor: Theme.primarySelected
                focusedBorderColor: Theme.primary
                onAccepted: if (searchButton.canSearch) searcher.search(searchTextField.text.trim())
            }

            Rectangle {
                id: searchButton
                width: c.smallButtonWidth
                height: searchTextField.height
                radius: Theme.cornerRadius

                property bool canSearch: searchTextField.text.trim().length >= 2
                                         && !searcher.isSearching

                color:         canSearch
                               ? (searchButtonMouseArea.containsMouse ? Theme.primary : Theme.surfaceContainerHighest)
                               : Theme.surfaceContainerHigh
                border.color:  canSearch ? Theme.primary : Theme.outlineVariant
                border.width:  1
                opacity:       canSearch ? 1.0 : 0.5

                StyledText {
                    anchors.centerIn: parent
                    text:           searcher.isSearching ? "Searching…" : "Search"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight:    Font.Medium
                    color: searchButton.canSearch
                           ? (searchButtonMouseArea.containsMouse ? Theme.surfaceContainer : Theme.primary)
                           : Theme.surfaceVariantText
                }

                MouseArea {
                    id: searchButtonMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape:  searchButton.canSearch ? Qt.PointingHandCursor : Qt.ArrowCursor
                    enabled:      searchButton.canSearch
                    onClicked:    searcher.search(searchTextField.text.trim())
                }
            }
        }

        // ── Results list ─────────────────────────────────────────────────
        Repeater {
            model: searcher.results

            delegate: Item {
                width:  searchPanel.width
                height: c.compactRowHeight
                clip:   true

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.cornerRadius
                    color:  searchResultMouseArea.containsMouse
                            ? Theme.primaryContainer
                            : Theme.surfaceContainerHigh

                    MouseArea {
                        id: searchResultMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape:  Qt.PointingHandCursor
                        onClicked: {
                            searchPanel.symbolSelected(modelData.id, modelData.name)
                            searcher.results = []
                        }
                    }

                    Row {
                        anchors.fill:    parent
                        anchors.margins: Theme.spacingS
                        spacing:         Theme.spacingS

                        // Name + description
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - c.searchPriceColumnW - Theme.spacingS

                            StyledText {
                                text:           modelData.id || ""
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight:    Font.Medium
                                color:          Theme.surfaceText
                                elide:          Text.ElideRight
                                width:          parent.width
                            }

                            StyledText {
                                text: {
                                    var desc = (modelData.name || "") + "  ·  " + (modelData.market || "")
                                    return desc.length > c.searchDescMaxLen
                                           ? desc.substring(0, c.searchDescMaxLen) + "…"
                                           : desc
                                }
                                font.pixelSize: Theme.fontSizeSmall
                                color:          Theme.surfaceVariantText
                                elide:          Text.ElideRight
                                width:          parent.width
                            }
                        }

                        // Price + change
                        Column {
                            width: c.searchPriceColumnW
                            anchors.verticalCenter: parent.verticalCenter

                            StyledText {
                                width: parent.width
                                text: {
                                    var num = parseFloat(modelData.price || "")
                                    return isNaN(num) ? (modelData.price || "") : num.toFixed(2)
                                }
                                font.pixelSize:     Theme.fontSizeSmall
                                color:              Theme.surfaceVariantText
                                horizontalAlignment: Text.AlignRight
                                elide:              Text.ElideRight
                            }

                            StyledText {
                                width:   parent.width
                                visible: (modelData.changeStr || "").length > 0
                                text: {
                                    var num = parseFloat(modelData.changeStr || "")
                                    return isNaN(num) ? (modelData.changeStr || "") : num.toFixed(2) + "%"
                                }
                                font.pixelSize: Theme.fontSizeSmall
                                color: {
                                    var num = parseFloat(modelData.changeStr || "0")
                                    return num > 0 ? c.defaultUpColor
                                         : num < 0 ? c.defaultDownColor
                                         : Theme.surfaceVariantText
                                }
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            visible: searcher.results.length > 0
            width:   parent.width
            height:  1
            color:   Theme.outlineVariant
        }
    }
}
