import XCTest

@testable import VibePulse

final class UsageRefreshServiceTests: XCTestCase {
  func testRefreshImportsEveryDiscoveredAgent() throws {
    let first = UsageAgent("future-agent")
    let second = UsageAgent("other-agent")
    let fetcher = StubUsageFetcher(
      discoveredAgents: [first, second],
      totalsByAgent: [
        first: [DailyTotal(dateKey: "2026-07-17", cost: 2)],
        second: [DailyTotal(dateKey: "2026-07-17", cost: 3)],
      ])
    let store = try UsageStore(path: ":memory:")
    let service = UsageRefreshService(fetcher: fetcher, store: store)
    let context = testContext()

    let result = try service.refresh(context: context)

    XCTAssertEqual(result.discoveredAgents, [first, second].sorted())
    XCTAssertEqual(fetcher.requestedAgents, [first, second])
    XCTAssertEqual(store.dailyTotal(for: "2026-07-17", tool: first), 2)
    XCTAssertEqual(store.dailyTotal(for: "2026-07-17", tool: second), 3)
    XCTAssertEqual(result.importErrors, [])
  }

  func testRefreshReplacesMissingRollupsForSuccessfulAgent() throws {
    let agent = UsageAgent("future-agent")
    let context = testContext()
    let staleDate = context.calendar.date(byAdding: .day, value: -1, to: context.startOfToday)!
    let staleDateKey = DateHelper.dateKey(for: staleDate, in: context.timeZone)
    let fetcher = StubUsageFetcher(
      discoveredAgents: [agent],
      totalsByAgent: [
        agent: [
          DailyTotal(
            dateKey: context.todayKey,
            cost: 7,
            modelBreakdowns: [DailyModelBreakdown(modelName: "new-model", cost: 7)],
            machineBreakdowns: [DailyMachineBreakdown(machineName: "new-machine", cost: 7)])
        ]
      ])
    let store = try UsageStore(path: ":memory:")
    try store.upsertDailyTotals(
      tool: agent,
      totals: [
        DailyTotal(
          dateKey: staleDateKey,
          cost: 3,
          modelBreakdowns: [DailyModelBreakdown(modelName: "old-model", cost: 3)],
          machineBreakdowns: [DailyMachineBreakdown(machineName: "old-machine", cost: 3)])
      ],
      dateContext: context)
    let service = UsageRefreshService(fetcher: fetcher, store: store)

    let result = try service.refresh(context: context)

    XCTAssertEqual(result.importErrors, [])
    XCTAssertEqual(
      store.fetchDailyRollups(
        since: context.usageWindowStartKey,
        through: context.todayKey,
        timeZone: context.timeZone
      )
      .map(\.dateKey),
      [context.todayKey])
    XCTAssertEqual(
      store.fetchModelDailyRollups(
        since: context.usageWindowStartKey,
        through: context.todayKey,
        tools: [agent],
        timeZone: context.timeZone
      )
      .map(\.modelName),
      ["new-model"])
    XCTAssertEqual(
      store.fetchMachineDailyRollups(
        since: context.usageWindowStartKey,
        through: context.todayKey,
        tools: [agent],
        timeZone: context.timeZone
      )
      .map(\.machineName),
      ["new-machine"])
  }

  func testRefreshClearsCurrentDaySnapshotsWhenTodayIsAbsent() throws {
    let agent = UsageAgent("future-agent")
    let context = testContext()
    let fetcher = StubUsageFetcher(
      discoveredAgents: [agent],
      totalsByAgent: [
        agent: [DailyTotal(dateKey: "2026-07-16", cost: 2)]
      ])
    let store = try UsageStore(path: ":memory:")
    try store.insertSample(
      tool: agent,
      totalCost: 10,
      recordedAt: context.now,
      dateContext: context)
    try store.insertModelSamplesForRefresh(
      tool: agent,
      modelBreakdowns: [DailyModelBreakdown(modelName: "model", cost: 10)],
      recordedAt: context.now,
      dateContext: context)
    try store.insertMachineSamplesForRefresh(
      tool: agent,
      machineBreakdowns: [DailyMachineBreakdown(machineName: "machine", cost: 10)],
      recordedAt: context.now,
      dateContext: context)
    let service = UsageRefreshService(fetcher: fetcher, store: store)

    let result = try service.refresh(context: context)

    XCTAssertEqual(result.importErrors, [])
    XCTAssertTrue(
      store.fetchSamples(tool: agent, from: context.startOfToday, to: context.now).isEmpty)
    XCTAssertTrue(
      store.fetchModelSamples(
        tools: [agent], from: context.startOfToday, to: context.now
      ).isEmpty)
    XCTAssertTrue(
      store.fetchMachineSamples(
        tools: [agent], from: context.startOfToday, to: context.now
      ).isEmpty)
  }

