import Foundation
import SwiftUI

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

  var id: String { rawValue }

  var title: String {
    switch self {
    case .agent:
      return "Agent"
    case .model:
      return "Model"
    }
  }
}

enum UsageSeriesKind: String {
  case agent
  case model
}

struct UsageSeriesKey: Hashable, Identifiable {
  let kind: UsageSeriesKind
  let value: String

  var id: String { "\(kind.rawValue):\(value)" }

  static func agent(_ tool: UsageTool) -> UsageSeriesKey {
    UsageSeriesKey(kind: .agent, value: tool.rawValue)
  }

  static func model(_ modelName: String) -> UsageSeriesKey {
    UsageSeriesKey(kind: .model, value: modelName)
  }

  var tool: UsageTool? {
    guard kind == .agent else { return nil }
    return UsageTool(rawValue: value)
  }

  var displayName: String {
    switch kind {
    case .agent:
      return tool?.displayName ?? value
    case .model:
      return value
    }
  }

  var color: Color {
    switch kind {
    case .agent:
      return tool?.color ?? .secondary
    case .model:
      return Self.modelPalette[Self.paletteIndex(for: value)]
    }
  }

  var sortKey: String {
    switch kind {
    case .agent:
      let index = tool.flatMap { UsageTool.allCases.firstIndex(of: $0) } ?? 999
      return String(format: "%03d-%@", index, displayName)
    case .model:
      return "500-\(displayName)"
    }
  }

  private static let modelPalette: [Color] = [
    Color(red: 0.52, green: 0.50, blue: 0.88),
    Color(red: 0.15, green: 0.68, blue: 0.58),
    Color(red: 0.90, green: 0.48, blue: 0.38),
    Color(red: 0.62, green: 0.67, blue: 0.24),
    Color(red: 0.75, green: 0.42, blue: 0.74),
    Color(red: 0.24, green: 0.63, blue: 0.82),
    Color(red: 0.88, green: 0.62, blue: 0.24),
    Color(red: 0.45, green: 0.70, blue: 0.38),
  ]

  private static func paletteIndex(for value: String) -> Int {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in value.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 1_099_511_628_211
    }
    return Int(hash % UInt64(modelPalette.count))
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

struct DailyTotal {
  let dateKey: String
  let cost: Double
  let modelBreakdowns: [DailyModelBreakdown]

  init(dateKey: String, cost: Double, modelBreakdowns: [DailyModelBreakdown] = []) {
    self.dateKey = dateKey
    self.cost = cost
    self.modelBreakdowns = modelBreakdowns
  }
}

struct UsageSample {
  let tool: UsageTool
  let recordedAt: Date
  let totalCost: Double
  let deltaCost: Double
}

struct ModelUsageSample {
  let tool: UsageTool
  let modelName: String
  let recordedAt: Date
  let totalCost: Double
  let deltaCost: Double
}

struct DailyRollup {
  let dateKey: String
  let tool: UsageTool
  let totalCost: Double
}

struct ModelDailyRollup {
  let dateKey: String
  let tool: UsageTool
  let modelName: String
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

  init(tool: UsageTool, date: Date, cost: Double) {
    self.init(series: .agent(tool), date: date, cost: cost)
  }

  var tool: UsageTool? { series.tool }
}

struct ToolTotal: Identifiable {
  let id = UUID()
  let series: UsageSeriesKey
  let totalCost: Double

  init(series: UsageSeriesKey, totalCost: Double) {
    self.series = series
    self.totalCost = totalCost
  }

  init(tool: UsageTool, totalCost: Double) {
    self.init(series: .agent(tool), totalCost: totalCost)
  }

  var tool: UsageTool? { series.tool }
}
