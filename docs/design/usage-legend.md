
# Scrollable, value-sorted usage legend

## Problem

The menu bar popover's two-column usage legend grew unbounded with the
number of agents, models, or machines being charted, pushing the rest of the
popover content down and off-screen once there were more than a handful of
entries. The legend also followed whatever order its underlying map
produced, not a stable, meaningful order.

## Behavior

The legend keeps its existing two-column item appearance. Entries are sorted
by descending total cost in every chart mode and aggregation mode (today,
7-day, 30-day; by agent, model, or machine); equal-cost entries break ties
by display name, ignoring case, so the order is deterministic. Up to 16 entries (eight
two-column rows) show without scrolling; a `ScrollView` wraps the grid and
scroll indicators only appear once there are more than 16 entries, so short
legends stay compact and large ones scroll within a capped height instead of
growing forever.

## Bar selection in history charts

The 7-day, 30-day, and 1-year charts have no floating tooltip. Hovering a bar
selects it instead: the other bars dim, a dashed rule marks the selected day or
month, and the headline total, its subtitle, and the legend switch to that
bar's per-series totals, sorted the same way as the full-range legend. Long
breakdowns scroll in the legend, so every series stays reachable and the chart
stays visible.

Clicking a bar pins the selection, shown by a pin icon after the subtitle, so
the pointer can leave the chart to scroll the legend. Clicking the pinned bar
again unpins it, and clicking an empty part of the plot clears it. Changing
the view or group, or reopening the menu, also clears the selection.

## Implementation

`Sources/VibePulse/Utils/UsageLegendLayout.swift` is a small pure helper with
no SwiftUI dependency, so its rules are unit-testable directly:

- `sortedTotals(_ totals: [ToolTotal]) -> [ToolTotal]` sorts by descending
  `totalCost`, falling back to ascending `series.displayName` on ties.
- `visibleRowCount(for itemCount: Int) -> Int` computes the number of
  two-column rows for a given item count, capped at 8 rows (16 items):
  `ceil(min(itemCount, 16) / 2)`.

`UsageSeriesAggregation.bucketPoints` picks the points that share the
selected bar's day or month, and `UsageSeriesAggregation.totalsBySeries`
turns them into sorted legend totals.

`MenuContentView` builds the same `ToolTotal` values it always did (via
`toolBreakdown`), pipes them through `UsageLegendLayout.sortedTotals` before
rendering, and wraps the existing `LazyVGrid` in a vertical `ScrollView`
whose frame height is `UsageLegendLayout.visibleRowCount(for:)` rows of a
fixed row height plus inter-row spacing. Scroll indicators are shown only
when the item count exceeds `UsageLegendLayout.maximumVisibleItems` (16).
