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

  static func cumulativeMachineSeries(from samples: [MachineUsageSample]) -> [UsageSeriesPoint] {
    let samplesByMachine = Dictionary(grouping: samples) { $0.machineName }

    return samplesByMachine.flatMap { machineName, samples in
      let samplesByDate = Dictionary(grouping: samples) { $0.recordedAt }
      let dates = samplesByDate.keys.sorted()
      var highWaterByTool: [UsageAgent: Double] = [:]
      var runningTotal = 0.0

      return dates.map { date in
        let deltaCost = samplesByDate[date, default: []].reduce(0) { total, sample in
          let highWater = highWaterByTool[sample.tool] ?? 0
          highWaterByTool[sample.tool] = max(highWater, sample.totalCost)
          return total + max(0, sample.totalCost - highWater)
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
      var highWaterByTool: [UsageAgent: Double] = [:]
      var runningTotal = 0.0

      return dates.map { date in
        let deltaCost = samplesByDate[date, default: []].reduce(0) { total, sample in
          let highWater = highWaterByTool[sample.tool] ?? 0
          highWaterByTool[sample.tool] = max(highWater, sample.totalCost)
          return total + max(0, sample.totalCost - highWater)
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
