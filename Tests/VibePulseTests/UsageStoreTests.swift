import SQLite3
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
    XCTAssertEqual(
      rollups.map(\.modelName),
      [
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

  func testUpsertDailyTotalsPreservesModelRollupsWhenBreakdownUnavailable() throws {
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
        DailyTotal(dateKey: "2026-07-02", cost: 14)
      ])

    let rollups = store.fetchModelDailyRollups(since: "2026-07-01", tools: [.claude])
    XCTAssertEqual(
      rollups.map(\.modelName),
      [
        "claude-fable-5",
        "claude-haiku-4-5-20251001",
      ])
    XCTAssertEqual(rollups.map(\.totalCost), [10.25, 2.25])
  }

  func testUpsertDailyTotalsNormalizesModelRollupDateKeysBeforeReplacing() throws {
    let store = try UsageStore(path: ":memory:")

    try store.upsertDailyTotals(
      tool: .codex,
      totals: [
        DailyTotal(
          dateKey: "July 2, 2026",
          cost: 4,
          modelBreakdowns: [
            DailyModelBreakdown(modelName: "gpt-5", cost: 4)
          ])
      ])

    try store.upsertDailyTotals(
      tool: .codex,
      totals: [
        DailyTotal(
          dateKey: "2026-07-02",
          cost: 7,
          modelBreakdowns: [
            DailyModelBreakdown(modelName: "gpt-5", cost: 7)
          ])
      ])

    let rollups = store.fetchModelDailyRollups(since: "2026-07-01", tools: [.codex])
    XCTAssertEqual(rollups.map(\.dateKey), ["2026-07-02"])
    XCTAssertEqual(rollups.map(\.modelName), ["gpt-5"])
    XCTAssertEqual(rollups.map(\.totalCost), [7])
  }

  func testNormalizeModelDailyRollupDatesMergesExistingDuplicateLogicalDates() throws {
    let dbURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("sqlite")
    defer { try? FileManager.default.removeItem(at: dbURL) }

    let store = try UsageStore(path: dbURL.path)
    try insertRawModelDailyRollup(
      path: dbURL.path,
      dateKey: "July 2, 2026",
      tool: .codex,
      modelName: "gpt-5",
      totalCost: 4)
    try insertRawModelDailyRollup(
      path: dbURL.path,
      dateKey: "2026-07-02",
      tool: .codex,
      modelName: "gpt-5",
      totalCost: 7)

    let normalizedCount = try store.normalizeModelDailyRollupDates(for: .codex)

    let rollups = store.fetchModelDailyRollups(since: "2026-07-01", tools: [.codex])
    XCTAssertEqual(normalizedCount, 1)
    XCTAssertEqual(rollups.map(\.dateKey), ["2026-07-02"])
    XCTAssertEqual(rollups.map(\.modelName), ["gpt-5"])
    XCTAssertEqual(rollups.map(\.totalCost), [7])
  }

  func testInsertModelSamplesForRefreshResetsModelsMissingFromCurrentBreakdown() throws {
    let store = try UsageStore(path: ":memory:")
    let calendar = Calendar.current
    let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 2))!
    let first = calendar.date(byAdding: .minute, value: 5, to: start)!
    let second = calendar.date(byAdding: .minute, value: 30, to: start)!

    try store.insertModelSamplesForRefresh(
      tool: .claude,
      modelBreakdowns: [
        DailyModelBreakdown(modelName: "claude-fable-5", cost: 10),
        DailyModelBreakdown(modelName: "claude-haiku-4-5-20251001", cost: 2),
      ],
      recordedAt: first)

    try store.insertModelSamplesForRefresh(
      tool: .claude,
      modelBreakdowns: [
        DailyModelBreakdown(modelName: "claude-fable-5", cost: 12)
      ],
      recordedAt: second)

    let samples = store.fetchModelSamples(tools: [.claude], from: start, to: second)
    XCTAssertEqual(samples.count, 4)
    XCTAssertEqual(
      samples.map(\.modelName),
      [
        "claude-fable-5",
        "claude-haiku-4-5-20251001",
        "claude-fable-5",
        "claude-haiku-4-5-20251001",
      ])
    XCTAssertEqual(samples.map(\.totalCost), [10, 2, 12, 0])
    XCTAssertEqual(samples.map(\.deltaCost), [10, 2, 2, 0])
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

  private func insertRawModelDailyRollup(
    path: String,
    dateKey: String,
    tool: UsageTool,
    modelName: String,
    totalCost: Double
  ) throws {
    var db: OpaquePointer?
    guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
      throw NSError(domain: "UsageStoreTests", code: 1)
    }
    defer { sqlite3_close(db) }

    let sql = """
      INSERT INTO model_daily_rollups (date_key, tool, model_name, total_cost, updated_at)
      VALUES (?, ?, ?, ?, ?);
      """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw NSError(domain: "UsageStoreTests", code: 2)
    }
    defer { sqlite3_finalize(statement) }

    sqlite3_bind_text(statement, 1, (dateKey as NSString).utf8String, -1, nil)
    sqlite3_bind_text(statement, 2, (tool.rawValue as NSString).utf8String, -1, nil)
    sqlite3_bind_text(statement, 3, (modelName as NSString).utf8String, -1, nil)
    sqlite3_bind_double(statement, 4, totalCost)
    sqlite3_bind_double(statement, 5, Date().timeIntervalSince1970)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw NSError(domain: "UsageStoreTests", code: 3)
    }
  }
}
