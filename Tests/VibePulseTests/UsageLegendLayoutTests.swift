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

  func testSortedTotalsBreaksTiesIgnoringCase() {
    let totals = [
      ToolTotal(series: .model("beta"), totalCost: 5),
      ToolTotal(series: .model("Gamma"), totalCost: 5),
      ToolTotal(series: .model("alpha"), totalCost: 5),
    ]

    XCTAssertEqual(
      UsageLegendLayout.sortedTotals(totals).map(\.series.displayName),
      ["alpha", "beta", "Gamma"])
  }

  func testTotalsBySeriesSumsOneBucketLargestFirst() throws {
    let calendar = Calendar(identifier: .gregorian)
    let august = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 3)))
    let laterAugust = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 8, day: 20)))
    let september = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)))
    let points = [
      UsageSeriesPoint(series: .model("Gemini 3.5 Flash"), date: august, cost: 0.03),
      UsageSeriesPoint(series: .model("claude-fable-5"), date: august, cost: 2000),
      UsageSeriesPoint(series: .model("claude-fable-5"), date: laterAugust, cost: 657.93),
      UsageSeriesPoint(series: .model("gpt-5.6-sol"), date: laterAugust, cost: 24_000),
      UsageSeriesPoint(series: .model("gpt-5-mini"), date: august, cost: 0),
      UsageSeriesPoint(series: .model("gpt-6-astra"), date: september, cost: 9000),
    ]

    let bucket = UsageSeriesAggregation.bucketPoints(
      points, containing: laterAugust, unit: .month, calendar: calendar)
    let totals = UsageSeriesAggregation.totalsBySeries(bucket)

    XCTAssertEqual(
      totals.map(\.series.displayName), ["gpt-5.6-sol", "claude-fable-5", "Gemini 3.5 Flash"])
    XCTAssertEqual(totals[1].totalCost, 2657.93, accuracy: 0.001)
  }

  func testVisibleRowCountUsesTwoColumnsAndCapsAtEightRows() {
    XCTAssertEqual(UsageLegendLayout.visibleRowCount(for: 0), 0)
    XCTAssertEqual(UsageLegendLayout.visibleRowCount(for: 1), 1)
    XCTAssertEqual(UsageLegendLayout.visibleRowCount(for: 16), 8)
    XCTAssertEqual(UsageLegendLayout.visibleRowCount(for: 17), 8)
  }
}
