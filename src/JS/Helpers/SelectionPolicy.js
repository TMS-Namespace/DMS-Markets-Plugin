// SelectionPolicy.js - logic: which price/chart choices does a provider allow, and what is the
// closest allowed choice to what someone asked for?
//
// Everything here is a pure function of a provider's declared limits (a ProviderProperties:
// priceResolutions, chartLimits, minPullResolution) and of plain values. It only ever sees values in
// the CURRENT format; data saved by older versions is upgraded first (SymbolMigration.js). Results
// are plain { priceResolution, chartResolution, chartRange } objects.
//
// Chart ranges are never listed by a provider: they are every ChartSpan within the provider's
// history limit for a resolution (`chartSpans`), further narrowed to those that give a readable
// number of candles (`allowedChartSpans`, see ChartRules.js).

.pragma library
.import "Constants.js" as Constants
.import "../Contracts/PluginError.js" as PluginError
.import "../Contracts/Resolution.js" as Resolution
.import "../Contracts/ChartSpan.js" as ChartSpan
.import "ChartRules.js" as ChartRules
// Copy the provider chart limits into a plain JavaScript array.
function _limits(properties) {
    let declared = properties.chartLimits,
        limits = [];
    for (let i = 0; i < declared.length; i++) limits.push(declared[i]);
    return limits;
}

// Order supported choices using the shared value-domain order.
function _sorted(values, order) {
    return values.slice().sort(function (earlier, later) {
        return order.indexOf(earlier) - order.indexOf(later);
    });
}

// Choose the supported value closest to the requested position.
function _nearest(candidates, wanted, order) {
    if (candidates.length === 0) return "";
    if (candidates.indexOf(wanted) !== -1) return wanted;
    let target = order.indexOf(wanted);
    let best = candidates[0],
        bestDistance = Infinity;
    for (let i = 0; i < candidates.length; i++) {
        let distance = Math.abs(order.indexOf(candidates[i]) - target);
        if (distance < bestDistance) {
            best = candidates[i];
            bestDistance = distance;
        }
    }
    return best;
}

// ── What is declared ─────────────────────────────────────────────────────────

// List the supported price resolutions, finest first.
function priceResolutions(properties) {
    return _sorted(Array.prototype.slice.call(properties.priceResolutions), Resolution.ORDER);
}

// Chart resolutions the provider can serve, finest first.
function chartResolutions(properties) {
    return _sorted(
        _limits(properties).map(function (limit) {
            return limit.resolution;
        }),
        Resolution.ORDER
    );
}

// Longest history (days) the provider serves for a chart resolution; 0 means no limit.
function historyLimitDays(properties, resolution) {
    let limits = _limits(properties);
    for (let i = 0; i < limits.length; i++)
        if (limits[i].resolution === resolution) return Number(limits[i].maxHistoryDays) || 0;
    return 0;
}

// Spans within the provider's history limit for `resolution`; [] for an unsupported resolution.
function chartSpans(properties, resolution) {
    if (chartResolutions(properties).indexOf(resolution) === -1) return [];
    let limit = historyLimitDays(properties, resolution);
    return ChartSpan.ORDER.filter(function (span) {
        return limit <= 0 || ChartSpan.days(span) <= limit;
    });
}

// What the settings offer: those spans minus the ones ChartRules blocks (too few / too many candles).
function allowedChartSpans(properties, resolution) {
    return chartSpans(properties, resolution).filter(function (span) {
        return ChartRules.isAllowed(resolution, span);
    });
}

// Chart resolutions that have at least one allowed span.
function allowedChartResolutions(properties) {
    return chartResolutions(properties).filter(function (resolution) {
        return allowedChartSpans(properties, resolution).length > 0;
    });
}

// Resolutions the provider can measure the change against (the close of the previous period of that size), coarsest last.
function changeResolutions(properties) {
    return _sorted(Array.prototype.slice.call(properties.changeResolutions), Resolution.ORDER);
}

// How often the change reference is pulled: as often as its resolution, but never less often than hourly (the reference
// of a day or a week rolls over during the day).
function changeRefreshMs(resolution) {
    return Math.min(Resolution.ms(resolution), Resolution.ms(Resolution.Values.H1));
}

// Check whether the provider declares this price resolution.
function supportsPrice(properties, resolution) {
    return priceResolutions(properties).indexOf(resolution) !== -1;
}
// Check whether the provider declares this change resolution.
function supportsChange(properties, resolution) {
    return changeResolutions(properties).indexOf(resolution) !== -1;
}
// Check whether both chart choices fit the provider history limits.
function supportsChart(properties, resolution, span) {
    return chartSpans(properties, resolution).indexOf(span) !== -1;
}

// ── Guards (throw on unsupported requests) ───────────────────────────────────

// Reject price resolutions the provider does not declare.
function assertPrice(properties, resolution) {
    if (!supportsPrice(properties, resolution))
        throw new PluginError.PluginError(
            PluginError.Code.UNSUPPORTED,
            properties.name + " doesn't offer a " + Resolution.label(resolution) + " price resolution.",
            properties.name +
                " does not support price resolution '" +
                resolution +
                "'. Supported: " +
                priceResolutions(properties).join(", ")
        );
}

// Reject unsupported change resolutions or excessive polling.
function assertChange(properties, resolution) {
    if (!supportsChange(properties, resolution))
        throw new PluginError.PluginError(
            PluginError.Code.UNSUPPORTED,
            properties.name + " can't measure the change over " + Resolution.label(resolution) + ".",
            properties.name +
                " does not support change resolution '" +
                resolution +
                "'. Supported: " +
                changeResolutions(properties).join(", ")
        );
    if (changeRefreshMs(resolution) < Resolution.ms(properties.minPullResolution))
        throw new PluginError.PluginError(
            PluginError.Code.POLL_TOO_FAST,
            properties.name +
                " can only be refreshed every " +
                Resolution.label(properties.minPullResolution) +
                " or slower.",
            properties.name + " cannot be polled every " + changeRefreshMs(resolution) + " ms for the change"
        );
}

