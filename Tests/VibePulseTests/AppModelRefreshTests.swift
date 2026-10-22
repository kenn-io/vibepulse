import Combine
import SwiftUI
import XCTest

@testable import VibePulse

final class AppModelRefreshTests: XCTestCase {
  @MainActor
  func testMenuReusesFreshUsageAndManualRefreshStillFetches() async throws {
    let (model, fetcher, store) = try makeModel()
    await finishRefresh(model)
    XCTAssertEqual(fetcher.requestCount, 1)

    model.refreshIfNeeded()
    XCTAssertFalse(model.isRefreshing)
    await finishRefresh(model)
    XCTAssertEqual(fetcher.requestCount, 1)
    XCTAssertEqual(store.dailyTotal(for: UsageDateContext().todayKey, tool: .codex), 1)

    model.refreshNow()
    await finishRefresh(model)
    XCTAssertEqual(fetcher.requestCount, 2)
    XCTAssertEqual(store.dailyTotal(for: UsageDateContext().todayKey, tool: .codex), 2)
  }

  @MainActor
  func testMenuRefreshesAtIntervalBoundaryAndAfterClockMovesBackwards() async throws {
    let (model, fetcher, _) = try makeModel()
    await finishRefresh(model)
    let lastUpdated = try XCTUnwrap(
      Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 12)))
    model.lastUpdated = lastUpdated

    model.refreshIfNeeded(now: lastUpdated.addingTimeInterval(299))
    await finishRefresh(model)
    XCTAssertEqual(fetcher.requestCount, 1)

    model.refreshIfNeeded(now: lastUpdated.addingTimeInterval(300))
    await finishRefresh(model)
    XCTAssertEqual(fetcher.requestCount, 2)

    model.refreshIfNeeded(now: lastUpdated.addingTimeInterval(-1))
    await finishRefresh(model)
    XCTAssertEqual(fetcher.requestCount, 3)
  }

  @MainActor
  func testOpeningMenuUsesFreshUsageWithoutAnotherRequest() async throws {
    let (model, fetcher, _) = try makeModel()
    await finishRefresh(model)
    let view = NSHostingView(
      rootView: MenuContentView()
        .environmentObject(model)
        .environmentObject(UpdaterController()))
    view.frame = NSRect(x: 0, y: 0, width: 360, height: 480)
    view.layoutSubtreeIfNeeded()
    await finishRefresh(model)
    XCTAssertEqual(fetcher.requestCount, 1)
  }

  @MainActor
  func testSourceChangeDuringRefreshDoesNotMarkNewSourceFresh() async throws {
    let (model, fetcher, _) = try makeModel()
    model.agentsviewServerURL = "https://example.com"
    await finishRefresh(model)
    XCTAssertNil(model.lastUpdated)

    model.refreshIfNeeded()
    await finishRefresh(model)
    XCTAssertEqual(fetcher.requestCount, 3)
    XCTAssertNotNil(model.lastUpdated)
  }

  @MainActor
  func testSourceChangedAndRestoredDuringRefreshStillRequiresAnotherRequest() async throws {
    for (setting, otherSource) in [
      (\AppModel.agentsviewServerURL, "https://example.com"),
      (\AppModel.agentsviewPath, "/example/agentsview"),
    ] {
      let (model, fetcher, store) = try makeModel()
      let originalSource = model[keyPath: setting]

      // The main actor cannot complete the initial refresh until these changes finish.
      model[keyPath: setting] = otherSource
      model[keyPath: setting] = originalSource
      await finishRefresh(model)
      XCTAssertNil(model.lastUpdated)

      model.refreshIfNeeded()
      await finishRefresh(model)
      XCTAssertEqual(fetcher.requestCount, 2)
      XCTAssertEqual(store.dailyTotal(for: UsageDateContext().todayKey, tool: .codex), 2)

      model.refreshIfNeeded()
      await finishRefresh(model)
      XCTAssertEqual(fetcher.requestCount, 2)
    }
  }

  @MainActor
  func testMenuRefreshesWhenSourceChanges() async throws {
    let (model, fetcher, _) = try makeModel()
    await finishRefresh(model)
    model.agentsviewServerURL = "https://example.com"
    model.refreshIfNeeded()
    await finishRefresh(model)
    XCTAssertEqual(fetcher.requestCount, 3)

    model.agentsviewPath = "/example/agentsview"
    model.refreshIfNeeded()
    await finishRefresh(model)
    XCTAssertEqual(fetcher.requestCount, 5)
  }

  @MainActor
  func testMenuRefreshesOnNewDayBeforeIntervalExpires() async throws {
    let (model, fetcher, _) = try makeModel()
    await finishRefresh(model)
    let midnight = try XCTUnwrap(
      Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 2)))
    model.lastUpdated = midnight.addingTimeInterval(-1)

    model.refreshIfNeeded(now: midnight)
    await finishRefresh(model)
    XCTAssertEqual(fetcher.requestCount, 2)
  }

  @MainActor
  func testMenuRefreshesWhenPreviousRefreshFinishesAfterMidnight() async throws {
    let (model, fetcher, store) = try makeModel()
    await finishRefresh(model)
    model.refreshInterval = .oneDay
    let today = UsageDateContext()

    // Capture yesterday's context, then let the asynchronous refresh finish today.
    model.refreshNow(now: today.startOfToday.addingTimeInterval(-1))
    await finishRefresh(model)
    XCTAssertEqual(fetcher.requestCount, 2)

    model.refreshIfNeeded()
    await finishRefresh(model)
    XCTAssertEqual(fetcher.requestCount, 3)
    XCTAssertEqual(store.dailyTotal(for: today.todayKey, tool: .codex), 3)
    XCTAssertEqual(model.cumulativeSeries.last?.cost, 3)

    model.refreshIfNeeded()
    await finishRefresh(model)
    XCTAssertEqual(fetcher.requestCount, 3)
  }

  @MainActor
  func testMenuRetriesAfterFailedManualRefresh() async throws {
    let (model, fetcher, store) = try makeModel()
    await finishRefresh(model)
    fetcher.failNextRequest()
    model.refreshNow()
    await finishRefresh(model)
    XCTAssertNotNil(model.statusMessage)

    model.refreshIfNeeded()
    await finishRefresh(model)
    XCTAssertEqual(fetcher.requestCount, 3)
    XCTAssertNil(model.statusMessage)
    XCTAssertEqual(store.dailyTotal(for: UsageDateContext().todayKey, tool: .codex), 3)
  }

  @MainActor
  func testAutomatedSettingPersistsAndSelectsSeparateHistories() async throws {
    let suite = "VibePulseTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: "hasSeenWelcome")
    defaults.set("manual", forKey: "maintenanceMode")
    defaults.set("https://example.com", forKey: "agentsviewServerURL")
    let store = try UsageStore(path: ":memory:")
    let excludedStore = try UsageStore(path: ":memory:")
    let model = AppModel(
      defaults: defaults, store: store, nonAutomatedStore: excludedStore,
      fetcher: AutomatedUsageFetcher())
    await finishRefresh(model)
    XCTAssertTrue(model.includeAutomatedSessions)
    XCTAssertEqual(store.dailyTotal(for: UsageDateContext().todayKey, tool: .codex), 100)

    model.chartMode = .oneYear
    await finishRefresh(model)
    model.includeAutomatedSessions = false
    XCTAssertFalse(model.isRefreshing)
    XCTAssertEqual(defaults.object(forKey: "includeAutomatedSessions") as? Bool, false)
    XCTAssertEqual(excludedStore.dailyTotal(for: UsageDateContext().todayKey, tool: .codex), 10)
    XCTAssertEqual(store.dailyTotal(for: UsageDateContext().todayKey, tool: .codex), 100)
    XCTAssertEqual(model.menuTotalText, Formatters.currencyString(10))
    let oldestDate = DateHelper.dateKey(for: UsageDateContext().yearStart)
    XCTAssertEqual(excludedStore.dailyTotal(for: oldestDate, tool: .codex), 10)

    let reopened = AppModel(
      defaults: defaults, store: store, nonAutomatedStore: excludedStore,
      fetcher: AutomatedUsageFetcher())
    await finishRefresh(reopened)
    XCTAssertFalse(reopened.includeAutomatedSessions)
    XCTAssertEqual(reopened.menuTotalText, Formatters.currencyString(10))
    reopened.includeAutomatedSessions = true
    XCTAssertFalse(reopened.isRefreshing)
    XCTAssertEqual(reopened.menuTotalText, Formatters.currencyString(100))
    XCTAssertEqual(store.dailyTotal(for: oldestDate, tool: .codex), 100)
  }

  @MainActor
  func testTogglingDuringRefreshPreservesBothSampleHistories() async throws {
    let suite = "VibePulseTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: "hasSeenWelcome")
    defaults.set("manual", forKey: "maintenanceMode")
    defaults.set("https://example.com", forKey: "agentsviewServerURL")
    defaults.set(false, forKey: "includeAutomatedSessions")
    let combined = try UsageStore(path: ":memory:")
    let excluded = try UsageStore(path: ":memory:")
    let blocked = expectation(description: "combined report blocked")
    let fetcher = BlockingScopeFetcher(blocked: blocked)
    defer { fetcher.resume.signal() }
    let model = AppModel(
      defaults: defaults, store: combined,
      nonAutomatedStore: excluded, fetcher: fetcher)
    await finishRefresh(model)
    XCTAssertEqual(model.menuTotalText, Formatters.currencyString(10))

    model.refreshNow()
    await fulfillment(of: [blocked], timeout: 3)
    model.includeAutomatedSessions = true
    XCTAssertEqual(model.menuTotalText, Formatters.currencyString(100))
    model.includeAutomatedSessions = false
    XCTAssertEqual(model.menuTotalText, Formatters.currencyString(10))
    fetcher.resume.signal()
    await finishRefresh(model)

    XCTAssertEqual(model.menuTotalText, Formatters.currencyString(20))
    XCTAssertEqual(model.modelCumulativeSeries.last?.cost, 20)
    XCTAssertEqual(model.machineCumulativeSeries.last?.cost, 20)
    let context = UsageDateContext()
    XCTAssertEqual(
      excluded.fetchModelSamples(
        tools: [.codex], from: context.startOfToday,
        to: context.startOfNextDay
      ).map(\.totalCost), [10, 20])
    XCTAssertEqual(
      combined.fetchModelSamples(
        tools: [.codex], from: context.startOfToday,
        to: context.startOfNextDay
      ).map(\.totalCost), [100, 200])
    XCTAssertEqual(
      excluded.fetchMachineSamples(
        tools: [.codex], from: context.startOfToday,
        to: context.startOfNextDay
      ).map(\.totalCost), [10, 20])
    XCTAssertEqual(
      combined.fetchMachineSamples(
        tools: [.codex], from: context.startOfToday,
        to: context.startOfNextDay
      ).map(\.totalCost), [100, 200])
    model.includeAutomatedSessions = true
    XCTAssertFalse(model.isRefreshing)
    XCTAssertEqual(model.menuTotalText, Formatters.currencyString(200))
  }

  @MainActor
  func testRefreshKeepsItsServerWhenSettingsChangeMidRefresh() async throws {
    let defaults = try makeDefaults(serverURL: "https://example.com", includeAutomated: false)
    let combined = try UsageStore(path: ":memory:")
    let excluded = try UsageStore(path: ":memory:")
    let blocked = expectation(description: "combined report blocked")
    let resume = DispatchSemaphore(value: 0)
    defer { resume.signal() }
    let fetcher = ScopedUsageFetcher()
    fetcher.beforeCombinedReport = {
      blocked.fulfill()
      _ = resume.wait(timeout: .now() + 3)
    }
    let model = AppModel(
      defaults: defaults, store: combined, nonAutomatedStore: excluded, fetcher: fetcher)

    await fulfillment(of: [blocked], timeout: 3)
    model.agentsviewServerURL = ""
    resume.signal()
    await finishRefresh(model)

    XCTAssertEqual(Set(fetcher.serverURLs), ["https://example.com"])
    let today = UsageDateContext().todayKey
    XCTAssertEqual(excluded.dailyTotal(for: today, tool: .codex), 10)
    XCTAssertEqual(combined.dailyTotal(for: today, tool: .codex), 100)
  }

  @MainActor
  func testAgentMissingFromFilteredDiscoveryLosesRecentTotalsOnly() async throws {
    let defaults = try makeDefaults(serverURL: "https://example.com", includeAutomated: false)
    let combined = try UsageStore(path: ":memory:")
    let excluded = try UsageStore(path: ":memory:")
    let bot = UsageAgent("review-bot")
    let context = UsageDateContext()
    let olderKey = DateHelper.dateKey(
      for: context.calendar.date(byAdding: .day, value: -60, to: context.startOfToday)!,
      in: context.timeZone)
    try excluded.upsertDailyTotals(
      tool: bot, totals: [DailyTotal(dateKey: olderKey, cost: 3)],
      dateContext: UsageDateContext(includesYear: true))
    let fetcher = ScopedUsageFetcher(agents: [.codex, bot])
    let model = AppModel(
      defaults: defaults, store: combined, nonAutomatedStore: excluded, fetcher: fetcher)
    await finishRefresh(model)
    XCTAssertEqual(model.menuTotalText, Formatters.currencyString(15))

    fetcher.setAgents([.codex], includeAutomated: false)
    model.refreshNow(refreshHistory: false)
    await finishRefresh(model)

    XCTAssertNil(model.statusMessage)
    XCTAssertEqual(model.discoveredAgents, [.codex, bot].sorted())
    XCTAssertEqual(model.menuTotalText, Formatters.currencyString(10))
    XCTAssertNil(excluded.dailyTotal(for: context.todayKey, tool: bot))
    XCTAssertTrue(
      excluded.fetchSamples(tool: bot, from: context.startOfToday, to: Date()).isEmpty)
    XCTAssertEqual(excluded.dailyTotal(for: olderKey, tool: bot), 3)
    model.includeAutomatedSessions = true
    XCTAssertEqual(model.menuTotalText, Formatters.currencyString(150))
  }

  @MainActor
  func testTimezoneChangeInCLIModeInvalidatesBothCaches() async throws {
    let currentZone = UsageDateContext().timeZone.identifier
    let defaults = try makeDefaults(serverURL: "", includeAutomated: false)
    defaults.set(currentZone == "UTC" ? "Asia/Tokyo" : "UTC", forKey: "lastUsageTimeZone")
    let combined = try UsageStore(path: ":memory:")
    let excluded = try UsageStore(path: ":memory:")
    let context = UsageDateContext()
    for store in [combined, excluded] {
      try store.upsertDailyTotals(
        tool: .codex, totals: [DailyTotal(dateKey: context.todayKey, cost: 999)],
        dateContext: context)
      try store.insertSample(
        tool: .codex, totalCost: 999, recordedAt: context.now, dateContext: context)
    }
    let model = AppModel(
      defaults: defaults, store: combined, nonAutomatedStore: excluded,
      fetcher: ScopedUsageFetcher())
    await finishRefresh(model)

    XCTAssertEqual(combined.dailyTotal(for: context.todayKey, tool: .codex), 100)
    XCTAssertNil(excluded.dailyTotal(for: context.todayKey, tool: .codex))
    XCTAssertTrue(
      excluded.fetchSamples(tool: .codex, from: context.startOfToday, to: Date()).isEmpty)

    model.agentsviewServerURL = "https://example.com"
    model.refreshNow()
    await finishRefresh(model)
    XCTAssertEqual(
      excluded.fetchSamples(tool: .codex, from: context.startOfToday, to: Date())
        .map(\.totalCost), [10])
    XCTAssertEqual(model.menuTotalText, Formatters.currencyString(10))
  }

  @MainActor
  func testOneFailedReportStillPublishesTheOther() async throws {
    for includeAutomated in [true, false] {
      let defaults = try makeDefaults(
        serverURL: "https://example.com", includeAutomated: includeAutomated)
      let fetcher = ScopedUsageFetcher()
      // Fail the report that is not displayed.
      fetcher.setFailing(!includeAutomated)
      let model = AppModel(
        defaults: defaults, store: try UsageStore(path: ":memory:"),
        nonAutomatedStore: try UsageStore(path: ":memory:"), fetcher: fetcher)
      await finishRefresh(model)

      XCTAssertEqual(model.discoveredAgents, [.codex])
      XCTAssertEqual(
        model.menuTotalText, Formatters.currencyString(includeAutomated ? 100 : 10))
      XCTAssertNotNil(model.statusMessage)
      XCTAssertNil(model.lastUpdated)

      fetcher.setFailing(nil)
      model.refreshIfNeeded()
      await finishRefresh(model)
      XCTAssertNil(model.statusMessage)
      XCTAssertNotNil(model.lastUpdated)
      model.includeAutomatedSessions.toggle()
      XCTAssertEqual(
        model.menuTotalText, Formatters.currencyString(includeAutomated ? 10 : 100))
    }
  }

  @MainActor
  private func makeDefaults(serverURL: String, includeAutomated: Bool) throws -> UserDefaults {
    let suite = "VibePulseTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: "hasSeenWelcome")
    defaults.set("manual", forKey: "maintenanceMode")
    defaults.set(serverURL, forKey: "agentsviewServerURL")
    defaults.set(includeAutomated, forKey: "includeAutomatedSessions")
    return defaults
  }

  @MainActor
  private func makeModel() throws -> (AppModel, CountingUsageFetcher, UsageStore) {
    let suite = "VibePulseTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: "hasSeenWelcome")
    defaults.set("manual", forKey: "maintenanceMode")
    defaults.set("5m", forKey: "refreshInterval")
    let store = try UsageStore(path: ":memory:")
    let fetcher = CountingUsageFetcher()
    return (AppModel(defaults: defaults, store: store, fetcher: fetcher), fetcher, store)
  }

  @MainActor
  private func finishRefresh(_ model: AppModel) async {
    let finished = expectation(description: "refresh completed")
    let subscription = model.$isRefreshing.filter { !$0 }.first().sink { _ in
      finished.fulfill()
    }
    await fulfillment(of: [finished], timeout: 3)
    withExtendedLifetime(subscription) {}
  }
}

