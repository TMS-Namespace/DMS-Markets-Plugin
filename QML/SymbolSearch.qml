// SymbolSearch.qml — Provider-agnostic symbol search panel
//
// Provides a search input and results list. When a result is clicked,
// the symbolSelected signal fires with the symbol ID and display name.
// Search URL building and response parsing are delegated to the provider.

import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Plugins
import qs.Widgets
import "../JS/ProviderInterface.js" as Providers

Item {
    id: searchPanel

    property string providerId:  ""
    property var    searchResults: []
    property bool   isSearching:   false

    signal symbolSelected(string symbolId, string symbolName)

    implicitHeight: childrenRect.height

    Column {
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
                onAccepted: if (searchButton.canSearch) searchPanel.doSearch()
            }

            Rectangle {
                id: searchButton
                width: 80
                height: searchTextField.height
                radius: Theme.cornerRadius

                property bool canSearch: searchTextField.text.trim().length >= 2
                                         && !searchPanel.isSearching

                color: canSearch
                    ? (searchButtonMouseArea.containsMouse ? Theme.primary : Theme.surfaceContainerHighest)
                    : Theme.surfaceContainerHigh
                border.color: canSearch ? Theme.primary : Theme.outlineVariant
                border.width: 1
                opacity: canSearch ? 1.0 : 0.5

                StyledText {
                    anchors.centerIn: parent
                    text: searchPanel.isSearching ? "Searching…" : "Search"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: searchButton.canSearch
                        ? (searchButtonMouseArea.containsMouse ? Theme.surfaceContainer : Theme.primary)
                        : Theme.surfaceVariantText
                }

                MouseArea {
                    id: searchButtonMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: searchButton.canSearch ? Qt.PointingHandCursor : Qt.ArrowCursor
                    enabled: searchButton.canSearch
                    onClicked: searchPanel.doSearch()
                }
            }
        }

        // Search results
        Repeater {
            model: searchPanel.searchResults

            delegate: Item {
                width: searchPanel.width
                height: 44
                clip: true

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.cornerRadius
                    color: searchResultMouseArea.containsMouse ? Theme.primaryContainer : Theme.surfaceContainerHigh

                    MouseArea {
                        id: searchResultMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            searchPanel.symbolSelected(modelData.id, modelData.name)
                            searchPanel.searchResults = []
                        }
                    }

                    Row {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingS
                        spacing: Theme.spacingS

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 90 - Theme.spacingS

                            StyledText {
                                text: modelData.id || ""
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                                elide: Text.ElideRight
                                width: parent.width
                            }

                            StyledText {
                                text: {
                                    var fullDescription = (modelData.name || "") + "  ·  " + (modelData.market || "")
                                    return fullDescription.length > 40 ? fullDescription.substring(0, 40) + "…" : fullDescription
                                }
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }

                        Column {
                            width: 90
                            anchors.verticalCenter: parent.verticalCenter

                            StyledText {
                                width: parent.width
                                text: {
                                    var raw = modelData.price || ""
                                    var num = parseFloat(raw)
                                    return isNaN(num) ? raw : num.toFixed(2)
                                }
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideRight
                            }

                            StyledText {
                                width: parent.width
                                text: {
                                    var raw = modelData.changeStr || ""
                                    var num = parseFloat(raw)
                                    return isNaN(num) ? raw : num.toFixed(2) + "%"
                                }
                                font.pixelSize: Theme.fontSizeSmall
                                color: {
                                    var num = parseFloat(modelData.changeStr || "0")
                                    return num > 0 ? "#4CAF50" : num < 0 ? "#F44336" : Theme.surfaceVariantText
                                }
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideRight
                                visible: (modelData.changeStr || "").length > 0
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            visible: searchPanel.searchResults.length > 0
            width: parent.width
            height: 1
            color: Theme.outlineVariant
        }
    }

    function doSearch() {
        var query = searchTextField.text.trim()
        if (query.length < 2) return
        isSearching = true
        searchResults = []

        var url = Providers.buildSearchUrl(searchPanel.providerId, query)
        if (!url) { isSearching = false; return }

        var httpRequest = new XMLHttpRequest()
        httpRequest.onreadystatechange = function() {
            if (httpRequest.readyState === XMLHttpRequest.DONE) {
                isSearching = false
                if (httpRequest.status === 200 && httpRequest.responseText) {
                    var results = Providers.parseSearchResponse(
                        searchPanel.providerId, httpRequest.responseText
                    )
                    searchResults = results
                    if (results.length === 0)
                        ToastService.showInfo("Markets", "No results for '" + query + "'")
                } else {
                    ToastService.showError("Markets", "Search failed — check connection")
                }
            }
        }
        httpRequest.open("GET", url)
        httpRequest.setRequestHeader("Cookie", "")
        httpRequest.send()
    }
}
