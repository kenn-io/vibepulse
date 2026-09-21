import XCTest

@testable import VibePulse

final class MachineLabelsTests: XCTestCase {
  func testMachineSeriesDisplaysLabelWhileKeepingStableIdentity() {
    let series = UsageSeriesKey.machine("installation-a")

    XCTAssertEqual(
      series.displayName(machineLabels: ["installation-a": "Laptop"]), "Laptop")
    XCTAssertEqual(
      series.displayName(machineLabels: ["installation-a": "Renamed Laptop"]),
      "Renamed Laptop")
    XCTAssertEqual(series.chartIdentity, "machine:installation-a")
    XCTAssertEqual(series, UsageSeriesKey.machine("installation-a"))
  }

  func testMachineSeriesFallsBackToRawValueForMissingOrEmptyLabel() {
    let series = UsageSeriesKey.machine("installation-a")

    XCTAssertEqual(series.displayName(machineLabels: [:]), "installation-a")
    XCTAssertEqual(
      series.displayName(machineLabels: ["installation-a": ""]), "installation-a")
    XCTAssertEqual(
      series.displayName(machineLabels: ["installation-b": "Workstation"]),
      "installation-a")
  }

  func testLabelsOnlyApplyToMachineSeries() {
    let labels = ["claude": "Laptop", "shared-model": "Workstation"]

    XCTAssertEqual(
      UsageSeriesKey.agent(.claude).displayName(machineLabels: labels), "Claude Code")
    XCTAssertEqual(
      UsageSeriesKey.model("shared-model").displayName(machineLabels: labels),
      "shared-model")
  }

  func testMachinesSharingOneLabelKeepSeparateTotalsAndSeries() {
    let rollups = [
      MachineDailyRollup(
        dateKey: "2026-07-17", tool: .claude, machineName: "installation-a", totalCost: 2),
      MachineDailyRollup(
        dateKey: "2026-07-17", tool: .claude, machineName: "installation-b", totalCost: 3),
    ]
    let labels = ["installation-a": "Laptop", "installation-b": "Laptop"]

    let totals = UsageSeriesAggregation.machineTotals(from: rollups, dateKey: "2026-07-17")

    XCTAssertEqual(
      totals.map { $0.series.displayName(machineLabels: labels) }, ["Laptop", "Laptop"])
    XCTAssertEqual(totals.map(\.series.value), ["installation-a", "installation-b"])
    XCTAssertEqual(totals.map(\.totalCost), [2, 3])
  }

  func testLabelsAreScopedToTheServerTheyCameFrom() {
    let labels = MachineLabels(
      serverURL: "http://127.0.0.1:18080",
      labels: ["installation-a": "Laptop"])

    XCTAssertEqual(
      labels.labels(forConfiguredServerURL: " http://127.0.0.1:18080/ "),
      ["installation-a": "Laptop"])
    XCTAssertEqual(labels.labels(forConfiguredServerURL: "http://192.0.2.10:18080"), [:])
    XCTAssertEqual(labels.labels(forConfiguredServerURL: ""), [:])
  }
}
