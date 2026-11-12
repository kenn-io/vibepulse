import Foundation

enum UsageLegendLayout {
  static let columnCount = 2
  static let maximumVisibleItems = 16

  static func sortedTotals(_ totals: [ToolTotal]) -> [ToolTotal] {
    totals.sorted { isOrdered(($0.series, $0.totalCost), before: ($1.series, $1.totalCost)) }
  }

  /// Largest cost first; equal costs sort by display name, ignoring case.
  static func isOrdered(
    _ lhs: (series: UsageSeriesKey, cost: Double),
    before rhs: (series: UsageSeriesKey, cost: Double)
  ) -> Bool {
    if lhs.cost != rhs.cost {
      return lhs.cost > rhs.cost
    }
    return lhs.series.displayName.localizedStandardCompare(rhs.series.displayName)
      == .orderedAscending
  }

  static func visibleRowCount(for itemCount: Int) -> Int {
    let boundedItemCount = min(max(itemCount, 0), maximumVisibleItems)
    return (boundedItemCount + columnCount - 1) / columnCount
  }
}
