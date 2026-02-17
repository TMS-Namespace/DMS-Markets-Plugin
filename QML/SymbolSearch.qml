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
    property alias  searchInput: searchField
    property var    searchResults: []
    property bool   isSearching:   false

    signal symbolSelected(string symbolId, string symbolName)

    implicitHeight: childrenRect.height

    Column {
        width: parent.width
        spacing: Theme.spacingS

        StringSetting {
            id: searchField
            settingKey: "_searchQuery"
            label: "Search Symbols"
            description: "Type to search for symbols (e.g., eur, gold, btc, apple)"
            placeholder: "Search…"
            defaultValue: ""
        }

        Item {
            width: parent.width
            height: searchBtn.height

            Rectangle {
                id: searchBtn
                width: 120
                height: 36
                radius: Theme.cornerRadius

                property bool canSearch: (searchField.value || "").trim().length >= 2
                                         && !searchPanel.isSearching

                color: canSearch
                    ? (searchBtnMouse.containsMouse ? Theme.primary : Theme.surfaceContainerHighest)
                    : Theme.surfaceContainerHigh
                border.color: canSearch ? Theme.primary : Theme.outlineVariant
                border.width: 1
                opacity: canSearch ? 1.0 : 0.5

                StyledText {
                    anchors.centerIn: parent
                    text: searchPanel.isSearching ? "Searching…" : "Search"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: searchBtn.canSearch
                        ? (searchBtnMouse.containsMouse ? Theme.surfaceContainer : Theme.primary)
                        : Theme.surfaceVariantText
                }

                MouseArea {
                    id: searchBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: searchBtn.canSearch ? Qt.PointingHandCursor : Qt.ArrowCursor
                    enabled: searchBtn.canSearch
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
                    color: srMouse.containsMouse ? Theme.primaryContainer : Theme.surfaceContainerHigh

                    MouseArea {
                        id: srMouse
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
                                    var full = (modelData.name || "") + "  ·  " + (modelData.market || "")
                                    return full.length > 40 ? full.substring(0, 40) + "…" : full
                                }
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }

                        StyledText {
                            width: 90
                            anchors.verticalCenter: parent.verticalCenter
                            text: (modelData.price || "") + "  " + (modelData.changeStr || "")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
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
        var query = (searchField.value || "").trim()
        if (query.length < 2) return
        isSearching = true
        searchResults = []

        var url = Providers.buildSearchUrl(searchPanel.providerId, query)
        if (!url) { isSearching = false; return }

        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                isSearching = false
                if (xhr.status === 200 && xhr.responseText) {
                    var results = Providers.parseSearchResponse(
                        searchPanel.providerId, xhr.responseText
                    )
                    searchResults = results
                    if (results.length === 0)
                        ToastService.showInfo("Markets", "No results for '" + query + "'")
                } else {
                    ToastService.showError("Markets", "Search failed — check connection")
                }
            }
        }
        xhr.open("GET", url)
        xhr.send()
    }
}
