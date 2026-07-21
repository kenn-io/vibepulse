import Foundation

enum ChartMode: String, CaseIterable, Identifiable {
  case today
  case sevenDays
  case thirtyDays

  var id: String { rawValue }

  var title: String {
    switch self {
    case .today:
      return "Today"
    case .sevenDays:
      return "7 Days"
    case .thirtyDays:
      return "30 Days"
    }
  }

  var dailyWindowDays: Int? {
    switch self {
    case .today:
      return nil
    case .sevenDays:
      return 7
    case .thirtyDays:
      return 30
    }
  }

  var usesGroupedDailyBars: Bool {
    switch self {
    case .today, .thirtyDays:
      return false
    case .sevenDays:
      return true
    }
  }
}

enum UsageAggregationMode: String, CaseIterable, Identifiable {
  case agent
  case model
  case machine

  var id: String { rawValue }

  var title: String {
    switch self {
    case .agent:
      return "Agent"
    case .model:
      return "Model"
    case .machine:
      return "Machine"
    }
  }
}

enum UsageSeriesKind: String {
  case agent
  case model
  case machine
}

struct UsageSeriesKey: Hashable, Identifiable {
  let kind: UsageSeriesKind
  let value: String

  var id: String { "\(kind.rawValue):\(value)" }

  static func agent(_ agent: UsageAgent) -> UsageSeriesKey {
    UsageSeriesKey(kind: .agent, value: agent.rawValue)
  }

  static func model(_ modelName: String) -> UsageSeriesKey {
    UsageSeriesKey(kind: .model, value: modelName)
  }

  static func machine(_ machineName: String) -> UsageSeriesKey {
    UsageSeriesKey(kind: .machine, value: machineName)
  }

  var tool: UsageAgent? {
    guard kind == .agent, !value.isEmpty else { return nil }
    return UsageAgent(value)
  }

  var displayName: String {
    switch kind {
    case .agent:
      return tool?.displayName ?? value
    case .model, .machine:
      return value
    }
  }

  var chartIdentity: String { id }

  var sortKey: String {
    switch kind {
    case .agent:
      return "000-\(tool?.displayName.lowercased() ?? value.lowercased())-\(value)"
    case .model:
      return "500-\(displayName)"
    case .machine:
      return "600-\(displayName)"
    }
  }

}

enum MaintenanceMode: String, CaseIterable, Identifiable {
  case automatic
  case manual

  var id: String { rawValue }

  var title: String {
    switch self {
    case .automatic:
      return "Automatic"
    case .manual:
      return "Manual"
    }
  }

  var detail: String {
    switch self {
    case .automatic:
      return "Runs when the app starts (at most once per day)."
    case .manual:
      return "Only runs when you click the button."
    }
  }
}

enum RefreshInterval: String, CaseIterable, Identifiable {
  case fiveMinutes = "5m"
  case fifteenMinutes = "15m"
  case oneHour = "1h"
  case fourHours = "4h"
  case oneDay = "1d"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .fiveMinutes:
      return "Every 5 minutes"
    case .fifteenMinutes:
      return "Every 15 minutes"
    case .oneHour:
      return "Every hour"
    case .fourHours:
      return "Every 4 hours"
    case .oneDay:
      return "Every day"
    }
  }

  var seconds: Int {
    switch self {
    case .fiveMinutes:
      return 5 * 60
    case .fifteenMinutes:
      return 15 * 60
    case .oneHour:
      return 60 * 60
    case .fourHours:
      return 4 * 60 * 60
    case .oneDay:
      return 24 * 60 * 60
    }
  }
}

struct DailyModelBreakdown {
  let modelName: String
  let cost: Double
}

struct DailyMachineBreakdown {
  let machineName: String
  let cost: Double
}

struct DailyTotal {
  let dateKey: String
  let cost: Double
  let modelBreakdowns: [DailyModelBreakdown]?
  let machineBreakdowns: [DailyMachineBreakdown]?

  init(
    dateKey: String,
    cost: Double,
    modelBreakdowns: [DailyModelBreakdown]? = nil,
    machineBreakdowns: [DailyMachineBreakdown]? = nil
  ) {
    self.dateKey = dateKey
    self.cost = cost
    self.modelBreakdowns = modelBreakdowns
    self.machineBreakdowns = machineBreakdowns
  }
}

struct UsageSample {
  let tool: UsageAgent
  let recordedAt: Date
  let totalCost: Double
  let deltaCost: Double
}

struct ModelUsageSample {
  let tool: UsageAgent
  let modelName: String
  let recordedAt: Date
  let totalCost: Double
  let deltaCost: Double
}

struct MachineUsageSample {
  let tool: UsageAgent
  let machineName: String
  let recordedAt: Date
  let totalCost: Double
  let deltaCost: Double
}

struct DailyRollup {
  let dateKey: String
  let tool: UsageAgent
  let totalCost: Double
}

struct ModelDailyRollup {
  let dateKey: String
  let tool: UsageAgent
  let modelName: String
  let totalCost: Double
}

struct MachineDailyRollup {
  let dateKey: String
  let tool: UsageAgent
  let machineName: String
  let totalCost: Double
}

struct UsageSeriesPoint: Identifiable {
  let id = UUID()
  let series: UsageSeriesKey
  let date: Date
  let cost: Double

  init(series: UsageSeriesKey, date: Date, cost: Double) {
    self.series = series
    self.date = date
    self.cost = cost
  }

  init(tool: UsageAgent, date: Date, cost: Double) {
    self.init(series: .agent(tool), date: date, cost: cost)
  }

  var tool: UsageAgent? { series.tool }
}

struct ToolTotal: Identifiable {
  let id = UUID()
  let series: UsageSeriesKey
  let totalCost: Double

  init(series: UsageSeriesKey, totalCost: Double) {
    self.series = series
    self.totalCost = totalCost
  }

  init(tool: UsageAgent, totalCost: Double) {
    self.init(series: .agent(tool), totalCost: totalCost)
  }

  var tool: UsageAgent? { series.tool }
}
