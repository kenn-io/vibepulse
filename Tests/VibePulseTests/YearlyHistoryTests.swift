import Combine
import SwiftUI
import XCTest

@testable import VibePulse

final class YearlyHistoryTests: XCTestCase {
  func testYearStartsElevenCalendarMonthsBeforeCurrentMonth() throws {
    let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2024-03-01T01:00:00Z"))
    let context = UsageDateContext(
      now: now, timeZone: TimeZone(identifier: "America/Los_Angeles")!, includesYear: true)

    XCTAssertEqual(context.todayKey, "2024-02-29")
    XCTAssertEqual(context.usageWindowStartKey, "2023-03-01")
    XCTAssertEqual(DateHelper.dateKey(for: context.yearEnd, in: context.timeZone), "2024-03-01")
  }

  func testMonthlyTotalsKeepSeriesSeparateAndExcludeDatesOutsideTheYear() throws {
    let formatter = ISO8601DateFormatter()
    let now = try XCTUnwrap(formatter.date(from: "2026-08-22T12:00:00Z"))
    let context = UsageDateContext(
      now: now, timeZone: TimeZone(secondsFromGMT: 0)!, includesYear: true)
    let inputs: [(String, UsageAgent, Double)] = [
      ("2025-08-31T00:00:00Z", .codex, 100),
      ("2025-09-01T00:00:00Z", .codex, 2),
      ("2025-09-30T00:00:00Z", .codex, 3),
      ("2025-09-15T00:00:00Z", .claude, 7),
      ("2026-08-22T00:00:00Z", .codex, 11),
      ("2026-08-23T00:00:00Z", .codex, 200),
    ]
    let points = try inputs.map { date, agent, cost in
      UsageSeriesPoint(tool: agent, date: try XCTUnwrap(formatter.date(from: date)), cost: cost)
    }

    let monthly = UsageSeriesAggregation.monthlySeries(from: points, context: context)

    XCTAssertEqual(
      monthly.map { DateHelper.dateKey(for: $0.date, in: context.timeZone) },
      ["2025-09-01", "2025-09-01", "2026-08-01"])
    XCTAssertEqual(monthly.map(\.tool), [.claude, .codex, .codex])
    XCTAssertEqual(monthly.map(\.cost), [7, 5, 11])
  }

  @MainActor
  func testMonthlyHoverUsesTheAggregationTimezoneAtMonthBoundaries() throws {
    let formatter = ISO8601DateFormatter()
    let now = try XCTUnwrap(formatter.date(from: "2026-03-22T12:00:00Z"))
    for zone in ["America/Los_Angeles", "Pacific/Kiritimati"] {
      let context = UsageDateContext(
        now: now, timeZone: TimeZone(identifier: zone)!, includesYear: true)
      let february = try XCTUnwrap(DateHelper.date(fromKey: "2026-02-28", in: context.timeZone))
      let march = try XCTUnwrap(DateHelper.date(fromKey: "2026-03-01", in: context.timeZone))
      let monthly = UsageSeriesAggregation.monthlySeries(
        from: [
          UsageSeriesPoint(tool: .codex, date: february, cost: 7),
          UsageSeriesPoint(tool: .codex, date: march, cost: 11),
        ], context: context)
      let chart = UsageChartView(
        mode: .oneYear, dateContext: context, cumulativeSeries: [], historySeries: monthly,
        palette: UsageSeriesPalette(series: [.agent(.codex)]), machineLabels: [:])

      XCTAssertEqual(chart.historyPoints(at: march.addingTimeInterval(-60)).map(\.cost), [7], zone)
      XCTAssertEqual(chart.historyPoints(at: march.addingTimeInterval(60)).map(\.cost), [11], zone)
    }
  }

  @MainActor
  func testSelectingYearImportsOlderAgentsAndReusesHistoryDuringRecentRefreshes() async throws {
    let (model, fetcher) = try makeModel()
    await finishRefresh(model)
    XCTAssertEqual(fetcher.yearRequests, 0)

    model.chartMode = .oneYear
    await finishRefresh(model)
    XCTAssertEqual(fetcher.yearRequests, 2)
    XCTAssertEqual(model.monthlySeries.reduce(0) { $0 + $1.cost }, 15)
    XCTAssertEqual(model.modelMonthlySeries.reduce(0) { $0 + $1.cost }, 15)
    XCTAssertEqual(model.machineMonthlySeries.reduce(0) { $0 + $1.cost }, 15)

    model.chartMode = .today
    model.chartMode = .oneYear
    model.refreshIfNeeded()
    await finishRefresh(model)
    XCTAssertEqual(fetcher.yearRequests, 2)

    model.refreshNow(refreshHistory: false)
    await finishRefresh(model)
    XCTAssertEqual(fetcher.yearRequests, 2)
    XCTAssertEqual(model.monthlySeries.reduce(0) { $0 + $1.cost }, 15)

    model.setAgent(UsageAgent("older-agent"), enabled: false)
    XCTAssertEqual(model.monthlySeries.reduce(0) { $0 + $1.cost }, 12)

    model.refreshNow()
    await finishRefresh(model)
    XCTAssertEqual(fetcher.yearRequests, 4)
  }

