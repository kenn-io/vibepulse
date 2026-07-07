import Foundation

enum UsageSeriesAggregation {
  static func cumulativeModelSeries(from samples: [ModelUsageSample]) -> [UsageSeriesPoint] {
    let samplesByModel = Dictionary(grouping: samples) { $0.modelName }

    return samplesByModel.flatMap { modelName, samples in
      let samplesByDate = Dictionary(grouping: samples) { $0.recordedAt }
      let dates = samplesByDate.keys.sorted()
      var highWaterByTool: [UsageTool: Double] = [:]
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
}
