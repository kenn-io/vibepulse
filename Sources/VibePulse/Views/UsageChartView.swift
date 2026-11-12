import AppKit
import Charts
import SwiftUI

struct UsageChartView: View {
  let mode: ChartMode
  let dateContext: UsageDateContext
  let cumulativeSeries: [UsageSeriesPoint]
  let historySeries: [UsageSeriesPoint]
  let palette: UsageSeriesPalette
  let machineLabels: [String: String]
  /// Lowest y, in `menuCoordinateSpace`, that the hover tooltip may reach.
  var tooltipBottomLimit: CGFloat? = nil

  static let menuCoordinateSpace = "menu"

  @State private var historyHoverDate: Date?
  /// Horizontal center of the hovered bar, in the chart's coordinates.
  @State private var historyHoverBarX: CGFloat?

  var body: some View {
    Group {
      switch mode {
      case .today:
        todayChart
      case .sevenDays, .thirtyDays, .oneYear:
        historyChart
      }
    }
    .environment(\.calendar, dateContext.calendar)
    .environment(\.timeZone, dateContext.timeZone)
  }

  private var todayChart: some View {
    Group {
      if cumulativeSeries.isEmpty {
        EmptyStateView(message: "Collecting samples for today.")
      } else {
        Chart(cumulativeSeries) { point in
          LineMark(
            x: .value("Time", point.date),
            y: .value("Cost", point.cost)
          )
          .interpolationMethod(.catmullRom)
          .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
          .foregroundStyle(by: .value("Series", point.series.chartIdentity))
        }
        .chartLegend(.hidden)
        .chartForegroundStyleScale(domain: colorDomain, range: colorRange)
        .chartYAxis {
          AxisMarks(position: .leading) { value in
            AxisGridLine()
            AxisValueLabel {
              if let cost = value.as(Double.self) {
                Text(Formatters.currencyString(cost))
              }
            }
          }
        }
        .chartXAxis {
          AxisMarks(values: .stride(by: .hour, count: 4)) { value in
            AxisGridLine()
            AxisValueLabel {
              if let date = value.as(Date.self) {
                Text(date, format: .dateTime.hour())
              }
            }
          }
        }
        .frame(height: 140)
      }
    }
  }

  private var historyChart: some View {
    Group {
      if historySeries.isEmpty {
        EmptyStateView(message: "No usage in this period.")
      } else {
        Chart {
          ForEach(historySeries) { point in
            if mode.usesGroupedDailyBars {
              BarMark(
                x: .value("Date", point.date, unit: historyUnit, calendar: dateContext.calendar),
                y: .value("Cost", point.cost)
              )
              .foregroundStyle(by: .value("Series", point.series.chartIdentity))
              .position(by: .value("Series", point.series.chartIdentity))
            } else {
              BarMark(
                x: .value("Date", point.date, unit: historyUnit, calendar: dateContext.calendar),
                y: .value("Cost", point.cost)
              )
              .foregroundStyle(by: .value("Series", point.series.chartIdentity))
            }
          }

          if let historyHoverDate, !historyHoverPoints.isEmpty {
            RuleMark(
              x: .value("Date", historyHoverDate, unit: historyUnit, calendar: dateContext.calendar)
            )
            .foregroundStyle(.secondary.opacity(0.5))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
          }
        }
        .chartLegend(.hidden)
        .chartForegroundStyleScale(domain: colorDomain, range: colorRange)
        .chartYAxis {
          AxisMarks(position: .leading) { value in
            AxisGridLine()
            AxisValueLabel {
              if let cost = value.as(Double.self) {
                Text(Formatters.currencyString(cost))
              }
            }
          }
        }
        .chartXScale(domain: historyDomain)
        .chartXAxis {
          AxisMarks(
            values: .stride(
              by: historyUnit, count: mode == .oneYear ? 2 : 5, calendar: dateContext.calendar)
          ) { value in
            AxisGridLine()
            AxisValueLabel {
              if let date = value.as(Date.self) {
                if mode == .oneYear {
                  Text(date, format: .dateTime.month(.abbreviated))
                } else {
                  Text(date, format: .dateTime.month().day())
                }
              }
            }
          }
        }
        .chartOverlay { proxy in
          GeometryReader { geo in
            HoverTrackingView { location in
              updateHistoryHover(location, proxy: proxy, geo: geo)
            }
          }
        }
        .overlay(alignment: .bottomLeading) {
          GeometryReader { geo in
            if let historyHoverDate, !historyHoverPoints.isEmpty, let historyHoverBarX {
              let width = min(HistoryTooltipView.width, geo.size.width)
              let x = min(max(historyHoverBarX - width / 2, 0), geo.size.width - width)
              let gap = HistoryTooltipView.caretHeight + 2
              let top = geo.frame(in: .named(Self.menuCoordinateSpace)).maxY + gap
              HistoryTooltipView(
                date: historyHoverDate,
                isMonthly: mode == .oneYear,
                points: historyHoverPoints,
                palette: palette,
                machineLabels: machineLabels,
                maxHeight: tooltipBottomLimit.map { $0 - top },
                caretX: historyHoverBarX - x
              )
              .frame(width: width)
              .offset(x: x, y: geo.size.height + gap)
              .allowsHitTesting(false)
            }
          }
        }
        .frame(height: 160)
        .onChange(of: mode) { _ in
          historyHoverDate = nil
          historyHoverBarX = nil
        }
      }
    }
  }

