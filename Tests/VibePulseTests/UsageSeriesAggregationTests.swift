import XCTest

@testable import VibePulse

final class UsageSeriesAggregationTests: XCTestCase {
  func testCumulativeBreakdownsReflectCorrectionsAcrossAgents() {
    let start = Date(timeIntervalSince1970: 1_000)
    let costs: [(UsageAgent, Double)] = [
      (.codex, 10), (.claude, 2), (.codex, 5), (.codex, 6), (.claude, 0),
    ]
    let modelSamples = costs.enumerated().map { index, value in
      ModelUsageSample(
        tool: value.0, modelName: "shared-model",
        recordedAt: start.addingTimeInterval(Double(index)), totalCost: value.1, deltaCost: 0)
    }
    let machineSamples = costs.enumerated().map { index, value in
      MachineUsageSample(
        tool: value.0, machineName: "shared-machine",
        recordedAt: start.addingTimeInterval(Double(index)), totalCost: value.1, deltaCost: 0)
    }

    XCTAssertEqual(
      UsageSeriesAggregation.cumulativeModelSeries(from: modelSamples).map(\.cost),
      [10, 12, 7, 8, 6])
    XCTAssertEqual(
      UsageSeriesAggregation.cumulativeMachineSeries(from: machineSamples).map(\.cost),
      [10, 12, 7, 8, 6])
  }

  func testCumulativeMachineSeriesCombinesSameMachineAcrossAgents() {
    let calendar = Calendar.current
    let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 10))!
    let later = calendar.date(byAdding: .hour, value: 1, to: start)!
    let samples = [
      MachineUsageSample(
        tool: .claude,
        machineName: "shared-host",
        recordedAt: start,
        totalCost: 2,
        deltaCost: 2),
      MachineUsageSample(
        tool: .codex,
        machineName: "shared-host",
        recordedAt: start,
        totalCost: 3,
        deltaCost: 3),
      MachineUsageSample(
        tool: .claude,
        machineName: "shared-host",
        recordedAt: later,
        totalCost: 5,
        deltaCost: 3),
    ]

    let points = UsageSeriesAggregation.cumulativeMachineSeries(from: samples)

    XCTAssertEqual(points.map(\.series), [.machine("shared-host"), .machine("shared-host")])
    XCTAssertEqual(points.map(\.date), [start, later])
    XCTAssertEqual(points.map(\.cost), [5, 8])
  }

  func testCumulativeMachineSeriesKeepsDifferentMachinesSeparate() {
    let start = Calendar.current.date(
      from: DateComponents(year: 2026, month: 7, day: 16, hour: 10))!
    let samples = [
      MachineUsageSample(
        tool: .claude,
        machineName: "host-a",
        recordedAt: start,
        totalCost: 2,
        deltaCost: 2),
      MachineUsageSample(
        tool: .claude,
        machineName: "host-b",
        recordedAt: start,
        totalCost: 7,
        deltaCost: 7),
    ]

    let points = UsageSeriesAggregation.cumulativeMachineSeries(from: samples)

    XCTAssertEqual(points.map(\.series), [.machine("host-a"), .machine("host-b")])
    XCTAssertEqual(points.map(\.cost), [2, 7])
  }

  func testDailyMachineSeriesCombinesSameMachineAcrossAgents() {
    let rollups = [
      MachineDailyRollup(
        dateKey: "2026-07-15", tool: .claude, machineName: "shared-host", totalCost: 2),
      MachineDailyRollup(
        dateKey: "2026-07-15", tool: .codex, machineName: "shared-host", totalCost: 3),
      MachineDailyRollup(
        dateKey: "2026-07-16", tool: .claude, machineName: "shared-host", totalCost: 4),
    ]

    let points = UsageSeriesAggregation.dailyMachineSeries(from: rollups)

    XCTAssertEqual(points.map(\.series), [.machine("shared-host"), .machine("shared-host")])
    XCTAssertEqual(points.map(\.cost), [5, 4])
  }

  func testMachineTotalsOnlyIncludeRequestedDay() {
    let rollups = [
      MachineDailyRollup(
        dateKey: "2026-07-15", tool: .claude, machineName: "host-a", totalCost: 20),
      MachineDailyRollup(
        dateKey: "2026-07-16", tool: .claude, machineName: "host-a", totalCost: 2),
      MachineDailyRollup(
        dateKey: "2026-07-16", tool: .codex, machineName: "host-a", totalCost: 3),
      MachineDailyRollup(
        dateKey: "2026-07-16", tool: .claude, machineName: "host-b", totalCost: 7),
    ]

    let totals = UsageSeriesAggregation.machineTotals(
      from: rollups, dateKey: "2026-07-16")

    XCTAssertEqual(totals.map(\.series), [.machine("host-a"), .machine("host-b")])
    XCTAssertEqual(totals.map(\.totalCost), [5, 7])
  }

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

  func testCumulativeModelSeriesReflectsCorrectionToZero() {
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
    XCTAssertEqual(points.map(\.cost), [2, 0])
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
    XCTAssertEqual(points.map(\.cost), [2, 0, 2, 5])
  }
}
