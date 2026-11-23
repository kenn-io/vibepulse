import Foundation

enum UsageSeriesAggregation {
  static func monthlySeries(from points: [UsageSeriesPoint], context: UsageDateContext)
    -> [UsageSeriesPoint]
  {
    var totals: [Date: [UsageSeriesKey: Double]] = [:]
    for point in points where point.date >= context.yearStart && point.date < context.startOfNextDay
    {
      guard let month = context.calendar.dateInterval(of: .month, for: point.date)?.start else {
        continue
      }
      totals[month, default: [:]][point.series, default: 0] += point.cost
    }
    return totals.keys.sorted().flatMap { month in
      totals[month]!.sorted { $0.key.sortKey < $1.key.sortKey }.map { series, cost in
        UsageSeriesPoint(series: series, date: month, cost: cost)
      }
    }
  }

  /// Each series' running total at every day of the last `days` days, zero-filled before its
  /// first spend, so a line per series climbs to that series' total for the window.
  static func runningDailySeries(
    from points: [UsageSeriesPoint], days: Int, context: UsageDateContext
  ) -> [UsageSeriesPoint] {
    let calendar = context.calendar
    let dayStarts = (0..<days).compactMap {
      calendar.date(byAdding: .day, value: $0 - (days - 1), to: context.startOfToday)
    }
    guard let windowStart = dayStarts.first else { return [] }

    var costByDay: [UsageSeriesKey: [Date: Double]] = [:]
    for point in points where point.date >= windowStart && point.date < context.startOfNextDay {
      costByDay[point.series, default: [:]][calendar.startOfDay(for: point.date), default: 0] +=
        point.cost
    }

    return costByDay.keys.sorted { $0.sortKey < $1.sortKey }.flatMap { series in
      var runningTotal = 0.0
      return dayStarts.map { day in
        runningTotal += costByDay[series]?[day] ?? 0
        return UsageSeriesPoint(series: series, date: day, cost: runningTotal)
      }
    }
  }

  static func cumulativeMachineSeries(from samples: [MachineUsageSample]) -> [UsageSeriesPoint] {
    let samplesByMachine = Dictionary(grouping: samples) { $0.machineName }

    return samplesByMachine.flatMap { machineName, samples in
      let samplesByDate = Dictionary(grouping: samples) { $0.recordedAt }
      let dates = samplesByDate.keys.sorted()
      var latestCostByTool: [UsageAgent: Double] = [:]
      var runningTotal = 0.0

      return dates.map { date in
        let deltaCost = samplesByDate[date, default: []].reduce(0) { total, sample in
          let previousCost = latestCostByTool[sample.tool] ?? 0
          latestCostByTool[sample.tool] = sample.totalCost
          return total + sample.totalCost - previousCost
        }
        runningTotal += deltaCost
        return UsageSeriesPoint(series: .machine(machineName), date: date, cost: runningTotal)
      }
    }
    .sorted {
      if $0.date == $1.date {
        return $0.series.sortKey < $1.series.sortKey
      }
      return $0.date < $1.date
    }
  }

  static func dailyMachineSeries(
    from rollups: [MachineDailyRollup],
    timeZone: TimeZone = .autoupdatingCurrent
  ) -> [UsageSeriesPoint] {
    let totals = Dictionary(grouping: rollups) {
      MachineDailyKey(dateKey: $0.dateKey, machineName: $0.machineName)
    }
    .mapValues { $0.reduce(0) { $0 + $1.totalCost } }

    return totals.compactMap { key, totalCost in
      guard let date = DateHelper.date(fromKey: key.dateKey, in: timeZone) else {
        return nil
      }
      return UsageSeriesPoint(
        series: .machine(key.machineName), date: date, cost: totalCost)
    }
    .sorted {
      if $0.date == $1.date {
        return $0.series.sortKey < $1.series.sortKey
      }
      return $0.date < $1.date
    }
  }

  static func machineTotals(
    from rollups: [MachineDailyRollup], dateKey: String
  ) -> [ToolTotal] {
    let totals = Dictionary(grouping: rollups.filter { $0.dateKey == dateKey }) {
      $0.machineName
    }
    .mapValues { $0.reduce(0) { $0 + $1.totalCost } }

    return totals.map { machineName, totalCost in
      ToolTotal(series: .machine(machineName), totalCost: totalCost)
    }
    .sorted { $0.series.sortKey < $1.series.sortKey }
  }

  static func cumulativeModelSeries(from samples: [ModelUsageSample]) -> [UsageSeriesPoint] {
    let samplesByModel = Dictionary(grouping: samples) { $0.modelName }

    return samplesByModel.flatMap { modelName, samples in
      let samplesByDate = Dictionary(grouping: samples) { $0.recordedAt }
      let dates = samplesByDate.keys.sorted()
      var latestCostByTool: [UsageAgent: Double] = [:]
      var runningTotal = 0.0

      return dates.map { date in
        let deltaCost = samplesByDate[date, default: []].reduce(0) { total, sample in
          let previousCost = latestCostByTool[sample.tool] ?? 0
          latestCostByTool[sample.tool] = sample.totalCost
          return total + sample.totalCost - previousCost
        }
        runningTotal += deltaCost
        return UsageSeriesPoint(series: .model(modelName), date: date, cost: runningTotal)
      }
    }
    .sorted {
      if $0.date == $1.date {
        return $0.series.sortKey < $1.series.sortKey
      }
      return $0.date < $1.date
    }
  }

  private struct MachineDailyKey: Hashable {
    let dateKey: String
    let machineName: String
  }
}
