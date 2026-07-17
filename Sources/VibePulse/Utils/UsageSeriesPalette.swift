import SwiftUI

struct UsageSeriesRGB: Hashable {
  let red: Double
  let green: Double
  let blue: Double

  init(hex: UInt32) {
    red = Double((hex >> 16) & 0xFF) / 255
    green = Double((hex >> 8) & 0xFF) / 255
    blue = Double(hex & 0xFF) / 255
  }

  var color: Color {
    Color(red: red, green: green, blue: blue)
  }
}

struct UsageSeriesPalette {
  enum Family: Equatable {
    case tab10
    case tab20
    case tab20bAndTab20c
  }

  let family: Family
  let orderedSeries: [UsageSeriesKey]
  private let colorsBySeries: [UsageSeriesKey: UsageSeriesRGB]

  init(series: [UsageSeriesKey]) {
    var seen = Set<UsageSeriesKey>()
    orderedSeries = series.filter { seen.insert($0).inserted }

    let colors: [UsageSeriesRGB]
    if orderedSeries.count <= Self.tab10.count {
      family = .tab10
      colors = Self.tab10
    } else if orderedSeries.count <= Self.tab20.count {
      family = .tab20
      colors = Self.tab20
    } else {
      family = .tab20bAndTab20c
      colors = Self.tab20bAndTab20c
    }

    colorsBySeries = Dictionary(
      uniqueKeysWithValues: orderedSeries.enumerated().map { index, series in
        (series, colors[index % colors.count])
      })
  }

  func rgb(for series: UsageSeriesKey) -> UsageSeriesRGB? {
    colorsBySeries[series]
  }

  func color(for series: UsageSeriesKey) -> Color {
    rgb(for: series)?.color ?? .secondary
  }

  static func canonicalSeries(
    thirtyDaySeries: [UsageSeriesPoint],
    todayCumulativeSeries: [UsageSeriesPoint],
    todayTotals: [ToolTotal]
  ) -> [UsageSeriesKey] {
    let minimumCost = UsageSeriesFilters.minimumVisibleCost
    let thirtyDaySet = Set(
      thirtyDaySeries.lazy
        .filter { $0.cost > minimumCost }
        .map(\.series))
    let todaySet = Set(
      todayCumulativeSeries.lazy
        .filter { $0.cost > minimumCost }
        .map(\.series)
    ).union(
      todayTotals.lazy
        .filter { $0.totalCost > minimumCost }
        .map(\.series))

    let thirtyDay = thirtyDaySet.sorted { $0.sortKey < $1.sortKey }
    let todayOnly = todaySet.subtracting(thirtyDaySet).sorted { $0.sortKey < $1.sortKey }
    return thirtyDay + todayOnly
  }

  // Values and ordering are based on Matplotlib's qualitative tab10, tab20,
  // tab20b, and tab20c colormaps:
  // https://github.com/matplotlib/matplotlib/blob/v3.10.5/lib/matplotlib/_cm.py#L1286-L1367
  // Gray entries are omitted, leaving 9, 18, and 36 usable colors.
  private static let tab10 = [
    UsageSeriesRGB(hex: 0x1F77B4), UsageSeriesRGB(hex: 0xFF7F0E),
    UsageSeriesRGB(hex: 0x2CA02C), UsageSeriesRGB(hex: 0xD62728),
    UsageSeriesRGB(hex: 0x9467BD), UsageSeriesRGB(hex: 0x8C564B),
    UsageSeriesRGB(hex: 0xE377C2), UsageSeriesRGB(hex: 0xBCBD22),
    UsageSeriesRGB(hex: 0x17BECF),
  ]

  private static let tab20 = [
    UsageSeriesRGB(hex: 0x1F77B4), UsageSeriesRGB(hex: 0xAEC7E8),
    UsageSeriesRGB(hex: 0xFF7F0E), UsageSeriesRGB(hex: 0xFFBB78),
    UsageSeriesRGB(hex: 0x2CA02C), UsageSeriesRGB(hex: 0x98DF8A),
    UsageSeriesRGB(hex: 0xD62728), UsageSeriesRGB(hex: 0xFF9896),
    UsageSeriesRGB(hex: 0x9467BD), UsageSeriesRGB(hex: 0xC5B0D5),
    UsageSeriesRGB(hex: 0x8C564B), UsageSeriesRGB(hex: 0xC49C94),
    UsageSeriesRGB(hex: 0xE377C2), UsageSeriesRGB(hex: 0xF7B6D2),
    UsageSeriesRGB(hex: 0xBCBD22), UsageSeriesRGB(hex: 0xDBDB8D),
    UsageSeriesRGB(hex: 0x17BECF), UsageSeriesRGB(hex: 0x9EDAE5),
  ]

  private static let tab20bAndTab20c = [
    UsageSeriesRGB(hex: 0x393B79), UsageSeriesRGB(hex: 0x5254A3),
    UsageSeriesRGB(hex: 0x6B6ECF), UsageSeriesRGB(hex: 0x9C9EDE),
    UsageSeriesRGB(hex: 0x637939), UsageSeriesRGB(hex: 0x8CA252),
    UsageSeriesRGB(hex: 0xB5CF6B), UsageSeriesRGB(hex: 0xCEDB9C),
    UsageSeriesRGB(hex: 0x8C6D31), UsageSeriesRGB(hex: 0xBD9E39),
    UsageSeriesRGB(hex: 0xE7BA52), UsageSeriesRGB(hex: 0xE7CB94),
    UsageSeriesRGB(hex: 0x843C39), UsageSeriesRGB(hex: 0xAD494A),
    UsageSeriesRGB(hex: 0xD6616B), UsageSeriesRGB(hex: 0xE7969C),
    UsageSeriesRGB(hex: 0x7B4173), UsageSeriesRGB(hex: 0xA55194),
    UsageSeriesRGB(hex: 0xCE6DBD), UsageSeriesRGB(hex: 0xDE9ED6),
    UsageSeriesRGB(hex: 0x3182BD), UsageSeriesRGB(hex: 0x6BAED6),
    UsageSeriesRGB(hex: 0x9ECAE1), UsageSeriesRGB(hex: 0xC6DBEF),
    UsageSeriesRGB(hex: 0xE6550D), UsageSeriesRGB(hex: 0xFD8D3C),
    UsageSeriesRGB(hex: 0xFDAE6B), UsageSeriesRGB(hex: 0xFDD0A2),
    UsageSeriesRGB(hex: 0x31A354), UsageSeriesRGB(hex: 0x74C476),
    UsageSeriesRGB(hex: 0xA1D99B), UsageSeriesRGB(hex: 0xC7E9C0),
    UsageSeriesRGB(hex: 0x756BB1), UsageSeriesRGB(hex: 0x9E9AC8),
    UsageSeriesRGB(hex: 0xBCBDDC), UsageSeriesRGB(hex: 0xDADAEB),
  ]
}
