import Foundation

struct UsageRefreshResult: Sendable {
  let discoveredAgents: [UsageAgent]
  let importErrors: [String]
  let machineLabels: MachineLabels?
}

final class UsageRefreshService: @unchecked Sendable {
  private let fetcher: UsageFetching
  private let store: UsageStore

  init(fetcher: UsageFetching, store: UsageStore) {
    self.fetcher = fetcher
    self.store = store
  }

  func refresh(
    context: UsageDateContext,
    invalidateCurrentDay: Bool = false
  ) throws -> UsageRefreshResult {
    if invalidateCurrentDay {
      try store.deleteCurrentDaySamples(using: context)
      try store.deleteRefreshWindowRollups(using: context)
    }

    let agents = try fetcher.discoverAgents(using: context).sorted()
    // Labels are display-only, so a failed request must not block usage.
    let machineLabels = try? fetcher.fetchMachineLabels()
    let reports = agents.map { DailyTotalsFetch(fetcher: fetcher, agent: $0, context: context) }
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 2
    queue.addOperations(reports, waitUntilFinished: true)
    var errors: [String] = []

    // Fetches can finish in any order; imports and errors retain the agent order.
    for report in reports {
      let agent = report.agent
      do {
        let totals = try report.result!.get()
        try store.replaceDailyTotals(
          tool: agent,
          totals: totals,
          dateContext: context)
        if let todayTotal = totals.first(where: {
          DateHelper.normalizedDateKey(from: $0.dateKey, in: context.timeZone)
            == context.todayKey
        }) {
          try store.insertSample(
            tool: agent,
            totalCost: todayTotal.cost,
            recordedAt: context.now,
            dateContext: context)
          if let modelBreakdowns = todayTotal.modelBreakdowns {
            try store.insertModelSamplesForRefresh(
              tool: agent,
              modelBreakdowns: modelBreakdowns,
              recordedAt: context.now,
              dateContext: context)
          }
          if let machineBreakdowns = todayTotal.machineBreakdowns {
            try store.insertMachineSamplesForRefresh(
              tool: agent,
              machineBreakdowns: machineBreakdowns,
              recordedAt: context.now,
              dateContext: context)
          }
        } else {
          try store.deleteCurrentDaySamples(for: agent, using: context)
        }
      } catch {
        errors.append("\(agent.displayName): \(error.localizedDescription)")
      }
    }

    return UsageRefreshResult(
      discoveredAgents: agents,
      importErrors: errors,
      machineLabels: machineLabels)
  }
}

private final class DailyTotalsFetch: Operation, @unchecked Sendable {
  let agent: UsageAgent
  private let fetcher: UsageFetching
  private let context: UsageDateContext
  private let lock = NSLock()
  private var fetchedResult: Result<[DailyTotal], Error>?

  // Read only after the queue has finished all operations. This queue is never cancelled.
  var result: Result<[DailyTotal], Error>? {
    lock.withLock { fetchedResult }
  }

  init(fetcher: UsageFetching, agent: UsageAgent, context: UsageDateContext) {
    self.fetcher = fetcher
    self.agent = agent
    self.context = context
  }

  override func main() {
    let result = Result { try fetcher.fetchDailyTotals(for: agent, using: context) }
    lock.withLock { fetchedResult = result }
  }
}
