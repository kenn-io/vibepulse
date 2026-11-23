import XCTest

@testable import VibePulse

final class ChartModeTests: XCTestCase {
  func testUsageAggregationModesIncludeMachineInDisplayOrder() {
    XCTAssertEqual(
      UsageAggregationMode.allCases.map(\.rawValue),
      ["agent", "model", "machine"])
    XCTAssertEqual(
      UsageAggregationMode.allCases.map(\.title),
      ["Agent", "Model", "Machine"])
  }

  func testDailyWindowDaysOnlyAppliesToDailyModes() {
    XCTAssertNil(ChartMode.today.dailyWindowDays)
    XCTAssertEqual(ChartMode.sevenDays.dailyWindowDays, 7)
    XCTAssertEqual(ChartMode.thirtyDays.dailyWindowDays, 30)
  }
}