  @MainActor
  func testRecentRefreshClearsDisappearedUsageWhilePreservingOlderHistory() async throws {
    let (model, fetcher) = try makeModel()
    await finishRefresh(model)
    model.chartMode = .oneYear
    await finishRefresh(model)
    XCTAssertEqual(model.toolTotals.reduce(0) { $0 + $1.totalCost }, 2)
    XCTAssertFalse(model.cumulativeSeries.isEmpty)
    XCTAssertFalse(model.modelCumulativeSeries.isEmpty)
    XCTAssertFalse(model.machineCumulativeSeries.isEmpty)

    fetcher.removeRecentUsage()
    model.refreshNow(refreshHistory: false)
    await finishRefresh(model)

    XCTAssertNil(model.statusMessage)
    XCTAssertEqual(model.toolTotals.reduce(0) { $0 + $1.totalCost }, 0)
    XCTAssertTrue(model.modelTotals.isEmpty)
    XCTAssertTrue(model.machineTotals.isEmpty)
    XCTAssertTrue(model.cumulativeSeries.isEmpty)
    XCTAssertTrue(model.modelCumulativeSeries.isEmpty)
    XCTAssertTrue(model.machineCumulativeSeries.isEmpty)
    XCTAssertEqual(model.monthlySeries.reduce(0) { $0 + $1.cost }, 13)
    XCTAssertEqual(model.modelMonthlySeries.reduce(0) { $0 + $1.cost }, 13)
    XCTAssertEqual(model.machineMonthlySeries.reduce(0) { $0 + $1.cost }, 13)
    XCTAssertEqual(fetcher.yearRequests, 2)
  }

  @MainActor
  func testDeletedYearHistoryDoesNotReturnWhenAnAgentBecomesActiveAgain() async throws {
    let (model, fetcher) = try makeModel()
    await finishRefresh(model)
    model.chartMode = .oneYear
    await finishRefresh(model)
    XCTAssertEqual(model.monthlySeries.reduce(0) { $0 + $1.cost }, 15)

    fetcher.removeCodexUsage()
    fetcher.failNextYearDiscovery()
    model.refreshNow()
    await finishRefresh(model)
    XCTAssertNotNil(model.statusMessage)
    XCTAssertEqual(model.monthlySeries.reduce(0) { $0 + $1.cost }, 15)

    model.refreshNow()
    await finishRefresh(model)
    XCTAssertNil(model.statusMessage)
    XCTAssertEqual(model.discoveredAgents, [UsageAgent("older-agent")])
    XCTAssertEqual(model.monthlySeries.reduce(0) { $0 + $1.cost }, 3)

    fetcher.recordRecentUsage(cost: 5)
    model.refreshNow(refreshHistory: false)
    await finishRefresh(model)

    XCTAssertNil(model.statusMessage)
    XCTAssertEqual(model.monthlySeries.reduce(0) { $0 + $1.cost }, 8)
    XCTAssertEqual(model.modelMonthlySeries.reduce(0) { $0 + $1.cost }, 8)
    XCTAssertEqual(model.machineMonthlySeries.reduce(0) { $0 + $1.cost }, 8)
    XCTAssertEqual(model.cumulativeSeries.map(\.cost), [5])
    XCTAssertEqual(model.modelCumulativeSeries.map(\.cost), [5])
    XCTAssertEqual(model.machineCumulativeSeries.map(\.cost), [5])
    XCTAssertEqual(fetcher.yearRequests, 3)
  }

  @MainActor
  func testSelectingYearDuringStartupQueuesHistoryAfterCurrentRefresh() async throws {
    let (model, fetcher) = try makeModel()
    let view = NSHostingView(
      rootView: MenuContentView()
        .environmentObject(model).environmentObject(UpdaterController()))
    view.frame = NSRect(x: 0, y: 0, width: 360, height: 440)
    view.layoutSubtreeIfNeeded()
    var views: [NSView] = [view]
    var selectedYear = false
    while let candidate = views.popLast() {
      if let picker = candidate as? NSSegmentedControl,
        let segment = (0..<picker.segmentCount).first(where: {
          picker.label(forSegment: $0) == "1 Year"
        })
      {
        picker.selectedSegment = segment
        picker.sendAction(picker.action, to: picker.target)
        selectedYear = true
        break
      }
      views.append(contentsOf: candidate.subviews)
    }
    XCTAssertTrue(selectedYear)
    await finishRefresh(model)

    XCTAssertEqual(model.chartMode, .oneYear)
    XCTAssertEqual(fetcher.yearRequests, 2)
    XCTAssertEqual(model.monthlySeries.reduce(0) { $0 + $1.cost }, 15)
  }

  @MainActor
  func testYearHistoryRenewsAfterSourceChangesAndOnANewDay() async throws {
    let (model, fetcher) = try makeModel()
    await finishRefresh(model)
    model.chartMode = .oneYear
    await finishRefresh(model)
    XCTAssertEqual(fetcher.yearRequests, 2)

    model.agentsviewServerURL = "https://example.com"
    model.refreshIfNeeded()
    await finishRefresh(model)
    XCTAssertEqual(fetcher.yearRequests, 4)

    model.refreshIfNeeded(now: UsageDateContext().startOfNextDay)
    await finishRefresh(model)
    XCTAssertEqual(fetcher.yearRequests, 6)
  }

