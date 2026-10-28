import Combine
import Foundation
import XCTest

@testable import VibePulse

final class RefreshCoordinationTests: XCTestCase {
  @MainActor
  func testRequestsDuringRefreshCoalesceIntoOneFollowup() async throws {
    let blocked = expectation(description: "second report captured")
    let fetcher = CoordinatedUsageFetcher(blocked: blocked) { _, count in count == 2 }
    defer { fetcher.resume.signal() }
    let model = try makeModel(fetcher: fetcher)
    await finishRefresh(model)

    model.refreshNow(refreshHistory: false)
    await fulfillment(of: [blocked], timeout: 3)
    model.refreshNow(refreshHistory: false)
    model.refreshNow(refreshHistory: false)
    fetcher.resume.signal()
    await finishRefresh(model)

    XCTAssertEqual(fetcher.reportContexts.count, 3)
    XCTAssertEqual(model.toolTotals.first?.totalCost, 3)
    XCTAssertNotNil(model.lastUpdated)
  }

  @MainActor
  func testQueuedManualYearRefreshSurvivesLaterMenuRefreshRequest() async throws {
    let blocked = expectation(description: "recent report blocked")
    let fetcher = CoordinatedUsageFetcher(blocked: blocked) { _, count in count == 3 }
    defer { fetcher.resume.signal() }
    let model = try makeModel(fetcher: fetcher)
    await finishRefresh(model)
    model.chartMode = .oneYear
    await finishRefresh(model)

    model.refreshNow(refreshHistory: false)
    await fulfillment(of: [blocked], timeout: 3)
    model.refreshNow()
    model.refreshNow(refreshHistory: false)
    fetcher.resume.signal()
    await finishRefresh(model)

    XCTAssertEqual(fetcher.reportContexts.map(\.includesYear), [false, true, false, true])
    XCTAssertEqual(model.toolTotals.first?.totalCost, 4)
  }

  @MainActor
  func testSelectedHistoryPublishesBeforeOtherHistoryCompletes() async throws {
    for selected in [true, false] {
      let blocked = expectation(description: "inactive history blocked")
      let fetcher = CoordinatedUsageFetcher(blocked: blocked) { context, _ in
        context.includeAutomated != selected
      }
      defer { fetcher.resume.signal() }
      let model = try makeModel(
        fetcher: fetcher, serverURL: "https://example.com", includeAutomated: selected)
      await fulfillment(of: [blocked], timeout: 3)

      XCTAssertTrue(model.isRefreshing)
      XCTAssertEqual(model.toolTotals.first?.totalCost, selected ? 1 : 10)
      XCTAssertEqual(fetcher.reportContexts.first?.includeAutomated, selected)
      fetcher.resume.signal()
      await finishRefresh(model)
      model.includeAutomatedSessions.toggle()
      XCTAssertEqual(model.toolTotals.first?.totalCost, selected ? 10 : 1)
    }
  }

  @MainActor
  func testSlowMachineLabelsDoNotDelayEitherHistory() async throws {
    let blocked = expectation(description: "labels blocked")
    let fetcher = CoordinatedUsageFetcher(labelsBlocked: blocked)
    defer { fetcher.resume.signal() }
    let model = try makeModel(fetcher: fetcher, serverURL: "https://example.com")
    await fulfillment(of: [blocked], timeout: 3)
    await finishRefresh(model)

    XCTAssertEqual(model.toolTotals.first?.totalCost, 1)
    model.includeAutomatedSessions = false
    XCTAssertEqual(model.toolTotals.first?.totalCost, 10)
    XCTAssertEqual(fetcher.labelRequestCount, 1)
    XCTAssertNil(model.statusMessage)
    model.refreshNow()
    await finishRefresh(model)
    XCTAssertEqual(model.toolTotals.first?.totalCost, 20)
    XCTAssertEqual(fetcher.labelRequestCount, 1)
    let labeled = expectation(description: "labels published independently")
    let subscription = model.$machineLabelSnapshot.compactMap { $0 }.first().sink { _ in
      labeled.fulfill()
    }
    fetcher.resume.signal()
    await fulfillment(of: [labeled], timeout: 3)
    XCTAssertEqual(model.machineLabels, ["example-machine": "Laptop"])
    withExtendedLifetime(subscription) {}
  }

