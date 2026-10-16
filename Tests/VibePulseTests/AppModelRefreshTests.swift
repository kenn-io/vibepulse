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
    XCTAssertEqual(fetcher.requestCount, 2)
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
    XCTAssertEqual(fetcher.requestCount, 2)

    model.agentsviewPath = "/example/agentsview"
    model.refreshIfNeeded()
    await finishRefresh(model)
    XCTAssertEqual(fetcher.requestCount, 3)
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

  func fetchMachineLabels() throws -> MachineLabels? { nil }

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
