import XCTest

@testable import VibePulse

final class UsageSeriesFiltersTests: XCTestCase {
  func testVisibleCumulativeSeriesDropsSeriesWithNoVisibleCost() {
    let start = Date(timeIntervalSince1970: 0)
    let later = Date(timeIntervalSince1970: 60)
    let zeroOnly = UsageSeriesKey.model("zero-only")
    let visible = UsageSeriesKey.model("visible")
    let points = [
      UsageSeriesPoint(series: zeroOnly, date: start, cost: 0),
      UsageSeriesPoint(series: zeroOnly, date: later, cost: 0.00001),
      UsageSeriesPoint(series: visible, date: start, cost: 1),
    ]

    let filtered = UsageSeriesFilters.visibleCumulativeSeries(points)

    XCTAssertEqual(filtered.map(\.series), [visible])
  }

  func testVisibleCumulativeSeriesKeepsZeroPointsForVisibleSeries() {
    let start = Date(timeIntervalSince1970: 0)
    let later = Date(timeIntervalSince1970: 60)
    let series = UsageSeriesKey.model("visible")
    let points = [
      UsageSeriesPoint(series: series, date: start, cost: 0),
      UsageSeriesPoint(series: series, date: later, cost: 1),
    ]

    let filtered = UsageSeriesFilters.visibleCumulativeSeries(points)

    XCTAssertEqual(filtered.map(\.cost), [0, 1])
  }

  func testVisibleDailySeriesDropsZeroCostPointsThatWouldReserveGroupedBarSlots() {
    let today = DateHelper.date(fromKey: DateHelper.dateKey(for: Date()))!
    let points = [
      UsageSeriesPoint(tool: .codex, date: today, cost: 12),
      UsageSeriesPoint(tool: .pi, date: today, cost: 0),
      UsageSeriesPoint(tool: .openCode, date: today, cost: 0.00001),
    ]

    let visible = UsageSeriesFilters.visibleDailySeries(points, mode: .sevenDays)

    XCTAssertEqual(visible.map(\.tool), [.codex])
  }
}
