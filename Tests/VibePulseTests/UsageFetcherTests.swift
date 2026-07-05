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
}