  private var historyUnit: Calendar.Component { mode == .oneYear ? .month : .day }

  private var historyDomain: ClosedRange<Date> {
    let context = dateContext
    if mode == .oneYear { return context.yearStart...context.yearEnd }
    let start = context.calendar.date(
      byAdding: .day, value: -(mode.dailyWindowDays! - 1), to: context.startOfToday)!
    return start...context.startOfNextDay
  }

  private var historyHoverPoints: [UsageSeriesPoint] {
    guard let historyHoverDate else { return [] }
    return historyPoints(at: historyHoverDate)
  }

  func historyPoints(at date: Date) -> [UsageSeriesPoint] {
    return
      historySeries
      .filter { dateContext.calendar.isDate($0.date, equalTo: date, toGranularity: historyUnit) }
      .sorted {
        UsageLegendLayout.isOrdered(($0.series, $0.cost), before: ($1.series, $1.cost))
      }
  }

  private func updateHistoryHover(_ location: CGPoint?, proxy: ChartProxy, geo: GeometryProxy) {
    guard let location else {
      historyHoverDate = nil
      historyHoverBarX = nil
      return
    }

    let plotFrame = geo[proxy.plotAreaFrame]
    guard plotFrame.contains(location) else {
      historyHoverDate = nil
      historyHoverBarX = nil
      return
    }

    let relativeX = location.x - plotFrame.origin.x
    guard let date: Date = proxy.value(atX: relativeX) else {
      historyHoverDate = nil
      historyHoverBarX = nil
      return
    }

    if let point = historyPoints(at: date).first {
      historyHoverDate = point.date
      historyHoverBarX = barCenterX(for: point.date, proxy: proxy, plotFrame: plotFrame)
    } else {
      historyHoverDate = nil
      historyHoverBarX = nil
    }
  }

  private func barCenterX(for bucketStart: Date, proxy: ChartProxy, plotFrame: CGRect)
    -> CGFloat?
  {
    guard
      let bucketEnd = dateContext.calendar.date(byAdding: historyUnit, value: 1, to: bucketStart),
      let x = proxy.position(forX: bucketStart + bucketEnd.timeIntervalSince(bucketStart) / 2)
    else { return nil }
    return plotFrame.minX + x
  }

  private var chartSeries: [UsageSeriesKey] {
    let series = (cumulativeSeries + historySeries).map(\.series)
    return Array(Set(series)).sorted { $0.sortKey < $1.sortKey }
  }

  private var colorDomain: [String] {
    chartSeries.map(\.chartIdentity)
  }

  private var colorRange: [Color] {
    chartSeries.map(palette.color(for:))
  }
}

private struct HistoryTooltipView: View {
  let date: Date
  let isMonthly: Bool
  let points: [UsageSeriesPoint]
  let palette: UsageSeriesPalette
  let machineLabels: [String: String]
  let maxHeight: CGFloat?
  /// Horizontal position of the hovered column, relative to the tooltip's leading edge.
  let caretX: CGFloat

  static let width: CGFloat = 260
  static let caretHeight: CGFloat = 6
  private static let caretWidth: CGFloat = 12
  private static let cornerRadius: CGFloat = 8
  private static let defaultMaximumRows = 12
  private static let rowHeight: CGFloat = 16
  private static let rowSpacing: CGFloat = 4
  private static let padding: CGFloat = 8

