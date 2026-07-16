import AppKit
import SwiftUI

struct MenuContentView: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var updaterController: UpdaterController
  @State private var chartMode: ChartMode = .today
  @State private var aggregationMode: UsageAggregationMode = .agent

  var body: some View {
    let palette = seriesPalette

    return VStack(alignment: .leading, spacing: 12) {
      header
      totalSection
      selectorControls

      Text(chartMode == .today ? "Cumulative" : "By Day")
        .font(.caption)
        .foregroundColor(.secondary)

      UsageChartView(
        mode: chartMode,
        cumulativeSeries: selectedCumulativeSeries,
        dailySeries: visibleDailySeries,
        palette: palette)

      totalsBreakdown(palette: palette)

      if let status = model.statusMessage {
        Text(status)
          .font(.caption)
          .foregroundColor(.red)
      }

      Divider()

      controls
    }
    .padding(12)
    .frame(width: 360)
    .background(Color(nsColor: .windowBackgroundColor))
    .onAppear {
      disableWindowResizing()
      model.refreshNow()
    }
  }

  private var selectorControls: some View {
    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
      GridRow {
        selectorLabel("View")
        Picker("View", selection: $chartMode) {
          ForEach(ChartMode.allCases) { mode in
            Text(mode.title).tag(mode)
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
      }

      GridRow {
        selectorLabel("Group")
        Picker("Group", selection: $aggregationMode) {
          ForEach(UsageAggregationMode.allCases) { mode in
            Text(mode.title).tag(mode)
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
      }
    }
  }

  private func selectorLabel(_ title: String) -> some View {
    Text(title)
      .font(.headline)
      .gridColumnAlignment(.leading)
  }

  private var header: some View {
    HStack(spacing: 8) {
      Image(systemName: "waveform.path.ecg")
        .font(.title3)
        .foregroundColor(.accentColor)
      Text("VibePulse")
        .font(.headline)
      Spacer()
      statusIndicator
    }
  }

  private var statusIndicator: some View {
    ZStack(alignment: .trailing) {
      if let lastUpdated = model.lastUpdated {
        Text(lastUpdated, format: .dateTime.hour().minute())
          .font(.caption)
          .foregroundColor(.secondary)
          .opacity(model.isRefreshing ? 0 : 1)
          .monospacedDigit()
      } else {
        Text(" ")
          .font(.caption)
          .foregroundColor(.secondary)
          .opacity(0)
      }

      if model.isRefreshing {
        ProgressView()
          .scaleEffect(0.7)
      }
    }
    .frame(width: 70, height: 16, alignment: .trailing)
    .animation(.none, value: model.isRefreshing)
  }

  private var totalSection: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(combinedTotalText)
        .font(.system(size: 28, weight: .semibold, design: .rounded))
        .monospacedDigit()
      Text(combinedTotalSubtitle)
        .font(.caption)
        .foregroundColor(.secondary)
    }
  }

  @ViewBuilder
  private func totalsBreakdown(palette: UsageSeriesPalette) -> some View {
    if toolBreakdown.count > 8 {
      ScrollView(.vertical) {
        totalsGrid(palette: palette)
      }
      .frame(height: 132)
    } else {
      totalsGrid(palette: palette)
    }
  }

  private func totalsGrid(palette: UsageSeriesPalette) -> some View {
    LazyVGrid(columns: legendColumns, alignment: .leading, spacing: 8) {
      ForEach(toolBreakdown) { total in
        ToolTotalLegendItem(total: total, color: palette.color(for: total.series))
      }
    }
  }

  private var legendColumns: [GridItem] {
    [
      GridItem(.flexible(minimum: 120), alignment: .leading),
      GridItem(.flexible(minimum: 120), alignment: .leading),
    ]
  }

  private var controls: some View {
    HStack {
      Button("Refresh") {
        model.refreshNow()
      }
      .disabled(model.isRefreshing)

      Button("Settings") {
        model.openSettings()
      }

      Button("Check for Updates\u{2026}") {
        updaterController.checkForUpdates()
      }

      Spacer()

      Button("Quit") {
        NSApp.terminate(nil)
      }
    }
    .buttonStyle(.borderless)
    .font(.caption)
  }

  private func disableWindowResizing() {
    if let window = NSApp.keyWindow {
      window.styleMask.remove(.resizable)
    }
  }

  private var combinedTotalText: String {
    switch chartMode {
    case .today:
      let total = selectedTotals.reduce(0) { $0 + $1.totalCost }
      return Formatters.currencyString(total)
    case .sevenDays, .thirtyDays:
      let total = visibleDailySeries.reduce(0) { $0 + $1.cost }
      return Formatters.currencyString(total)
    }
  }

  private var combinedTotalSubtitle: String {
    switch chartMode {
    case .today:
      return "Combined today by \(aggregationMode.title.lowercased()) via agentsview"
    case .sevenDays:
      return "Combined (last 7 days) by \(aggregationMode.title.lowercased())"
    case .thirtyDays:
      return "Combined (last 30 days) by \(aggregationMode.title.lowercased())"
    }
  }

  private var toolBreakdown: [ToolTotal] {
    switch chartMode {
    case .today:
      return selectedTotals.filter { $0.totalCost > 0.0001 }
    case .sevenDays, .thirtyDays:
      var totalsBySeries: [UsageSeriesKey: Double] = [:]
      for point in visibleDailySeries {
        totalsBySeries[point.series, default: 0] += point.cost
      }
      return totalsBySeries.compactMap { series, total in
        guard total > 0.0001 else { return nil }
        return ToolTotal(series: series, totalCost: total)
      }
      .sorted { $0.series.sortKey < $1.series.sortKey }
    }
  }

  private var selectedCumulativeSeries: [UsageSeriesPoint] {
    switch aggregationMode {
    case .agent:
      return model.cumulativeSeries
    case .model:
      return model.modelCumulativeSeries
    }
  }

  private var selectedDailySeries: [UsageSeriesPoint] {
    switch aggregationMode {
    case .agent:
      return model.dailySeries
    case .model:
      return model.modelDailySeries
    }
  }

  private var selectedTotals: [ToolTotal] {
    switch aggregationMode {
    case .agent:
      return model.toolTotals
    case .model:
      return model.modelTotals
    }
  }

  private var seriesPalette: UsageSeriesPalette {
    UsageSeriesPalette(
      series: UsageSeriesPalette.canonicalSeries(
        thirtyDaySeries: selectedDailySeries,
        todayCumulativeSeries: selectedCumulativeSeries,
        todayTotals: selectedTotals))
  }

  private var visibleDailySeries: [UsageSeriesPoint] {
    UsageSeriesFilters.visibleDailySeries(selectedDailySeries, mode: chartMode)
  }
}

private struct ToolTotalLegendItem: View {
  let total: ToolTotal
  let color: Color

  var body: some View {
    HStack(alignment: .top, spacing: 6) {
      Circle()
        .fill(color)
        .frame(width: 8, height: 8)
        .padding(.top, 4)

      VStack(alignment: .leading, spacing: 1) {
        Text(total.series.displayName)
          .lineLimit(1)
          .truncationMode(.middle)
          .minimumScaleFactor(0.85)
        Text(Formatters.currencyString(total.totalCost))
          .monospacedDigit()
      }
      .font(.caption)
      .foregroundColor(.secondary)
    }
  }
}
