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
