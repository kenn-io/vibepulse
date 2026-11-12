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

  @State private var historyHoverDate: Date?
  @State private var historyTooltipPosition: CGPoint?

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
        .overlay(alignment: .topLeading) {
          if let historyHoverDate, !historyHoverPoints.isEmpty, let historyTooltipPosition {
            HistoryTooltipView(
              date: historyHoverDate,
              isMonthly: mode == .oneYear,
              points: historyHoverPoints,
              palette: palette,
              machineLabels: machineLabels
            )
            .offset(x: historyTooltipPosition.x, y: historyTooltipPosition.y)
          }
        }
        .frame(height: 160)
        .onChange(of: mode) { _ in
          historyHoverDate = nil
          historyTooltipPosition = nil
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
      .sorted { $0.series.sortKey < $1.series.sortKey }
  }

  private func updateHistoryHover(_ location: CGPoint?, proxy: ChartProxy, geo: GeometryProxy) {
    guard let location else {
      historyHoverDate = nil
      historyTooltipPosition = nil
      return
    }

    let plotFrame = geo[proxy.plotAreaFrame]
    guard plotFrame.contains(location) else {
      historyHoverDate = nil
      historyTooltipPosition = nil
      return
    }

    let relativeX = location.x - plotFrame.origin.x
    guard let date: Date = proxy.value(atX: relativeX) else {
      historyHoverDate = nil
      historyTooltipPosition = nil
      return
    }

    if let point = historyPoints(at: date).first {
      historyHoverDate = point.date
      historyTooltipPosition = CGPoint(x: plotFrame.minX + 8, y: plotFrame.minY + 8)
    } else {
      historyHoverDate = nil
      historyTooltipPosition = nil
    }
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

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(date, format: isMonthly ? .dateTime.month().year() : .dateTime.month().day())
        .font(.caption)
        .foregroundColor(.secondary)

      if points.count > 8 {
        ScrollView(.vertical) {
          LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(points) { point in
              pointRow(point)
            }
          }
        }
        .frame(height: 150)
      } else {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(points) { point in
            pointRow(point)
          }
        }
      }
    }
    .frame(minWidth: 180, maxWidth: 260, alignment: .leading)
    .padding(8)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(Color(nsColor: .windowBackgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color.secondary.opacity(0.2))
    )
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
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
