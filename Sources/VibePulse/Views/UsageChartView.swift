import AppKit
import Charts
import SwiftUI

struct UsageChartView: View {
  let mode: ChartMode
  let dateContext: UsageDateContext
  let cumulativeSeries: [UsageSeriesPoint]
  let historySeries: [UsageSeriesPoint]
  let palette: UsageSeriesPalette
  @Binding var selection: HistorySelection?

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
              .opacity(barOpacity(point))
            } else {
              BarMark(
                x: .value("Date", point.date, unit: historyUnit, calendar: dateContext.calendar),
                y: .value("Cost", point.cost)
              )
              .foregroundStyle(by: .value("Series", point.series.chartIdentity))
              .opacity(barOpacity(point))
            }
          }

          if let selection {
            RuleMark(
              x: .value("Date", selection.date, unit: historyUnit, calendar: dateContext.calendar)
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
            HoverTrackingView(
              onMove: { location in
                updateHistoryHover(location, proxy: proxy, geo: geo)
              },
              onClick: { location in
                toggleHistoryPin(location, proxy: proxy, geo: geo)
              })
          }
        }
        .frame(height: 160)
      }
    }
  }

  private var historyUnit: Calendar.Component { mode.historyUnit }

  private var historyDomain: ClosedRange<Date> {
    let context = dateContext
    if mode == .oneYear { return context.yearStart...context.yearEnd }
    let start = context.calendar.date(
      byAdding: .day, value: -(mode.dailyWindowDays! - 1), to: context.startOfToday)!
    return start...context.startOfNextDay
  }

  func historyPoints(at date: Date) -> [UsageSeriesPoint] {
    UsageSeriesAggregation.bucketPoints(
      historySeries, containing: date, unit: historyUnit, calendar: dateContext.calendar)
  }

  private func barOpacity(_ point: UsageSeriesPoint) -> Double {
    guard let selection else { return 1 }
    let isSelected = dateContext.calendar.isDate(
      point.date, equalTo: selection.date, toGranularity: historyUnit)
    return isSelected ? 1 : 0.35
  }

  /// The start of the bar under `location`, or nil when no bar has data there.
  private func historyBucket(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy)
    -> Date?
  {
    let plotFrame = geo[proxy.plotAreaFrame]
    guard plotFrame.contains(location),
      let date: Date = proxy.value(atX: location.x - plotFrame.origin.x)
    else { return nil }
    return historyPoints(at: date).first?.date
  }

  private func updateHistoryHover(_ location: CGPoint?, proxy: ChartProxy, geo: GeometryProxy) {
    if selection?.isPinned == true { return }
    let bucket = location.flatMap { historyBucket(at: $0, proxy: proxy, geo: geo) }
    selection = bucket.map { HistorySelection(date: $0, isPinned: false) }
  }

  private func toggleHistoryPin(_ location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
    guard let bucket = historyBucket(at: location, proxy: proxy, geo: geo) else {
      selection = nil
      return
    }
    if let selection, selection.isPinned, selection.date == bucket {
      self.selection = HistorySelection(date: bucket, isPinned: false)
    } else {
      selection = HistorySelection(date: bucket, isPinned: true)
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

/// A hovered or clicked bar in the history chart. A pinned selection ignores hover.
struct HistorySelection: Equatable {
  let date: Date
  let isPinned: Bool
}

private struct HoverTrackingView: NSViewRepresentable {
  var onMove: (CGPoint?) -> Void
  var onClick: (CGPoint) -> Void

  func makeNSView(context: Context) -> TrackingView {
    let view = TrackingView()
    view.onMove = onMove
    view.onClick = onClick
    return view
  }

  func updateNSView(_ nsView: TrackingView, context: Context) {
    nsView.onMove = onMove
    nsView.onClick = onClick
  }

  final class TrackingView: NSView {
    // Match SwiftUI's top-left origin so points line up with the plot frame.
    override var isFlipped: Bool { true }

    var onMove: ((CGPoint?) -> Void)?
    var onClick: ((CGPoint) -> Void)?
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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
      onClick?(convert(event.locationInWindow, from: nil))
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