  @MainActor
  func testChangingSourceDiscardsInFlightReportAndRefreshesNewSource() async throws {
    for (setting, newSource) in [
      (\AppModel.agentsviewServerURL, "https://other.example"),
      (\AppModel.agentsviewPath, "/example/agentsview"),
    ] {
      let blocked = expectation(description: "old source report blocked")
      let fetcher = CoordinatedUsageFetcher(blocked: blocked) { _, count in count == 2 }
      defer { fetcher.resume.signal() }
      let model = try makeModel(fetcher: fetcher)
      await finishRefresh(model)
      model.refreshNow()
      await fulfillment(of: [blocked], timeout: 3)

      var published: [Double] = []
      model[keyPath: setting] = newSource
      let subscription = model.$toolTotals.sink { published += $0.map(\.totalCost) }
      XCTAssertTrue(model.toolTotals.isEmpty)
      model.chartMode = .oneYear
      XCTAssertTrue(model.toolTotals.isEmpty)
      fetcher.resume.signal()
      await finishRefresh(model)

      XCTAssertFalse(published.contains(2), "Obsolete results must never reach the new source's UI")
      XCTAssertEqual(model.toolTotals.first?.totalCost, 100)
      XCTAssertNotNil(model.lastUpdated)
      withExtendedLifetime(subscription) {}
    }
  }

  @MainActor
  func testRestoringSourceDuringRefreshStillDiscardsObsoleteResult() async throws {
    let blocked = expectation(description: "old report blocked")
    let fetcher = CoordinatedUsageFetcher(blocked: blocked) { _, count in count == 2 }
    defer { fetcher.resume.signal() }
    let model = try makeModel(fetcher: fetcher)
    await finishRefresh(model)
    model.refreshNow()
    await fulfillment(of: [blocked], timeout: 3)

    model.agentsviewServerURL = "https://other.example"
    model.agentsviewServerURL = ""
    var published: [Double] = []
    let subscription = model.$toolTotals.sink { published += $0.map(\.totalCost) }
    fetcher.resume.signal()
    await finishRefresh(model)

    XCTAssertFalse(published.contains(2))
    XCTAssertEqual(model.toolTotals.first?.totalCost, 3)
    XCTAssertEqual(fetcher.reportContexts.count, 3)
    withExtendedLifetime(subscription) {}
  }

  @MainActor
  func testOldMachineLabelsCannotReplaceNewSourceLabels() async throws {
    let blocked = expectation(description: "old source labels blocked")
    let fetcher = CoordinatedUsageFetcher(labelsBlocked: blocked)
    defer { fetcher.resume.signal() }
    let model = try makeModel(fetcher: fetcher, serverURL: "https://example.com")
    await fulfillment(of: [blocked], timeout: 3)
    await finishRefresh(model)

    model.agentsviewServerURL = "https://other.example"
    model.refreshNow()
    await finishRefresh(model)
    XCTAssertEqual(model.toolTotals.first?.totalCost, 100)
    var labelSources: [String] = []
    let labeled = expectation(description: "new source labels published")
    let subscription = model.$machineLabelSnapshot.compactMap { $0 }.sink { snapshot in
      labelSources.append(snapshot.serverURL)
      labeled.fulfill()
    }
    fetcher.resume.signal()
    await fulfillment(of: [labeled], timeout: 3)
    XCTAssertEqual(labelSources, ["https://other.example"])
    XCTAssertEqual(fetcher.labelRequestCount, 2)
    withExtendedLifetime(subscription) {}
  }

  @MainActor
  func testFailedNewSourceDoesNotRestoreOldHistory() async throws {
    let fetcher = CoordinatedUsageFetcher(failingServerURL: "https://other.example")
    let model = try makeModel(fetcher: fetcher)
    await finishRefresh(model)
    model.chartMode = .oneYear
    await finishRefresh(model)
    XCTAssertEqual(model.monthlySeries.count, 2)
    model.chartMode = .today

    model.agentsviewServerURL = "https://other.example"
    model.refreshNow()
    await finishRefresh(model)
    model.chartMode = .today
    model.chartMode = .oneYear
    await finishRefresh(model)

    XCTAssertTrue(model.cumulativeSeries.isEmpty)
    XCTAssertTrue(model.dailySeries.isEmpty)
    XCTAssertTrue(model.monthlySeries.isEmpty)
    XCTAssertNotNil(model.statusMessage)
    XCTAssertNil(model.lastUpdated)
  }

