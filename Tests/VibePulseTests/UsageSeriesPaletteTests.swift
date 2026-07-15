import Foundation
import XCTest

@testable import VibePulse

final class UsageSeriesPaletteTests: XCTestCase {
  func testTenSeriesUseGrayFreeTab10InMatplotlibOrder() {
    let series = modelSeries(count: 10)

    let palette = UsageSeriesPalette(series: series)

    XCTAssertEqual(palette.family, .tab10)
    XCTAssertEqual(
      palette.orderedSeries.compactMap(palette.rgb(for:)),
      [
        UsageSeriesRGB(hex: 0x1F77B4),
        UsageSeriesRGB(hex: 0xFF7F0E),
        UsageSeriesRGB(hex: 0x2CA02C),
        UsageSeriesRGB(hex: 0xD62728),
        UsageSeriesRGB(hex: 0x9467BD),
        UsageSeriesRGB(hex: 0x8C564B),
        UsageSeriesRGB(hex: 0xE377C2),
        UsageSeriesRGB(hex: 0xBCBD22),
        UsageSeriesRGB(hex: 0x17BECF),
        UsageSeriesRGB(hex: 0xAEC7E8),
      ])
  }

  func testPaletteFamilyChangesAtElevenAndTwentyOneSeries() {
    XCTAssertEqual(UsageSeriesPalette(series: modelSeries(count: 10)).family, .tab10)
    XCTAssertEqual(UsageSeriesPalette(series: modelSeries(count: 11)).family, .tab20)
    XCTAssertEqual(UsageSeriesPalette(series: modelSeries(count: 20)).family, .tab20)
    XCTAssertEqual(
      UsageSeriesPalette(series: modelSeries(count: 21)).family,
      .tab20bAndTab20c)
  }

  func testTwentySeriesUseUniqueGrayFreeTab20Colors() {
    let palette = UsageSeriesPalette(series: modelSeries(count: 20))
    let colors = palette.orderedSeries.compactMap(palette.rgb(for:))

    XCTAssertEqual(palette.family, .tab20)
    XCTAssertEqual(Set(colors).count, 20)
    XCTAssertFalse(colors.contains(UsageSeriesRGB(hex: 0x7F7F7F)))
    XCTAssertFalse(colors.contains(UsageSeriesRGB(hex: 0xC7C7C7)))
    XCTAssertEqual(
      Array(colors.suffix(2)),
      [
        UsageSeriesRGB(hex: 0x393B79),
        UsageSeriesRGB(hex: 0x5254A3),
      ])
  }

  func testFortySeriesUseUniqueTab20bThenGrayFreeTab20cColors() {
    let palette = UsageSeriesPalette(series: modelSeries(count: 40))
    let colors = palette.orderedSeries.compactMap(palette.rgb(for:))

    XCTAssertEqual(palette.family, .tab20bAndTab20c)
    XCTAssertEqual(Set(colors).count, 40)
    for gray in [0x636363, 0x969696, 0xBDBDBD, 0xD9D9D9] as [UInt32] {
      XCTAssertFalse(colors.contains(UsageSeriesRGB(hex: gray)))
    }
    XCTAssertEqual(
      Array(colors.suffix(4)),
      [
        UsageSeriesRGB(hex: 0x1F77B4),
        UsageSeriesRGB(hex: 0xFF7F0E),
        UsageSeriesRGB(hex: 0x2CA02C),
        UsageSeriesRGB(hex: 0xD62728),
      ])
  }

  func testMoreThanFortySeriesCycleTheResolvedFortyColorPalette() throws {
    let palette = UsageSeriesPalette(series: modelSeries(count: 41))

    XCTAssertEqual(
      try XCTUnwrap(palette.rgb(for: palette.orderedSeries[40])),
      try XCTUnwrap(palette.rgb(for: palette.orderedSeries[0])))
  }

  func testCanonicalSeriesKeepThirtyDayOrderBeforeSortedTodayOnlySeries() {
    let date = Date(timeIntervalSince1970: 0)
    let modelA = UsageSeriesKey.model("model-a")
    let modelB = UsageSeriesKey.model("model-b")
    let modelC = UsageSeriesKey.model("model-c")
    let modelZ = UsageSeriesKey.model("model-z")

    let series = UsageSeriesPalette.canonicalSeries(
      thirtyDaySeries: [
        UsageSeriesPoint(series: modelZ, date: date, cost: 2),
        UsageSeriesPoint(series: modelA, date: date, cost: 1),
        UsageSeriesPoint(series: modelB, date: date, cost: 0),
      ],
      todayCumulativeSeries: [
        UsageSeriesPoint(series: modelC, date: date, cost: 3),
        UsageSeriesPoint(series: modelA, date: date, cost: 3),
      ],
      todayTotals: [
        ToolTotal(series: modelB, totalCost: 4),
        ToolTotal(series: .model("ignored-zero"), totalCost: 0),
      ])

    XCTAssertEqual(series, [modelA, modelZ, modelB, modelC])
  }

  private func modelSeries(count: Int) -> [UsageSeriesKey] {
    (0..<count).map { .model(String(format: "model-%02d", $0)) }
  }
}
