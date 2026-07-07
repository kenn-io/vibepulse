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

  func testCumulativeModelSeriesDoesNotDropWhenModelResetsToZero() {
    let calendar = Calendar.current
    let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 10))!
    let later = calendar.date(byAdding: .hour, value: 1, to: start)!
    let samples = [
      ModelUsageSample(
        tool: .claude,
        modelName: "claude-haiku-4-5-20251001",
        recordedAt: start,
        totalCost: 2,
        deltaCost: 2),
      ModelUsageSample(
        tool: .claude,
        modelName: "claude-haiku-4-5-20251001",
        recordedAt: later,
        totalCost: 0,
        deltaCost: 0),
    ]

    let points = UsageSeriesAggregation.cumulativeModelSeries(from: samples)

    XCTAssertEqual(
      points.map(\.series.displayName),
      [
        "claude-haiku-4-5-20251001",
        "claude-haiku-4-5-20251001",
      ])
    XCTAssertEqual(points.map(\.date), [start, later])
    XCTAssertEqual(points.map(\.cost), [2, 2])
  }

  func testCumulativeModelSeriesDoesNotDoubleCountResetThenReappear() {
    let calendar = Calendar.current
    let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 10))!
    let reset = calendar.date(byAdding: .minute, value: 30, to: start)!
    let reappearSameTotal = calendar.date(byAdding: .minute, value: 45, to: start)!
    let reappearHigherTotal = calendar.date(byAdding: .hour, value: 1, to: start)!
    let samples = [
      ModelUsageSample(
        tool: .claude,
        modelName: "claude-haiku-4-5-20251001",
        recordedAt: start,
        totalCost: 2,
        deltaCost: 2),
      ModelUsageSample(
        tool: .claude,
        modelName: "claude-haiku-4-5-20251001",
        recordedAt: reset,
        totalCost: 0,
        deltaCost: 0),
      ModelUsageSample(
        tool: .claude,
        modelName: "claude-haiku-4-5-20251001",
        recordedAt: reappearSameTotal,
        totalCost: 2,
        deltaCost: 2),
      ModelUsageSample(
        tool: .claude,
        modelName: "claude-haiku-4-5-20251001",
        recordedAt: reappearHigherTotal,
        totalCost: 5,
        deltaCost: 3),
    ]

    let points = UsageSeriesAggregation.cumulativeModelSeries(from: samples)

    XCTAssertEqual(
      points.map(\.date),
      [start, reset, reappearSameTotal, reappearHigherTotal])
    XCTAssertEqual(points.map(\.cost), [2, 2, 2, 5])
  }
}