  func testRefreshContinuesAfterOneAgentImportFails() throws {
    let failed = UsageAgent("failed-agent")
    let successful = UsageAgent("successful-agent")
    let fetcher = StubUsageFetcher(
      discoveredAgents: [failed, successful],
      totalsByAgent: [successful: [DailyTotal(dateKey: "2026-07-17", cost: 3)]],
      failingAgents: [failed])
    let store = try UsageStore(path: ":memory:")
    let service = UsageRefreshService(fetcher: fetcher, store: store)
    let context = testContext()

    let result = try service.refresh(context: context)

    XCTAssertEqual(fetcher.requestedAgents, [failed, successful])
    XCTAssertEqual(store.dailyTotal(for: "2026-07-17", tool: successful), 3)
    XCTAssertEqual(result.importErrors.count, 1)
    XCTAssertTrue(result.importErrors[0].hasPrefix("Failed Agent:"))
  }

  func testInvalidationClearsRollupsBeforeFailedAgentImport() throws {
    let agent = UsageAgent("failed-agent")
    let context = testContext()
    let fetcher = StubUsageFetcher(
      discoveredAgents: [agent],
      failingAgents: [agent])
    let store = try UsageStore(path: ":memory:")
    try store.upsertDailyTotals(
      tool: agent,
      totals: [
        DailyTotal(
          dateKey: context.todayKey,
          cost: 3,
          modelBreakdowns: [DailyModelBreakdown(modelName: "old-model", cost: 3)],
          machineBreakdowns: [DailyMachineBreakdown(machineName: "old-machine", cost: 3)])
      ],
      dateContext: context)
    let service = UsageRefreshService(fetcher: fetcher, store: store)

    let result = try service.refresh(context: context, invalidateCurrentDay: true)

    XCTAssertEqual(result.importErrors.count, 1)
    XCTAssertTrue(
      store.fetchDailyRollups(
        since: context.usageWindowStartKey,
        through: context.todayKey,
        timeZone: context.timeZone
      ).isEmpty)
    XCTAssertTrue(
      store.fetchModelDailyRollups(
        since: context.usageWindowStartKey,
        through: context.todayKey,
        tools: [agent],
        timeZone: context.timeZone
      ).isEmpty)
    XCTAssertTrue(
      store.fetchMachineDailyRollups(
        since: context.usageWindowStartKey,
        through: context.todayKey,
        tools: [agent],
        timeZone: context.timeZone
      ).isEmpty)
  }

  func testDiscoveryFailurePreventsImports() throws {
    let fetcher = StubUsageFetcher(discoveryError: StubError.discoveryFailed)
    let store = try UsageStore(path: ":memory:")
    let service = UsageRefreshService(fetcher: fetcher, store: store)

    XCTAssertThrowsError(
      try service.refresh(context: testContext()))
    XCTAssertEqual(fetcher.requestedAgents, [])
  }

  func testRefreshInvalidatesCurrentDayBeforeImportingNewTotals() throws {
    let agent = UsageAgent("future-agent")
    let context = testContext()
    let fetcher = StubUsageFetcher(
      discoveredAgents: [agent],
      totalsByAgent: [agent: [DailyTotal(dateKey: context.todayKey, cost: 7)]])
    let store = try UsageStore(path: ":memory:")
    try store.insertSample(
      tool: agent,
      totalCost: 100,
      recordedAt: context.now,
      dateContext: UsageDateContext(
        now: context.now,
        timeZone: TimeZone(identifier: "UTC")!))
    let service = UsageRefreshService(fetcher: fetcher, store: store)

    _ = try service.refresh(context: context, invalidateCurrentDay: true)

    let samples = store.fetchSamples(
      tool: agent, from: context.startOfToday, to: context.now)
    XCTAssertEqual(samples.map(\.totalCost), [7])
  }

  func testRefreshFetchesMachineLabelsOncePerCycle() throws {
    let labels = MachineLabels(
      serverURL: "http://127.0.0.1:18080",
      labels: ["installation-a": "Laptop"])
    let fetcher = StubUsageFetcher(
      discoveredAgents: [UsageAgent("future-agent"), UsageAgent("other-agent")],
      machineLabels: labels)
    let service = UsageRefreshService(fetcher: fetcher, store: try UsageStore(path: ":memory:"))

    let result = try service.refresh(context: testContext())

    XCTAssertEqual(result.machineLabels, labels)
    XCTAssertEqual(fetcher.machineLabelRequestCount, 1)
  }