private final class CountingUsageFetcher: UsageFetching, @unchecked Sendable {
  private let lock = NSLock()
  private var requests = 0
  private var shouldFail = false

  var requestCount: Int { lock.withLock { requests } }

  func failNextRequest() {
    lock.withLock { shouldFail = true }
  }

  func discoverAgents(using context: UsageDateContext) throws -> [UsageAgent] { [.codex] }

  func fetchMachineLabels(using context: UsageDateContext) throws -> MachineLabels? { nil }

  func fetchDailyTotals(for tool: UsageAgent, using context: UsageDateContext) throws
    -> [DailyTotal]
  {
    try lock.withLock {
      requests += 1
      if shouldFail {
        shouldFail = false
        throw UsageFetcher.FetchError.invalidOutput
      }
      return [DailyTotal(dateKey: context.todayKey, cost: Double(requests))]
    }
  }
}

private struct AutomatedUsageFetcher: UsageFetching {
  func discoverAgents(using context: UsageDateContext) throws -> [UsageAgent] { [.codex] }
  func fetchMachineLabels(using context: UsageDateContext) throws -> MachineLabels? { nil }
  func fetchDailyTotals(for tool: UsageAgent, using context: UsageDateContext) throws
    -> [DailyTotal]
  {
    let cost: Double = context.includeAutomated ? 100 : 10
    var rows = [DailyTotal(dateKey: context.todayKey, cost: cost)]
    if context.includesYear {
      rows.append(DailyTotal(dateKey: context.usageWindowStartKey, cost: cost))
    }
    return rows
  }
}

