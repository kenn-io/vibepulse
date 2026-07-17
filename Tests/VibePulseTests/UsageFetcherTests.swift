import XCTest

@testable import VibePulse

final class UsageFetcherTests: XCTestCase {
  func testParseDailyTotalsIncludesModelBreakdowns() throws {
    let json = """
      {
        "daily": [
          {
            "date": "2026-07-02",
            "totalCost": 12.5,
            "modelBreakdowns": [
              { "modelName": "claude-fable-5", "cost": 10.25 },
              { "modelName": "claude-haiku-4-5-20251001", "cost": 2.25 }
            ]
          }
        ]
      }
      """
    let data = try XCTUnwrap(json.data(using: .utf8))

    let totals = try UsageFetcher.parseDailyTotals(data: data)

    XCTAssertEqual(totals.count, 1)
    XCTAssertEqual(totals[0].dateKey, "2026-07-02")
    XCTAssertEqual(totals[0].cost, 12.5, accuracy: 0.001)
    let modelBreakdowns = try XCTUnwrap(totals[0].modelBreakdowns)
    XCTAssertEqual(
      modelBreakdowns.map(\.modelName),
      [
        "claude-fable-5",
        "claude-haiku-4-5-20251001",
      ])
    XCTAssertEqual(modelBreakdowns.map(\.cost), [10.25, 2.25])
  }

  func testParseDailyTotalsDistinguishesUnavailableModelBreakdownsFromExplicitEmpty() throws {
    let json = """
      {
        "daily": [
          {
            "date": "2026-07-02",
            "totalCost": 12.5
          },
          {
            "date": "2026-07-03",
            "totalCost": 7.25,
            "modelBreakdowns": []
          }
        ]
      }
      """
    let data = try XCTUnwrap(json.data(using: .utf8))

    let totals = try UsageFetcher.parseDailyTotals(data: data)

    XCTAssertEqual(totals.count, 2)
    XCTAssertNil(totals[0].modelBreakdowns)
    XCTAssertNotNil(totals[1].modelBreakdowns)
    XCTAssertEqual(totals[1].modelBreakdowns?.count, 0)
  }

  func testParseDailyTotalsTreatsPartiallyMalformedModelBreakdownsAsUnavailable() throws {
    let json = """
      {
        "daily": [
          {
            "date": "2026-07-02",
            "totalCost": 12.5,
            "modelBreakdowns": [
              { "modelName": "claude-fable-5", "cost": 10.25 },
              { "modelName": "claude-haiku-4-5-20251001" }
            ]
          }
        ]
      }
      """
    let data = try XCTUnwrap(json.data(using: .utf8))

    let totals = try UsageFetcher.parseDailyTotals(data: data)

    XCTAssertNil(totals[0].modelBreakdowns)
  }

  func testParseDailyTotalsIncludesValidMachineBreakdowns() throws {
    let json = """
      {
        "daily": [
          {
            "date": "2026-07-16",
            "totalCost": 12.5,
            "machineBreakdowns": [
              { "machineName": "host-a", "cost": 8.25 },
              { "machineName": "host-b", "cost": "4.25" },
              { "machineName": "", "cost": 1 },
              { "machineName": "host-c", "cost": "invalid" }
            ]
          }
        ]
      }
      """
    let data = try XCTUnwrap(json.data(using: .utf8))

    let totals = try UsageFetcher.parseDailyTotals(data: data)

    let machineBreakdowns = try XCTUnwrap(totals[0].machineBreakdowns)
    XCTAssertEqual(machineBreakdowns.map(\.machineName), ["host-a", "host-b"])
    XCTAssertEqual(machineBreakdowns.map(\.cost), [8.25, 4.25])
  }

  func testParseDailyTotalsDistinguishesUnavailableMachineBreakdownsFromExplicitEmpty() throws {
    let json = """
      {
        "daily": [
          {
            "date": "2026-07-16",
            "totalCost": 12.5
          },
          {
            "date": "2026-07-17",
            "totalCost": 7.25,
            "machineBreakdowns": "malformed"
          },
          {
            "date": "2026-07-18",
            "totalCost": 4,
            "machineBreakdowns": []
          }
        ]
      }
      """
    let data = try XCTUnwrap(json.data(using: .utf8))

    let totals = try UsageFetcher.parseDailyTotals(data: data)

    XCTAssertNil(totals[0].machineBreakdowns)
    XCTAssertNil(totals[1].machineBreakdowns)
    XCTAssertNotNil(totals[2].machineBreakdowns)
    XCTAssertEqual(totals[2].machineBreakdowns?.count, 0)
  }
}
