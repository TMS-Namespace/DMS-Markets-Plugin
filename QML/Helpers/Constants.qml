// Constants.qml — QML-side constants for the Markets plugin
//
// Instantiate in each consumer with:   Constants { id: c }
// Then reference as:                   c.defaultUpColor
//
// Only values consumed by QML rendering live here.
// JS-only timing/fetch constants live in JS/Constants.js.

import QtQuick

QtObject {

    // ── Developer / debug mode ────────────────────────────────────────────────
    readonly property bool devMode: false   // set false to silence all plugin logs

    // ── Default chart colors ──────────────────────────────────────────────────
    readonly property color defaultUpColor:   "#4CAF50"
    readonly property color defaultDownColor: "#F44336"

    // ── Bar-pill display strings ──────────────────────────────────────────────
    readonly property string barDefaultLabel: "Markets"
    readonly property string barSeparator:    "  │  "

    // ── Popout / widget layout ────────────────────────────────────────────────
    readonly property int popoutWidth:      440
    readonly property int popoutMinHeight:  200
    readonly property int popoutPadding:    80   // px added beyond rows × rowHeight
    readonly property int rowHeight:        78   // px per symbol row
    readonly property int defaultPopoutRows: 5

    // ── PopoutPanel internal UI ───────────────────────────────────────────────
    readonly property int    headerButtonSpacing:  6
    readonly property int    headerButtonSize:     28
    readonly property int    headerButtonRadius:   14
    readonly property int    headerIconSize:       18
    readonly property int    headerAnimDurationMs: 800
    readonly property int    scrollBarWidth:       4
    readonly property int    scrollBarRadius:      2
    readonly property int    scrollThumbMin:       20
    readonly property real   scrollOpacityActive:  0.8
    readonly property real   scrollOpacityIdle:    0.4
    readonly property int    scrollAnimDurationMs: 200
    readonly property int    emptyStateIconSize:   48

    // ── SymbolRow UI ─────────────────────────────────────────────────────────
    readonly property int    symbolRowHeight:      76
    readonly property int    symbolNameColumnW:    90
    readonly property int    symbolPriceColumnW:   86
    readonly property int    symbolColSpacing:     2
    readonly property int    actionButtonSize:     22
    readonly property int    actionButtonRadius:   11
    readonly property int    actionIconSize:       14
    readonly property int    actionCloseIconSize:  12
    readonly property int    actionButtonSpacing:  4
    readonly property real   actionButtonBgOpacity: 0.85
    readonly property int    smallFontSize:        10   // px for change/delta text
    readonly property int    agoTickMs:            15000 // "X sec ago" refresh

    // ── PriceChart rendering ──────────────────────────────────────────────────
    readonly property int    chartPadding:         2
    readonly property real   chartLineWidth:       1.5
    readonly property real   chartFillOpacity:     0.25
    readonly property int    chartLabelLeftMargin: 4
    readonly property int    chartLabelTopMargin:  2
    readonly property int    chartLabelFontSize:   9
    readonly property real   chartLabelOpacity:    0.8
    readonly property color  chartLabelColor:      "#888888"
    readonly property int    chartStatusFontSize:  10
    readonly property int    chartLoadingAnimMs:   600

    // ── ConfiguredSymbol / settings list rows ─────────────────────────────────
    readonly property int    configRowHeight:       56
    readonly property int    configIconSize:        18   // pin icon + delete icon
    readonly property int    configActionSize:      24   // clickable area for move/delete
    readonly property int    configArrowIconSize:   16
    readonly property int    configButtonSpacing:   2

    // ── Shared small buttons / compact rows ───────────────────────────────────
    readonly property int    smallButtonWidth:      80   // search, cancel buttons
    readonly property int    compactRowHeight:      44   // search results, add/edit row
    readonly property int    searchPriceColumnW:    90
    readonly property int    searchDescMaxLen:      40   // chars before truncation

    // ── Slider (settings popout-row slider) ───────────────────────────────────
    readonly property int    sliderContainerHeight: 48
    readonly property int    sliderAreaHeight:      24
    readonly property int    sliderTrackHeight:     4
    readonly property int    sliderHandleSize:      18

    // ── Button hover / background alphas ─────────────────────────────────────
    readonly property real   buttonHoverAlpha:      0.15  // hover highlight tint
}
