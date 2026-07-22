# Scrollable value-sorted usage legend

**Status:** Approved for implementation
**Date:** 2026-07-21

## Goal

Keep the existing two-column usage legend while ensuring every series remains
reachable. Order entries from highest total cost to lowest total cost. Let the
legend expand through 16 entries (eight rows), then scroll vertically for any
additional entries.

## Scope

- Preserve the current legend item appearance and two-column layout.
- Sort the displayed `ToolTotal` values by descending `totalCost` in every chart
  mode and aggregation mode.
- Break equal-cost ties by display name so ordering is deterministic.
- Size the legend for its actual number of rows through eight rows.
- Cap the legend at eight visible rows and enable vertical scrolling when more
  than 16 entries exist.

The chart, tooltip ordering, color assignment, totals, and data collection are
unchanged.

## Design

Move legend ordering into a small pure helper so the rule can be tested without
rendering SwiftUI. `MenuContentView` will pass its filtered totals through that
helper before rendering.

Wrap the existing `LazyVGrid` in a vertical `ScrollView`. Derive the visible row
count from the number of entries and two columns, capped at eight. Apply the
corresponding height to the scroll region so short legends stay compact, lists
up to 16 entries expand naturally, and larger lists scroll within the capped
region.

## Testing

Focused unit tests will verify that:

- totals are sorted from largest to smallest;
- equal totals use display name as a stable tie-breaker;
- the visible row count grows through eight rows and remains capped there.

The full Swift test suite and formatting/diff checks will run after the change.