  @MainActor
  func testFailedYearImportRetriesInsteadOfCachingIncompleteHistory() async throws {
    let (model, fetcher) = try makeModel()
    await finishRefresh(model)
    fetcher.failNextYearDiscovery()
    model.chartMode = .oneYear
    await finishRefresh(model)
    XCTAssertNotNil(model.statusMessage)
    XCTAssertEqual(fetcher.yearRequests, 0)

    model.refreshIfNeeded()
    await finishRefresh(model)
    XCTAssertNil(model.statusMessage)
    XCTAssertEqual(fetcher.yearRequests, 2)
    XCTAssertEqual(model.monthlySeries.reduce(0) { $0 + $1.cost }, 15)
  }

  @MainActor
  func testFailedManualYearRefreshRetriesTheYearEvenAfterAnEarlierSuccess() async throws {
    let (model, fetcher) = try makeModel()
    await finishRefresh(model)
    model.chartMode = .oneYear
    await finishRefresh(model)
    fetcher.failNextYearReport()
    model.refreshNow()
    await finishRefresh(model)
    XCTAssertNotNil(model.statusMessage)
    XCTAssertEqual(fetcher.yearRequests, 4)

    model.refreshIfNeeded()
    await finishRefresh(model)
    XCTAssertNil(model.statusMessage)
    XCTAssertEqual(fetcher.yearRequests, 6)
  }

  @MainActor
  private func makeModel() throws -> (AppModel, HistoryUsageFetcher) {
    let suite = "VibePulseTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: "hasSeenWelcome")
    defaults.set("manual", forKey: "maintenanceMode")
    defaults.set("5m", forKey: "refreshInterval")
    let fetcher = HistoryUsageFetcher()
    let model = AppModel(
      defaults: defaults, store: try UsageStore(path: ":memory:"), fetcher: fetcher)
    return (model, fetcher)
  }

  @MainActor
  private func finishRefresh(_ model: AppModel) async {
    while model.isRefreshing {
      let finished = expectation(description: "refresh completed")
      let subscription = model.$isRefreshing.filter { !$0 }.first().sink { _ in finished.fulfill() }
      await fulfillment(of: [finished], timeout: 3)
      withExtendedLifetime(subscription) {}
    }
  }
}

private final class HistoryUsageFetcher: UsageFetching, @unchecked Sendable {
  private let lock = NSLock()
  private var yearRequestCount = 0
  private var failYearDiscovery = false
  private var failYearReport = false
  private var recentCost: Double? = 2
  private var hasOlderCodexUsage = true
  var yearRequests: Int { lock.withLock { yearRequestCount } }

  func failNextYearDiscovery() {
    lock.withLock { failYearDiscovery = true }
  }

  func failNextYearReport() {
    lock.withLock { failYearReport = true }
  }

  func removeRecentUsage() {
    lock.withLock { recentCost = nil }
  }

  func removeCodexUsage() {
    lock.withLock {
      recentCost = nil
      hasOlderCodexUsage = false
    }
  }

  func recordRecentUsage(cost: Double) {
    lock.withLock { recentCost = cost }
  }

  func discoverAgents(using context: UsageDateContext) throws -> [UsageAgent] {
    try lock.withLock {
      if context.includesYear && failYearDiscovery {
        failYearDiscovery = false
        throw UsageFetcher.FetchError.invalidOutput
      }
      var agents: [UsageAgent] = recentCost == nil ? [] : [.codex]
      if context.includesYear {
        if hasOlderCodexUsage && agents.isEmpty { agents.append(.codex) }
        agents.append(UsageAgent("older-agent"))
      }
      return agents
    }
  }

  func fetchMachineLabels() throws -> MachineLabels? { nil }

  func fetchDailyTotals(for tool: UsageAgent, using context: UsageDateContext) throws
    -> [DailyTotal]
  {
    if context.includesYear {
      try lock.withLock {
        yearRequestCount += 1
        if failYearReport && tool == UsageAgent("older-agent") {
          failYearReport = false
          throw UsageFetcher.FetchError.invalidOutput
        }
      }
    }
    let older = context.calendar.date(byAdding: .month, value: -6, to: context.startOfToday)!
    let olderKey = DateHelper.dateKey(for: older, in: context.timeZone)
    let values: [(String, Double)] = lock.withLock {
      guard tool == .codex else { return [(olderKey, 3)] }
      var values: [(String, Double)] = hasOlderCodexUsage ? [(olderKey, 10)] : []
      if let recentCost { values.append((context.todayKey, recentCost)) }
      return values
    }
    return values.filter { $0.0 >= context.usageWindowStartKey }.map { date, cost in
      DailyTotal(
        dateKey: date, cost: cost,
        modelBreakdowns: [DailyModelBreakdown(modelName: "example-model", cost: cost)],
        machineBreakdowns: [DailyMachineBreakdown(machineName: "example-machine", cost: cost)])
    }
  }
}
