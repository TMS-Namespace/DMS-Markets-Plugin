// Constants.qml - QML-side constants for the Markets plugin
//
// Instantiate in each consumer with:   Constants { id: constants }
// Then reference as:                   constants.defaultUpColor
//
// Only values consumed by QML rendering live here.
// JS-only timing/fetch constants live in JS/Helpers/Constants.js.

import QtQuick

QtObject {
    readonly property real actionButtonBgOpacity: 0.85
    readonly property int actionButtonRadius: 11
    readonly property int actionButtonSize: 22
    readonly property int actionButtonSpacing: 4
    readonly property int actionCloseIconSize: 12
    readonly property int actionIconSize: 14
    readonly property int agoTickMs: 15000 // "X sec ago" refresh

    // ── Bar-pill display strings ──────────────────────────────────────────────
    readonly property string barDefaultLabel: "Markets"
    readonly property string barSeparator: "│"

    // ── Button hover / background alphas ─────────────────────────────────────
    readonly property real buttonHoverAlpha: 0.15  // hover highlight tint
    readonly property int chartAreaMargin: 5   // around the chart on every side (one constant for all four)
    readonly property real chartFillOpacity: 0.25
    readonly property int chartLabelBottomMargin: 2
    readonly property int chartLabelFontSizeDelta: -3
    readonly property int chartLabelLeftMargin: 4
    readonly property real chartLabelOpacity: 0.8
    readonly property int chartLabelTopMargin: 2
    readonly property real chartLineWidth: 1.5
    readonly property int chartLoadingAnimMs: 600

    // ── PriceChart rendering ──────────────────────────────────────────────────
    readonly property int chartPadding: 3   // inside the chart: between the drawing and its edge
    readonly property int chartStatusFontSizeDelta: -2
    readonly property int compactRowHeight: 44   // add/edit rows

    readonly property int configActionSize: 24   // clickable area for move/delete
    readonly property int configArrowIconSize: 16
    readonly property int configButtonSpacing: 2
    readonly property int configDefaultWidth: 200
    readonly property int configIconSize: 18   // pin icon + delete icon

    // ── ConfiguredSymbol / settings list rows ─────────────────────────────────
    readonly property int configRowHeight: 56
    readonly property int configTextFontSizeDelta: -1   // the one-line summary of a configured symbol, a little below "small"
    readonly property int defaultBarIconSize: 16

    // ── Default chart colors ──────────────────────────────────────────────────
    readonly property color defaultDownColor: "#F44336"
    readonly property int defaultPopoutRows: 5
    readonly property color defaultUpColor: "#4CAF50"

    // ── Developer / debug mode ────────────────────────────────────────────────
    readonly property bool isDevMode: true   // enable for verbose plugin diagnostics

    readonly property int emptyStateIconSize: 48
    readonly property int errorTooltipMaxWidth: 360
    readonly property int fullRotationDeg: 360
    readonly property int headerAnimDurationMs: 800
    readonly property int headerButtonRadius: 14
    readonly property int headerButtonSize: 28

    // ── PopoutPanel internal UI ───────────────────────────────────────────────
    readonly property int headerButtonSpacing: 6
    readonly property int headerButtonZ: 101
    readonly property int headerHoverZ: 100
    readonly property int headerIconSize: 18
    readonly property int maxPopoutRows: 50
    readonly property int minPopoutRows: 1
    readonly property int overlayZ: 10
    readonly property string pluginSubtitle: "Track live prices for currencies, stocks, commodities, and crypto."

    // ── Popout / widget layout ────────────────────────────────────────────────
    readonly property int popoutWidth: 420
    readonly property int refreshWarningBadgeSize: 14
    readonly property int scrollAnimDurationMs: 200
    readonly property int scrollBarRadius: 4
    readonly property int scrollBarWidth: 4
    readonly property real scrollOpacityActive: 0.8
    readonly property real scrollOpacityIdle: 0.4
    readonly property int scrollThumbMin: 20

    // ── Shared small buttons / compact rows ───────────────────────────────────
    readonly property int smallButtonWidth: 80   // cancel buttons
    readonly property int smallFontSizeDelta: -2
    readonly property int symbolColSpacing: 2
    readonly property int symbolNameColumnW: 90
    // DMS defaults: medium 14px, small 12px. Deltas preserve compact labels.
    readonly property int symbolNameFontSizeDelta: 1
    readonly property int symbolPriceColumnShift: 5   // the price column sits this many px further right
    readonly property int symbolPriceColumnW: 86

    // ── SymbolRow UI ─────────────────────────────────────────────────────────
    readonly property int symbolRowHeight: 76
    readonly property int symbolSearchButtonPadding: 14
    readonly property int symbolSearchButtonWidth: 290
    // The ticker line is smaller than the name but stays bigger than the "refreshed ago" line (smallFontSizeDelta): one step above it.
    readonly property int symbolTickerFontSizeDelta: smallFontSizeDelta + 1
    readonly property int unpinnedRotationDeg: 45

    // ── Provider credentials / settings ──────────────────────────────────────
}
