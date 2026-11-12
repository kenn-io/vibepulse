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
