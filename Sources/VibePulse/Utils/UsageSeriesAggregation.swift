import Foundation

enum UsageSeriesAggregation {
  static func cumulativeModelSeries(from samples: [ModelUsageSample]) -> [UsageSeriesPoint] {
    let samplesByModel = Dictionary(grouping: samples) { $0.modelName }

    return samplesByModel.flatMap { modelName, samples in
      var latestByTool: [UsageTool: Double] = [:]
      let samplesByDate = Dictionary(grouping: samples) { $0.recordedAt }
      let dates = samplesByDate.keys.sorted()

      return dates.map { date in
        for sample in samplesByDate[date, default: []] {
          latestByTool[sample.tool] = sample.totalCost
        }
        let totalCost = latestByTool.values.reduce(0, +)
        return UsageSeriesPoint(series: .model(modelName), date: date, cost: totalCost)
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
