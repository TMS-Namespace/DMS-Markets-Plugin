// TimeUnits.js - calendar time units in milliseconds, defined once.
//
// Everything that measures time (resolutions, chart spans, polling, retry delays, "x ago")
// builds on these, so no number is spelled out twice.

.pragma library

var SECOND_MS = 1000
var MINUTE_MS = 60 * SECOND_MS
var HOUR_MS   = 60 * MINUTE_MS
var DAY_MS    = 24 * HOUR_MS
var WEEK_MS   = 7 * DAY_MS
var MONTH_MS  = 30 * DAY_MS
