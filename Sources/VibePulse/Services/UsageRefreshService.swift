import Foundation

struct UsageRefreshResult: Sendable {
  let discoveredAgents: [UsageAgent]
  let importErrors: [String]
}

final class UsageRefreshService: @unchecked Sendable {
  private let fetcher: UsageFetching
  private let store: UsageStore

  init(fetcher: UsageFetching, store: UsageStore) {
    self.fetcher = fetcher
    self.store = store
  }

  func refresh(todayKey: String, sampleTime: Date) throws -> UsageRefreshResult {
    let agents = try fetcher.discoverAgents().sorted()
    var errors: [String] = []

    for agent in agents {
      do {
        let totals = try fetcher.fetchDailyTotals(for: agent)
        try store.upsertDailyTotals(tool: agent, totals: totals)
        if let todayTotal = totals.first(where: {
          DateHelper.normalizedDateKey(from: $0.dateKey) == todayKey
        }) {
          try store.insertSample(
            tool: agent,
            totalCost: todayTotal.cost,
            recordedAt: sampleTime)
          if let modelBreakdowns = todayTotal.modelBreakdowns {
            try store.insertModelSamplesForRefresh(
              tool: agent,
              modelBreakdowns: modelBreakdowns,
              recordedAt: sampleTime)
          }
          if let machineBreakdowns = todayTotal.machineBreakdowns {
            try store.insertMachineSamplesForRefresh(
              tool: agent,
              machineBreakdowns: machineBreakdowns,
              recordedAt: sampleTime)
          }
        }
      } catch {
        errors.append("\(agent.displayName): \(error.localizedDescription)")
      }
    }

    return UsageRefreshResult(
      discoveredAgents: agents,
      importErrors: errors)
  }
}
