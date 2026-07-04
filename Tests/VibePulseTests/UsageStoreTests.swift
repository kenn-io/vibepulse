import XCTest

@testable import VibePulse

final class UsageStoreTests: XCTestCase {
  func testSampleDeltaCalculation() throws {
    let store = try UsageStore(path: ":memory:")
    let calendar = Calendar.current
    let start = calendar.date(from: DateComponents(year: 2024, month: 1, day: 15))!
    let first = calendar.date(byAdding: .minute, value: 5, to: start)!
    let second = calendar.date(byAdding: .minute, value: 30, to: start)!

    try store.insertSample(tool: .claude, totalCost: 10, recordedAt: first)
    try store.insertSample(tool: .claude, totalCost: 15, recordedAt: second)

    let samples = store.fetchSamples(tool: .claude, from: start, to: second)
    XCTAssertEqual(samples.count, 2)
    XCTAssertEqual(samples[0].deltaCost, 10, accuracy: 0.001)
    XCTAssertEqual(samples[1].deltaCost, 5, accuracy: 0.001)
  }

  func testSampleDeltaDoesNotGoNegative() throws {
    let store = try UsageStore(path: ":memory:")
    let calendar = Calendar.current
    let start = calendar.date(from: DateComponents(year: 2024, month: 1, day: 16))!
    let first = calendar.date(byAdding: .minute, value: 10, to: start)!
    let second = calendar.date(byAdding: .minute, value: 20, to: start)!

    try store.insertSample(tool: .codex, totalCost: 12, recordedAt: first)
    try store.insertSample(tool: .codex, totalCost: 8, recordedAt: second)

    let samples = store.fetchSamples(tool: .codex, from: start, to: second)
    XCTAssertEqual(samples.count, 2)
    XCTAssertEqual(samples[0].deltaCost, 12, accuracy: 0.001)
    XCTAssertEqual(samples[1].deltaCost, 0, accuracy: 0.001)
  }

  func testUpsertDailyTotalsPersistsModelRollupsPerAgent() throws {
    let store = try UsageStore(path: ":memory:")
    let totals = [
      DailyTotal(
        dateKey: "2026-07-02",
        cost: 12.5,
        modelBreakdowns: [
          DailyModelBreakdown(modelName: "claude-fable-5", cost: 10.25),
          DailyModelBreakdown(modelName: "claude-haiku-4-5-20251001", cost: 2.25),
        ])
    ]

    try store.upsertDailyTotals(tool: .claude, totals: totals)

    let rollups = store.fetchModelDailyRollups(since: "2026-07-01", tools: [.claude])
    XCTAssertEqual(rollups.map(\.dateKey), ["2026-07-02", "2026-07-02"])
    XCTAssertEqual(rollups.map(\.tool), [.claude, .claude])
    XCTAssertEqual(rollups.map(\.modelName), [
      "claude-fable-5",
      "claude-haiku-4-5-20251001",
    ])
    XCTAssertEqual(rollups.map(\.totalCost), [10.25, 2.25])
  }

  func testUpsertDailyTotalsRemovesStaleModelRollups() throws {
    let store = try UsageStore(path: ":memory:")

    try store.upsertDailyTotals(
      tool: .claude,
      totals: [
        DailyTotal(
          dateKey: "2026-07-02",
          cost: 12.5,
          modelBreakdowns: [
            DailyModelBreakdown(modelName: "claude-fable-5", cost: 10.25),
            DailyModelBreakdown(modelName: "claude-haiku-4-5-20251001", cost: 2.25),
          ])
      ])

    try store.upsertDailyTotals(
      tool: .claude,
      totals: [
        DailyTotal(
          dateKey: "2026-07-02",
          cost: 10.75,
          modelBreakdowns: [
            DailyModelBreakdown(modelName: "claude-fable-5", cost: 10.75)
          ])
      ])

    let rollups = store.fetchModelDailyRollups(since: "2026-07-01", tools: [.claude])
    XCTAssertEqual(rollups.map(\.modelName), ["claude-fable-5"])
    XCTAssertEqual(rollups.map(\.totalCost), [10.75])
  }

  func testModelSampleDeltaCalculationIsScopedByAgentAndModel() throws {
    let store = try UsageStore(path: ":memory:")
    let calendar = Calendar.current
    let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 2))!
    let first = calendar.date(byAdding: .minute, value: 5, to: start)!
    let second = calendar.date(byAdding: .minute, value: 30, to: start)!

    try store.insertModelSample(
      tool: .claude, modelName: "shared-model", totalCost: 10, recordedAt: first)
    try store.insertModelSample(
      tool: .codex, modelName: "shared-model", totalCost: 4, recordedAt: first)
    try store.insertModelSample(
      tool: .claude, modelName: "shared-model", totalCost: 15, recordedAt: second)

    let samples = store.fetchModelSamples(tools: [.claude, .codex], from: start, to: second)

    XCTAssertEqual(samples.count, 3)
    XCTAssertEqual(samples[0].deltaCost, 10, accuracy: 0.001)
    XCTAssertEqual(samples[1].deltaCost, 4, accuracy: 0.001)
    XCTAssertEqual(samples[2].deltaCost, 5, accuracy: 0.001)
  }
}
