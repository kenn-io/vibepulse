# Scrollable Value-Sorted Legend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the existing two-column usage legend, sort it by descending total cost, show up to 16 entries without scrolling, and scroll beyond 16.

**Architecture:** Add a small pure `UsageLegendLayout` helper for deterministic value ordering and the eight-row cap. `MenuContentView` will continue to build the same `ToolTotal` values and render the same cells, but will sort through the helper and place the grid in a dynamically sized vertical `ScrollView`.

**Tech Stack:** Swift 6, SwiftUI, XCTest, Swift Package Manager

## Global Constraints

- Preserve the current two-column legend item appearance.
- Show at most 16 entries (eight two-column rows) before vertical scrolling.
- Sort every legend mode by descending `totalCost`; break equal-cost ties by display name.
- Do not change chart rendering, tooltip ordering, colors, totals, or data collection.

---

### Task 1: Value-sorted bounded legend

**Files:**
- Create: `Sources/VibePulse/Utils/UsageLegendLayout.swift`
- Create: `Tests/VibePulseTests/UsageLegendLayoutTests.swift`
- Modify: `Sources/VibePulse/Views/MenuContentView.swift:116-209`

**Interfaces:**
- Consumes: `[ToolTotal]` values already produced by `MenuContentView.toolBreakdown`.
- Produces: `UsageLegendLayout.sortedTotals(_:) -> [ToolTotal]` and `UsageLegendLayout.visibleRowCount(for:) -> Int`.

- [x] **Step 1: Write failing ordering and row-cap tests**

Create `Tests/VibePulseTests/UsageLegendLayoutTests.swift`:

```swift
import XCTest

@testable import VibePulse

final class UsageLegendLayoutTests: XCTestCase {
  func testSortedTotalsOrdersLargestValueFirst() {
    let totals = [
      ToolTotal(series: .model("small"), totalCost: 1),
      ToolTotal(series: .model("large"), totalCost: 10),
      ToolTotal(series: .model("medium"), totalCost: 5),
    ]

    XCTAssertEqual(
      UsageLegendLayout.sortedTotals(totals).map(\.series.displayName),
      ["large", "medium", "small"])
  }

  func testSortedTotalsBreaksEqualValuesByDisplayName() {
    let totals = [
      ToolTotal(series: .model("Zulu"), totalCost: 5),
      ToolTotal(series: .model("Alpha"), totalCost: 5),
    ]

    XCTAssertEqual(
      UsageLegendLayout.sortedTotals(totals).map(\.series.displayName),
      ["Alpha", "Zulu"])
  }

  func testVisibleRowCountUsesTwoColumnsAndCapsAtEightRows() {
    XCTAssertEqual(UsageLegendLayout.visibleRowCount(for: 0), 0)
    XCTAssertEqual(UsageLegendLayout.visibleRowCount(for: 1), 1)
    XCTAssertEqual(UsageLegendLayout.visibleRowCount(for: 16), 8)
    XCTAssertEqual(UsageLegendLayout.visibleRowCount(for: 17), 8)
  }
}
```

- [x] **Step 2: Run the focused tests and verify RED**

Run:

```bash
mise exec -- swift test --filter UsageLegendLayoutTests
```

Expected: compilation fails because `UsageLegendLayout` does not exist.

- [x] **Step 3: Implement the pure ordering and row-cap helper**

Create `Sources/VibePulse/Utils/UsageLegendLayout.swift`:

```swift
import Foundation

enum UsageLegendLayout {
  static let columnCount = 2
  static let maximumVisibleItems = 16

  static func sortedTotals(_ totals: [ToolTotal]) -> [ToolTotal] {
    totals.sorted { lhs, rhs in
      if lhs.totalCost != rhs.totalCost {
        return lhs.totalCost > rhs.totalCost
      }
      return lhs.series.displayName < rhs.series.displayName
    }
  }

  static func visibleRowCount(for itemCount: Int) -> Int {
    let boundedItemCount = min(max(itemCount, 0), maximumVisibleItems)
    return (boundedItemCount + columnCount - 1) / columnCount
  }
}
```

- [x] **Step 4: Run the focused tests and verify GREEN**

Run:

```bash
mise exec -- swift test --filter UsageLegendLayoutTests
```

Expected: all three `UsageLegendLayoutTests` pass.

- [x] **Step 5: Connect the tested rules to the existing legend**

In `Sources/VibePulse/Views/MenuContentView.swift`, add predictable row sizing and wrap the existing grid:

```swift
private let legendRowHeight: CGFloat = 28
private let legendRowSpacing: CGFloat = 8

private var totalsBreakdown: some View {
  ScrollView(.vertical) {
    LazyVGrid(columns: legendColumns, alignment: .leading, spacing: legendRowSpacing) {
      ForEach(toolBreakdown) { total in
        ToolTotalLegendItem(total: total)
          .frame(height: legendRowHeight, alignment: .topLeading)
      }
    }
  }
  .scrollIndicators(toolBreakdown.count > UsageLegendLayout.maximumVisibleItems ? .visible : .hidden)
  .frame(height: legendHeight)
}

private var legendHeight: CGFloat {
  let rows = UsageLegendLayout.visibleRowCount(for: toolBreakdown.count)
  guard rows > 0 else { return 0 }
  return CGFloat(rows) * legendRowHeight + CGFloat(rows - 1) * legendRowSpacing
}
```

Refactor `toolBreakdown` so both switch branches feed the helper:

```swift
private var toolBreakdown: [ToolTotal] {
  let totals: [ToolTotal]
  switch chartMode {
  case .today:
    totals = selectedTotals.filter { $0.totalCost > 0.0001 }
  case .sevenDays, .thirtyDays:
    var totalsBySeries: [UsageSeriesKey: Double] = [:]
    for point in visibleDailySeries {
      totalsBySeries[point.series, default: 0] += point.cost
    }
    totals = totalsBySeries.compactMap { series, total in
      guard total > 0.0001 else { return nil }
      return ToolTotal(series: series, totalCost: total)
    }
  }
  return UsageLegendLayout.sortedTotals(totals)
}
```

- [x] **Step 6: Format and run all verification**

Run:

```bash
mise exec -- scripts/format.sh
mise exec -- swift test
git diff --check
```

Expected: formatting succeeds, the full test suite passes, and `git diff --check` prints no output.

- [x] **Step 7: Review the final diff and commit**

Review:

```bash
git status --short
git diff --stat
git diff HEAD
```

Then use the mandatory commit skill, stage only the helper, tests, menu view, and this plan, and create one rationale-focused commit without bypassing hooks.