private final class BlockingScopeFetcher: UsageFetching, @unchecked Sendable {
  let resume = DispatchSemaphore(value: 0)
  private let blocked: XCTestExpectation
  private let lock = NSLock()
  private var counts: [Bool: Int] = [:]

  init(blocked: XCTestExpectation) { self.blocked = blocked }
  func discoverAgents(using context: UsageDateContext) throws -> [UsageAgent] { [.codex] }
  func fetchMachineLabels(using context: UsageDateContext) throws -> MachineLabels? { nil }
  func fetchDailyTotals(for tool: UsageAgent, using context: UsageDateContext) throws
    -> [DailyTotal]
  {
    let count = lock.withLock {
      counts[context.includeAutomated, default: 0] += 1
      return counts[context.includeAutomated]!
    }
    if context.includeAutomated && count == 2 {
      blocked.fulfill()
      guard resume.wait(timeout: .now() + 3) == .success else {
        throw UsageFetcher.FetchError.invalidOutput
      }
    }
    let cost = Double(count) * (context.includeAutomated ? 100 : 10)
    return [
      DailyTotal(
        dateKey: context.todayKey, cost: cost,
        modelBreakdowns: [DailyModelBreakdown(modelName: "test-model", cost: cost)],
        machineBreakdowns: [DailyMachineBreakdown(machineName: "test-machine", cost: cost)])
    ]
  }
}

