import Foundation

enum UsageSeriesAggregation {
  static func cumulativeModelSeries(from samples: [ModelUsageSample]) -> [UsageSeriesPoint] {
    let samplesByModel = Dictionary(grouping: samples) { $0.modelName }

    return samplesByModel.flatMap { modelName, samples in
      let samplesByDate = Dictionary(grouping: samples) { $0.recordedAt }
      let dates = samplesByDate.keys.sorted()
      var runningTotal = 0.0

      return dates.map { date in
        let deltaCost = samplesByDate[date, default: []].reduce(0) { total, sample in
          total + max(0, sample.deltaCost)
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
