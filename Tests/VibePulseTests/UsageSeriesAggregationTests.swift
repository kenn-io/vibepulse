import XCTest

@testable import VibePulse

final class UsageSeriesAggregationTests: XCTestCase {
  func testRunningDailySeriesFillsEveryDayAndEndsAtTheWindowTotal() throws {
    let formatter = ISO8601DateFormatter()
    let now = try XCTUnwrap(formatter.date(from: "2026-11-23T15:00:00Z"))
    let context = UsageDateContext(now: now, timeZone: TimeZone(identifier: "America/New_York")!)
    func day(_ key: String) throws -> Date {
      try XCTUnwrap(DateHelper.date(fromKey: key, in: context.timeZone))
    }
    let daily = [
      UsageSeriesPoint(series: .model("opus"), date: try day("2026-11-17"), cost: 4),
      UsageSeriesPoint(series: .model("opus"), date: try day("2026-11-20"), cost: 6),
      UsageSeriesPoint(series: .model("opus"), date: try day("2026-11-23"), cost: 1),
      UsageSeriesPoint(series: .model("haiku"), date: try day("2026-11-21"), cost: 2),
      // Outside the 7-day window, so it must not count toward the running total.
      UsageSeriesPoint(series: .model("haiku"), date: try day("2026-11-16"), cost: 100),
    ]

    let running = UsageSeriesAggregation.runningDailySeries(
      from: daily, days: 7, context: context)

    let days = try ["17", "18", "19", "20", "21", "22", "23"].map { try day("2026-11-\($0)") }
    let opus = running.filter { $0.series == .model("opus") }
    XCTAssertEqual(opus.map(\.date), days)
    XCTAssertEqual(opus.map(\.cost), [4, 4, 4, 10, 10, 10, 11])
    let haiku = running.filter { $0.series == .model("haiku") }
    XCTAssertEqual(haiku.map(\.date), days)
    XCTAssertEqual(haiku.map(\.cost), [0, 0, 0, 0, 2, 2, 2])
  }

  func testRunningDailySeriesKeepsMidnightSpendWhenDaylightSavingSkipsMidnightToday() throws {
    // Chile moves its clocks from 00:00 to 01:00 on 2026-09-06, so that day starts at 01:00.
    let zone = try XCTUnwrap(TimeZone(identifier: "America/Santiago"))
    let formatter = ISO8601DateFormatter()
    let now = try XCTUnwrap(formatter.date(from: "2026-09-06T16:00:00Z"))
    let context = UsageDateContext(now: now, timeZone: zone)
    let earlierDays = try ["2026-08-31", "2026-09-03"].map { key in
      try XCTUnwrap(DateHelper.date(fromKey: key, in: zone))
    }
    let daily = (earlierDays + [context.startOfToday]).map {
      UsageSeriesPoint(series: .model("opus"), date: $0, cost: 1)
    }

    let running = UsageSeriesAggregation.runningDailySeries(
      from: daily, days: 7, context: context)

    XCTAssertEqual(running.map(\.cost), [1, 1, 1, 2, 2, 2, 3])
  }

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