// Reports $10 per agent without automation and $100 with it; a second agent reports half that.
private final class ScopedUsageFetcher: UsageFetching, @unchecked Sendable {
  private let lock = NSLock()
  private var agentsByScope: [Bool: [UsageAgent]]
  private var failingScope: Bool?
  private var requestedServerURLs: [String] = []
  // Runs once, before the first report that includes automation.
  var beforeCombinedReport: (() -> Void)?

  init(agents: [UsageAgent] = [.codex]) {
    agentsByScope = [true: agents, false: agents]
  }

  var serverURLs: [String] { lock.withLock { requestedServerURLs } }

  func setAgents(_ agents: [UsageAgent], includeAutomated: Bool) {
    lock.withLock { agentsByScope[includeAutomated] = agents }
  }

  func setFailing(_ includeAutomated: Bool?) {
    lock.withLock { failingScope = includeAutomated }
  }

  func discoverAgents(using context: UsageDateContext) throws -> [UsageAgent] {
    try lock.withLock {
      requestedServerURLs.append(context.serverURL)
      if failingScope == context.includeAutomated {
        throw UsageFetcher.FetchError.invalidOutput
      }
      return agentsByScope[context.includeAutomated] ?? []
    }
  }

  func fetchMachineLabels(using context: UsageDateContext) throws -> MachineLabels? {
    lock.withLock { requestedServerURLs.append(context.serverURL) }
    return nil
  }

  func fetchDailyTotals(for tool: UsageAgent, using context: UsageDateContext) throws
    -> [DailyTotal]
  {
    let pause: (() -> Void)? = lock.withLock {
      requestedServerURLs.append(context.serverURL)
      guard context.includeAutomated else { return nil }
      defer { beforeCombinedReport = nil }
      return beforeCombinedReport
    }
    pause?()
    let cost = (tool == .codex ? 10.0 : 5.0) * (context.includeAutomated ? 10 : 1)
    return [DailyTotal(dateKey: context.todayKey, cost: cost)]
  }
}