  func testCLIRefreshDisplaysMachineLabelAndPreservesIdentity() throws {
    let report = """
      {
        "machine_labels": {"installation-a": "Laptop"},
        "daily": [{
          "date": "2026-07-17",
          "totalCost": 7,
          "agentBreakdowns": [{"agent": "claude", "cost": 7}],
          "machineBreakdowns": [{"machineName": "installation-a", "cost": 7}]
        }]
      }
      """
    let fetcher = UsageFetcher(commandRunner: { _ in Data(report.utf8) })
    let store = try UsageStore(path: ":memory:")
    let service = UsageRefreshService(fetcher: fetcher, store: store)
    let context = testContext()

    let result = try service.refresh(context: context)
    let labels = result.machineLabels?.labels(forConfiguredServerURL: "") ?? [:]
    let rollups = store.fetchMachineDailyRollups(
      since: context.todayKey, tools: [.claude], timeZone: context.timeZone)
    let totals = UsageSeriesAggregation.machineTotals(from: rollups, dateKey: context.todayKey)

    XCTAssertEqual(totals.map { $0.series.displayName(machineLabels: labels) }, ["Laptop"])
    XCTAssertEqual(totals.map(\.series.value), ["installation-a"])
    XCTAssertEqual(totals.map(\.totalCost), [7])
  }

  func testRefreshImportsUsageWhenMachineLabelsAreUnavailable() throws {
    let agent = UsageAgent("future-agent")
    let fetcher = StubUsageFetcher(
      discoveredAgents: [agent],
      totalsByAgent: [agent: [DailyTotal(dateKey: "2026-07-17", cost: 2)]],
      machineLabelsError: StubError.importFailed)
    let store = try UsageStore(path: ":memory:")
    let service = UsageRefreshService(fetcher: fetcher, store: store)

    let result = try service.refresh(context: testContext())

    XCTAssertNil(result.machineLabels)
    XCTAssertEqual(result.importErrors, [])
    XCTAssertEqual(store.dailyTotal(for: "2026-07-17", tool: agent), 2)
  }

  private func testContext() -> UsageDateContext {
    UsageDateContext(
      now: ISO8601DateFormatter().date(from: "2026-07-17T12:00:00Z")!,
      timeZone: TimeZone(identifier: "UTC")!)
  }
}

private enum StubError: LocalizedError {
  case discoveryFailed
  case importFailed

  var errorDescription: String? {
    switch self {
    case .discoveryFailed: return "discovery failed"
    case .importFailed: return "import failed"
    }
  }
}

private final class StubUsageFetcher: UsageFetching, @unchecked Sendable {
  private let discoveredAgents: [UsageAgent]
  private let totalsByAgent: [UsageAgent: [DailyTotal]]
  private let failingAgents: Set<UsageAgent>
  private let discoveryError: Error?
  private let machineLabels: MachineLabels?
  private let machineLabelsError: Error?
  private(set) var machineLabelRequestCount = 0
  private(set) var requestedAgents: [UsageAgent] = []
  private(set) var requestedTimeZones: [String] = []

  init(
    discoveredAgents: [UsageAgent] = [],
    totalsByAgent: [UsageAgent: [DailyTotal]] = [:],
    failingAgents: Set<UsageAgent> = [],
    discoveryError: Error? = nil,
    machineLabels: MachineLabels? = nil,
    machineLabelsError: Error? = nil
  ) {
    self.discoveredAgents = discoveredAgents
    self.totalsByAgent = totalsByAgent
    self.failingAgents = failingAgents
    self.discoveryError = discoveryError
    self.machineLabels = machineLabels
    self.machineLabelsError = machineLabelsError
  }

  func fetchMachineLabels() throws -> MachineLabels? {
    machineLabelRequestCount += 1
    if let machineLabelsError { throw machineLabelsError }
    return machineLabels
  }

  func discoverAgents(using context: UsageDateContext) throws -> [UsageAgent] {
    requestedTimeZones.append(context.timeZone.identifier)
    if let discoveryError { throw discoveryError }
    return discoveredAgents
  }

  func fetchDailyTotals(for tool: UsageAgent, using context: UsageDateContext) throws
    -> [DailyTotal]
  {
    requestedTimeZones.append(context.timeZone.identifier)
    requestedAgents.append(tool)
    if failingAgents.contains(tool) { throw StubError.importFailed }
    return totalsByAgent[tool] ?? []
  }
}
