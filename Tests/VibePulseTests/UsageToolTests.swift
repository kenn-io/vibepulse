import XCTest

@testable import VibePulse

final class UsageToolTests: XCTestCase {
  func testSupportedToolsIncludeAgentsviewPricingSources() {
    XCTAssertEqual(
      UsageTool.allCases.map(\.rawValue),
      ["claude", "codex", "pi", "omp", "gemini", "opencode"])
  }

  func testDailyCommandsFilterAgentsviewByToolAgentName() {
    XCTAssertEqual(
      UsageTool.pi.dailyCommand,
      ["agentsview", "usage", "daily", "--json", "--breakdown", "--agent", "pi"])
    XCTAssertEqual(
      UsageTool.omp.dailyCommand,
      ["agentsview", "usage", "daily", "--json", "--breakdown", "--agent", "omp"])
    XCTAssertEqual(
      UsageTool.gemini.dailyCommand,
      ["agentsview", "usage", "daily", "--json", "--breakdown", "--agent", "gemini"])
    XCTAssertEqual(
      UsageTool.openCode.dailyCommand,
      ["agentsview", "usage", "daily", "--json", "--breakdown", "--agent", "opencode"])
    XCTAssertTrue(UsageTool.allCases.allSatisfy { $0.dailyCommand.contains("--breakdown") })
  }
}