  // A step lighter than the menu so the tooltip stands apart from the legend under it.
  private static let background = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      ? NSColor(white: 0.24, alpha: 1) : NSColor(white: 1, alpha: 1)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Self.rowSpacing) {
      Text(date, format: isMonthly ? .dateTime.month().year() : .dateTime.month().day())
        .font(.caption)
        .foregroundColor(.secondary)
        .frame(height: Self.rowHeight)

      ForEach(visiblePoints) { point in
        pointRow(point)
      }

      if !hiddenPoints.isEmpty {
        HStack(spacing: 6) {
          Text("+\(hiddenPoints.count) more")
            .foregroundColor(.secondary)
            .padding(.leading, 14)
          Spacer(minLength: 8)
          Text(Formatters.currencyString(hiddenPoints.reduce(0) { $0 + $1.cost }))
            .foregroundColor(.secondary)
            .fixedSize()
        }
        .font(.caption)
        .frame(height: Self.rowHeight)
      }
    }
    .padding(Self.padding)
    .background(
      RoundedRectangle(cornerRadius: Self.cornerRadius)
        .fill(Color(nsColor: Self.background))
    )
    .overlay(
      RoundedRectangle(cornerRadius: Self.cornerRadius)
        .stroke(Color.secondary.opacity(0.2))
    )
    .overlay(alignment: .topLeading) {
      GeometryReader { geo in
        let inset = Self.cornerRadius + Self.caretWidth / 2
        let center = min(max(caretX, inset), geo.size.width - inset)
        ZStack {
          // The fill covers the border under the caret's base so the two shapes read as one.
          TooltipCaret(closed: true).fill(Color(nsColor: Self.background))
          TooltipCaret(closed: false).stroke(Color.secondary.opacity(0.2))
        }
        .frame(width: Self.caretWidth, height: Self.caretHeight + 1)
        .offset(x: center - Self.caretWidth / 2, y: -Self.caretHeight)
      }
    }
    .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
  }

  /// Series rows that fit below the date, counting a "+N more" row when some are cut.
  private var maximumRows: Int {
    guard let maxHeight else { return Self.defaultMaximumRows }
    let perRow = Self.rowHeight + Self.rowSpacing
    let available = maxHeight - Self.padding * 2 - Self.rowHeight
    return max(Int(available / perRow), 2)
  }

  /// Rows past the limit collapse into one "+N more" row so the tooltip stays inside the menu.
  private var visiblePoints: ArraySlice<UsageSeriesPoint> {
    points.count > maximumRows ? points.prefix(maximumRows - 1) : points[...]
  }

  private var hiddenPoints: ArraySlice<UsageSeriesPoint> {
    points.dropFirst(visiblePoints.count)
  }

  private func pointRow(_ point: UsageSeriesPoint) -> some View {
    HStack(spacing: 6) {
      Circle()
        .fill(palette.color(for: point.series))
        .frame(width: 8, height: 8)
      Text(point.series.displayName(machineLabels: machineLabels))
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer(minLength: 8)
      Text(Formatters.currencyString(point.cost))
        .fixedSize()
    }
    .font(.caption)
    .frame(height: Self.rowHeight)
  }
}

/// An upward-pointing triangle. The open form omits the base so a stroke draws only the sides.
private struct TooltipCaret: Shape {
  let closed: Bool

  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    if closed { path.closeSubpath() }
    return path
  }
}

private struct HoverTrackingView: NSViewRepresentable {
  var onMove: (CGPoint?) -> Void

  func makeNSView(context: Context) -> TrackingView {
    let view = TrackingView()
    view.onMove = onMove
    return view
  }

  func updateNSView(_ nsView: TrackingView, context: Context) {
    nsView.onMove = onMove
  }

  final class TrackingView: NSView {
    var onMove: ((CGPoint?) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
      if let trackingArea {
        removeTrackingArea(trackingArea)
      }

      let options: NSTrackingArea.Options = [
        .activeAlways,
        .inVisibleRect,
        .mouseEnteredAndExited,
        .mouseMoved,
      ]
      let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
      addTrackingArea(area)
      trackingArea = area
      super.updateTrackingAreas()
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      window?.acceptsMouseMovedEvents = true
    }

    override func mouseEntered(with event: NSEvent) {
      let point = convert(event.locationInWindow, from: nil)
      onMove?(point)
    }

    override func mouseMoved(with event: NSEvent) {
      let point = convert(event.locationInWindow, from: nil)
      onMove?(point)
    }

    override func mouseExited(with event: NSEvent) {
      onMove?(nil)
    }
  }
}

private struct EmptyStateView: View {
  let message: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(message)
        .font(.callout)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
    .padding(.vertical, 8)
  }
}