// Reject chart resolutions and spans outside the declared limits.
function assertChart(properties, resolution, span) {
    let spans = chartSpans(properties, resolution);
    if (spans.length === 0)
        throw new PluginError.PluginError(
            PluginError.Code.UNSUPPORTED,
            properties.name + " doesn't offer " + Resolution.label(resolution) + " chart candles.",
            properties.name +
                " does not support chart resolution '" +
                resolution +
                "'. Supported: " +
                chartResolutions(properties).join(", ")
        );
    if (!supportsChart(properties, resolution, span))
        throw new PluginError.PluginError(
            PluginError.Code.UNSUPPORTED,
            properties.name +
                " can't show a " +
                ChartSpan.label(span) +
                " chart with " +
                Resolution.label(resolution) +
                " candles.",
            properties.name +
                " does not support a '" +
                span +
                "' chart range at '" +
                resolution +
                "' resolution. Supported: " +
                spans.join(", ")
        );
}

// Data is pulled as often as its resolution: a 1m candle is re-fetched every minute. Throws when that
// is faster than the provider allows.
function assertPull(properties, resolution) {
    if (Resolution.ms(resolution) < Resolution.ms(properties.minPullResolution))
        throw new PluginError.PluginError(
            PluginError.Code.POLL_TOO_FAST,
            properties.name +
                " can only be refreshed every " +
                Resolution.label(properties.minPullResolution) +
                " or slower.",
            properties.name +
                " cannot be polled every " +
                Resolution.label(resolution) +
                "; the minimum is " +
                Resolution.label(properties.minPullResolution)
        );
}

// ── Defaults ─────────────────────────────────────────────────────────────────

// First resolution at or above one hour, else the coarsest available.
function _atLeastAnHour(candidates) {
    let sorted = _sorted(candidates, Resolution.ORDER);
    let minimumMs = Resolution.ms(Resolution.Values.H1);
    for (let i = 0; i < sorted.length; i++) if (Resolution.ms(sorted[i]) >= minimumMs) return sorted[i];
    return sorted[sorted.length - 1];
}

// Choose the default price resolution from the provider capabilities.
function defaultPriceResolution(properties) {
    return _atLeastAnHour(priceResolutions(properties));
}

// Choose the supported change resolution closest to the shared default.
function defaultChangeResolution(properties) {
    return _nearest(changeResolutions(properties), Constants.DEFAULT_CHANGE_RESOLUTION, Resolution.ORDER);
}

// Choose a supported chart resolution with a readable range.
function defaultChartResolution(properties) {
    let allowed = allowedChartResolutions(properties);
    return _nearest(
        allowed.length > 0 ? allowed : chartResolutions(properties),
        Constants.DEFAULT_CHART_RESOLUTION,
        Resolution.ORDER
    );
}

// Choose a readable chart range closest to the shared default.
function defaultChartSpan(properties, resolution) {
    let allowed = allowedChartSpans(properties, resolution);
    return _nearest(
        allowed.length > 0 ? allowed : chartSpans(properties, resolution),
        Constants.DEFAULT_CHART_SPAN,
        ChartSpan.ORDER
    );
}

// Build the provider default selection from its supported choices.
function defaultSelection(properties) {
    let resolution = defaultChartResolution(properties);
    return {
        priceResolution: defaultPriceResolution(properties),
        changeResolution: defaultChangeResolution(properties),
        chartResolution: resolution,
        chartRange: defaultChartSpan(properties, resolution)
    };
}

// ── Clamping ─────────────────────────────────────────────────────────────────

// The ONE clamp: the closest selection the provider can serve (its history limits) that is also readable
// (ChartRules: not far too few or too many candles). Used by the settings, by the migration of saved symbols
// and before every fetch. `selection` carries values in the current format; anything missing or unknown
// falls back to the provider's default for that part.
function clamp(properties, selection) {
    let defaults = defaultSelection(properties);
    let price = Resolution.isValid(selection.priceResolution) ? selection.priceResolution : defaults.priceResolution;
    let priceFinal = _nearest(priceResolutions(properties), price, Resolution.ORDER);
    let change = Resolution.isValid(selection.changeResolution)
        ? selection.changeResolution
        : defaults.changeResolution;
    let changeFinal = _nearest(changeResolutions(properties), change, Resolution.ORDER);
    if (!ChartSpan.isValid(selection.chartRange) && !Resolution.isValid(selection.chartResolution))
        return {
            priceResolution: priceFinal,
            changeResolution: changeFinal,
            chartResolution: defaults.chartResolution,
            chartRange: defaults.chartRange
        };

    let wantedResolution = Resolution.isValid(selection.chartResolution)
        ? selection.chartResolution
        : defaults.chartResolution;
    let allowed = allowedChartResolutions(properties);
    let resolution = _nearest(
        allowed.length > 0 ? allowed : chartResolutions(properties),
        wantedResolution,
        Resolution.ORDER
    );
    let spans = allowedChartSpans(properties, resolution);
    if (spans.length === 0) spans = chartSpans(properties, resolution);
    let wantedSpan = ChartSpan.isValid(selection.chartRange) ? selection.chartRange : defaults.chartRange;
    return {
        priceResolution: priceFinal,
        changeResolution: changeFinal,
        chartResolution: resolution,
        chartRange: _nearest(spans, wantedSpan, ChartSpan.ORDER)
    };
}