  @MainActor
  func testRestartAfterSourceChangeCannotRestorePreviousSourceCache() async throws {
    let suite = "VibePulseTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: "hasSeenWelcome")
    defaults.set("manual", forKey: "maintenanceMode")
    let store = try UsageStore(path: ":memory:")
    let fetcher = CoordinatedUsageFetcher(failingServerURL: "https://other.example")
    let model = AppModel(defaults: defaults, store: store, fetcher: fetcher)
    await finishRefresh(model)
    XCTAssertEqual(model.toolTotals.first?.totalCost, 1)
    model.agentsviewServerURL = "https://other.example"

    let reopened = AppModel(defaults: defaults, store: store, fetcher: fetcher)
    XCTAssertTrue(reopened.toolTotals.isEmpty)
    await finishRefresh(reopened)
    XCTAssertTrue(reopened.cumulativeSeries.isEmpty)
    XCTAssertTrue(reopened.dailySeries.isEmpty)
    XCTAssertNil(store.dailyTotal(for: UsageDateContext().todayKey, tool: .codex))
  }

  @MainActor
  private func makeModel(
    fetcher: UsageFetching, serverURL: String = "", includeAutomated: Bool = true
  ) throws -> AppModel {
    let suite = "VibePulseTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: "hasSeenWelcome")
    defaults.set("manual", forKey: "maintenanceMode")
    defaults.set("1d", forKey: "refreshInterval")
    defaults.set(serverURL, forKey: "agentsviewServerURL")
    defaults.set(includeAutomated, forKey: "includeAutomatedSessions")
    return AppModel(
      defaults: defaults, store: try UsageStore(path: ":memory:"),
      nonAutomatedStore: try UsageStore(path: ":memory:"), fetcher: fetcher)
  }

  @MainActor
  private func finishRefresh(_ model: AppModel) async {
    let finished = expectation(description: "usage refresh completed")
    let subscription = model.$isRefreshing.filter { !$0 }.first().sink { _ in finished.fulfill() }
    await fulfillment(of: [finished], timeout: 3)
    withExtendedLifetime(subscription) {}
  }
}

private final class CoordinatedUsageFetcher: UsageFetching, @unchecked Sendable {
  let resume = DispatchSemaphore(value: 0)
  private let lock = NSLock()
  private var contexts: [UsageDateContext] = []
  private var labels = 0
  private let blocked: XCTestExpectation?
  private let labelsBlocked: XCTestExpectation?
  private let failingServerURL: String?
  private let blockReport: (UsageDateContext, Int) -> Bool

  init(
    blocked: XCTestExpectation? = nil, labelsBlocked: XCTestExpectation? = nil,
    failingServerURL: String? = nil,
    blockReport: @escaping (UsageDateContext, Int) -> Bool = { _, _ in false }
  ) {
    self.blocked = blocked
    self.labelsBlocked = labelsBlocked
    self.failingServerURL = failingServerURL
    self.blockReport = blockReport
  }

  var reportContexts: [UsageDateContext] { lock.withLock { contexts } }
  var labelRequestCount: Int { lock.withLock { labels } }

  func discoverAgents(using context: UsageDateContext) throws -> [UsageAgent] {
    if context.serverURL == failingServerURL { throw UsageFetcher.FetchError.invalidOutput }
    return [.codex]
  }

  func fetchDailyTotals(for tool: UsageAgent, using context: UsageDateContext) throws
    -> [DailyTotal]
  {
    let count = lock.withLock {
      contexts.append(context)
      return contexts.filter { $0.includeAutomated == context.includeAutomated }.count
    }
    if blockReport(context, count) {
      blocked?.fulfill()
      guard resume.wait(timeout: .now() + 10) == .success else {
        throw UsageFetcher.FetchError.invalidOutput
      }
    }
    let isNewSource =
      context.serverURL == "https://other.example"
      || context.agentsviewPath == "/example/agentsview"
    let cost = isNewSource ? 100 : Double(count) * (context.includeAutomated ? 1 : 10)
    var totals = [DailyTotal(dateKey: context.todayKey, cost: cost)]
    if context.includesYear {
      totals.append(DailyTotal(dateKey: context.usageWindowStartKey, cost: cost))
    }
    return totals
  }

  func fetchMachineLabels(using context: UsageDateContext) throws -> MachineLabels? {
    let count = lock.withLock {
      labels += 1
      return labels
    }
    if count == 1, let labelsBlocked {
      labelsBlocked.fulfill()
      guard resume.wait(timeout: .now() + 10) == .success else {
        throw UsageFetcher.FetchError.invalidOutput
      }
    }
    return MachineLabels(serverURL: context.serverURL, labels: ["example-machine": "Laptop"])
  }
}
