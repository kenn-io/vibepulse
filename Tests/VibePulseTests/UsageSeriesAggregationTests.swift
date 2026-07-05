import XCTest

@testable import VibePulse

final class UsageSeriesAggregationTests: XCTestCase {
  func testCumulativeModelSeriesCombinesSameModelAcrossAgents() {
    let calendar = Calendar.current
    let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 10))!
    let later = calendar.date(byAdding: .hour, value: 1, to: start)!
    let samples = [
      ModelUsageSample(
        tool: .claude,
        modelName: "shared-model",
        recordedAt: start,
        totalCost: 2,
        deltaCost: 2),
      ModelUsageSample(
        tool: .codex,
        modelName: "shared-model",
        recordedAt: start,
        totalCost: 3,
        deltaCost: 3),
      ModelUsageSample(
        tool: .claude,
        modelName: "shared-model",
        recordedAt: later,
        totalCost: 5,
        deltaCost: 3),
    ]

    let points = UsageSeriesAggregation.cumulativeModelSeries(from: samples)

    XCTAssertEqual(points.map(\.series.displayName), ["shared-model", "shared-model"])
    XCTAssertEqual(points.map(\.date), [start, later])
    XCTAssertEqual(points.map(\.cost), [5, 8])
  }
}
