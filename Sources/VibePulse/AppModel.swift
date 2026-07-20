import Foundation
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
  @Published var menuTotalText: String = Formatters.currencyString(0)
  @Published var hourlySeries: [UsageSeriesPoint] = []
  @Published var cumulativeSeries: [UsageSeriesPoint] = []
  @Published var dailySeries: [UsageSeriesPoint] = []
  @Published var toolTotals: [ToolTotal] = []
  @Published var modelCumulativeSeries: [UsageSeriesPoint] = []
  @Published var modelDailySeries: [UsageSeriesPoint] = []
  @Published var modelTotals: [ToolTotal] = []
  @Published var machineCumulativeSeries: [UsageSeriesPoint] = []
  @Published var machineDailySeries: [UsageSeriesPoint] = []
  @Published var machineTotals: [ToolTotal] = []
  @Published var lastUpdated: Date?
  @Published var statusMessage: String?
  @Published var isRefreshing = false
  @Published var isMaintaining = false
  @Published var maintenanceMode: MaintenanceMode {
    didSet {
      defaults.set(maintenanceMode.rawValue, forKey: DefaultsKey.maintenanceMode)
      if maintenanceMode == .automatic {
        runMaintenanceIfNeeded()
      }
    }
  }
  @Published var lastMaintenanceAt: Date?
  @Published var maintenanceMessage: String?
  @Published var startAtLogin: Bool {
    didSet {
      setStartAtLogin(enabled: startAtLogin)
    }
  }
  @Published var loginItemMessage: String?
  @Published var agentsviewPath: String {
    didSet {
      defaults.set(
        agentsviewPath, forKey: DefaultsKey.agentsviewPath
      )
    }
  }

  @Published var includeClaude: Bool {
    didSet {
      defaults.set(includeClaude, forKey: DefaultsKey.includeClaude)
      reloadFromStore()
    }
  }

  @Published var includeCodex: Bool {
    didSet {
      defaults.set(includeCodex, forKey: DefaultsKey.includeCodex)
      reloadFromStore()
    }
  }

  @Published var includePi: Bool {
    didSet {
      defaults.set(includePi, forKey: DefaultsKey.includePi)
      reloadFromStore()
    }
  }

  @Published var includeOMP: Bool {
    didSet {
      defaults.set(includeOMP, forKey: DefaultsKey.includeOMP)
      reloadFromStore()
    }
  }

  @Published var includeGemini: Bool {
    didSet {
      defaults.set(includeGemini, forKey: DefaultsKey.includeGemini)
      reloadFromStore()
    }
  }

  @Published var includeOpenCode: Bool {
    didSet {
      defaults.set(includeOpenCode, forKey: DefaultsKey.includeOpenCode)
      reloadFromStore()
    }
  }

  @Published var refreshInterval: RefreshInterval {
    didSet {
      defaults.set(refreshInterval.rawValue, forKey: DefaultsKey.refreshInterval)
      scheduleTimer()
    }
  }

  private let defaults = UserDefaults.standard
  private let fetcher = UsageFetcher()
  private let settingsWindowController = SettingsWindowController()
  private let welcomeWindowController = WelcomeWindowController()
  private var timer: DispatchSourceTimer?
  private var isUpdatingLoginItem = false
  private let store: UsageStore

  init() {
    includeClaude = defaults.object(forKey: DefaultsKey.includeClaude) as? Bool ?? true
    includeCodex = defaults.object(forKey: DefaultsKey.includeCodex) as? Bool ?? true
    includePi = defaults.object(forKey: DefaultsKey.includePi) as? Bool ?? true
    includeOMP = defaults.object(forKey: DefaultsKey.includeOMP) as? Bool ?? true
    includeGemini = defaults.object(forKey: DefaultsKey.includeGemini) as? Bool ?? true
    includeOpenCode = defaults.object(forKey: DefaultsKey.includeOpenCode) as? Bool ?? true
    let storedInterval = defaults.string(forKey: DefaultsKey.refreshInterval)
    if let storedInterval, let interval = RefreshInterval(rawValue: storedInterval) {
      refreshInterval = interval
    } else if let legacyMinutes = defaults.object(forKey: DefaultsKey.refreshMinutes) as? Double {
      refreshInterval = Self.intervalFromLegacy(minutes: legacyMinutes)
    } else {
      refreshInterval = .fifteenMinutes
    }
    let storedMode = defaults.string(forKey: DefaultsKey.maintenanceMode)
    maintenanceMode = MaintenanceMode(rawValue: storedMode ?? "") ?? .automatic
    if let storedMaintenance = defaults.object(forKey: DefaultsKey.lastMaintenanceAt) as? Double {
      lastMaintenanceAt = Date(timeIntervalSince1970: storedMaintenance)
    }

    agentsviewPath =
      defaults.string(forKey: DefaultsKey.agentsviewPath) ?? ""
    startAtLogin = Self.currentLoginItemEnabled()

    if SMAppService.mainApp.status == .requiresApproval {
      loginItemMessage = "Enable VibePulse in System Settings > Login Items."
    }

    do {
      store = try UsageStore.defaultStore()
    } catch {
      store = try! UsageStore(path: ":memory:")
      statusMessage = "Database unavailable. Running without persistence."
    }

    reloadFromStore()
    scheduleTimer()
    refreshNow()
    runMaintenanceIfNeeded()
    DispatchQueue.main.async {
      self.showWelcomeIfNeeded()
    }
  }

  func refreshNow() {
    guard !isRefreshing else { return }

    let tools = activeTools
    guard !tools.isEmpty else {
      statusMessage = "Enable at least one data source in Settings."
      return
    }

    isRefreshing = true
    statusMessage = nil

    let todayKey = DateHelper.dateKey(for: Date())

    DispatchQueue.global(qos: .background).async { [fetcher, store] in
      var errors: [String] = []
      let sampleTime = Date()

      for tool in tools {
        do {
          let totals = try fetcher.fetchDailyTotals(for: tool)
          try store.upsertDailyTotals(tool: tool, totals: totals)
          if let todayTotal = totals.first(where: {
            DateHelper.normalizedDateKey(from: $0.dateKey) == todayKey
          }) {
            try store.insertSample(tool: tool, totalCost: todayTotal.cost, recordedAt: sampleTime)
            if let modelBreakdowns = todayTotal.modelBreakdowns {
              try store.insertModelSamplesForRefresh(
                tool: tool,
                modelBreakdowns: modelBreakdowns,
                recordedAt: sampleTime)
            }
            if let machineBreakdowns = todayTotal.machineBreakdowns {
              try store.insertMachineSamplesForRefresh(
                tool: tool,
                machineBreakdowns: machineBreakdowns,
                recordedAt: sampleTime)
            }
          }
        } catch {
          errors.append("\(tool.displayName): \(error.localizedDescription)")
        }
      }

      let refreshTime = Date()

      DispatchQueue.main.async {
        if !errors.isEmpty {
          self.statusMessage = errors.joined(separator: " | ")
        } else {
          self.lastUpdated = refreshTime
        }
        self.reloadFromStore()
        self.isRefreshing = false
      }
    }
  }

  private func showWelcomeIfNeeded() {
    if !defaults.bool(forKey: DefaultsKey.welcomeKey) {
      welcomeWindowController.show(model: self) {
        self.defaults.set(true, forKey: DefaultsKey.welcomeKey)
      }
    }
  }

  func openSettings() {
    settingsWindowController.show(model: self)
  }

  private var activeTools: [UsageTool] {
    UsageTool.allCases.filter { tool in
      switch tool {
      case .claude:
        return includeClaude
      case .codex:
        return includeCodex
      case .pi:
        return includePi
      case .omp:
        return includeOMP
      case .gemini:
        return includeGemini
      case .openCode:
        return includeOpenCode
      }
    }
  }

  private func reloadFromStore() {
    let tools = activeTools
    let startOfDay = DateHelper.startOfToday()
    let now = Date()
    var hourlyPoints: [UsageSeriesPoint] = []

    for tool in tools {
      let samples = store.fetchSamples(tool: tool, from: startOfDay, to: now).sorted {
        $0.recordedAt < $1.recordedAt
      }
      hourlyPoints.append(
        contentsOf: HourlyUsageInferer.inferPoints(
          tool: tool, samples: samples, startOfDay: startOfDay, end: now))
    }

    hourlySeries = hourlyPoints.sorted { $0.date < $1.date }
    var cumulativePoints: [UsageSeriesPoint] = []

    for tool in tools {
      let samples = store.fetchSamples(tool: tool, from: startOfDay, to: now).sorted {
        $0.recordedAt < $1.recordedAt
      }
      cumulativePoints.append(
        contentsOf: samples.map {
          UsageSeriesPoint(tool: tool, date: $0.recordedAt, cost: $0.totalCost)
        })
    }

    cumulativeSeries = cumulativePoints.sorted { $0.date < $1.date }

    let modelSamples = store.fetchModelSamples(tools: tools, from: startOfDay, to: now)
    modelCumulativeSeries = UsageSeriesAggregation.cumulativeModelSeries(from: modelSamples)
    let machineSamples = store.fetchMachineSamples(tools: tools, from: startOfDay, to: now)
    machineCumulativeSeries = UsageSeriesAggregation.cumulativeMachineSeries(from: machineSamples)

    let sinceKey = DateHelper.dateKeyDaysAgo(29)
    let rollups = store.fetchDailyRollups(since: sinceKey)
    dailySeries = rollups.compactMap { rollup in
      guard tools.contains(rollup.tool), let date = DateHelper.date(fromKey: rollup.dateKey) else {
        return nil
      }
      return UsageSeriesPoint(tool: rollup.tool, date: date, cost: rollup.totalCost)
    }

    let modelRollups = store.fetchModelDailyRollups(since: sinceKey, tools: tools)
    modelDailySeries = aggregateModelDailySeries(modelRollups)
    let machineRollups = store.fetchMachineDailyRollups(since: sinceKey, tools: tools)
    machineDailySeries = UsageSeriesAggregation.dailyMachineSeries(from: machineRollups)

    let todayKey = DateHelper.dateKey(for: Date())
    var totals: [ToolTotal] = []
    for tool in tools {
      let dailyTotal = store.dailyTotal(for: todayKey, tool: tool)
      let sampleTotal = store.latestSample(for: todayKey, tool: tool)?.totalCost
      let totalCost = dailyTotal ?? sampleTotal ?? 0
      totals.append(ToolTotal(tool: tool, totalCost: totalCost))
    }
    toolTotals = totals
    modelTotals = aggregateModelTotals(modelRollups, todayKey: todayKey)
    machineTotals = UsageSeriesAggregation.machineTotals(
      from: machineRollups, dateKey: todayKey)
    let combined = totals.reduce(0) { $0 + $1.totalCost }
    menuTotalText = Formatters.currencyString(combined)
  }

  private func aggregateModelDailySeries(_ rollups: [ModelDailyRollup]) -> [UsageSeriesPoint] {
    var totalsByDateAndModel: [ModelDailyKey: Double] = [:]
    for rollup in rollups {
      let key = ModelDailyKey(dateKey: rollup.dateKey, modelName: rollup.modelName)
      totalsByDateAndModel[key, default: 0] += rollup.totalCost
    }

    return totalsByDateAndModel.compactMap { key, totalCost in
      guard let date = DateHelper.date(fromKey: key.dateKey) else {
        return nil
      }
      return UsageSeriesPoint(series: .model(key.modelName), date: date, cost: totalCost)
    }
    .sorted {
      if $0.date == $1.date {
        return $0.series.sortKey < $1.series.sortKey
      }
      return $0.date < $1.date
    }
  }

  private func aggregateModelTotals(
    _ rollups: [ModelDailyRollup],
    todayKey: String
  ) -> [ToolTotal] {
    var totalsByModel: [String: Double] = [:]
    for rollup in rollups where rollup.dateKey == todayKey {
      totalsByModel[rollup.modelName, default: 0] += rollup.totalCost
    }

    return totalsByModel.map { modelName, totalCost in
      ToolTotal(series: .model(modelName), totalCost: totalCost)
    }
    .sorted { $0.series.sortKey < $1.series.sortKey }
  }

  private struct ModelDailyKey: Hashable {
    let dateKey: String
    let modelName: String
  }

  func runMaintenance(force: Bool = false) {
    guard !isMaintaining else { return }
    guard force || maintenanceMode == .automatic else { return }

    if !force, let lastMaintenanceAt, Date().timeIntervalSince(lastMaintenanceAt) < 60 * 60 * 24 {
      return
    }

    isMaintaining = true
    maintenanceMessage = nil

    DispatchQueue.global(qos: .background).async { [store] in
      do {
        let deltaUpdated = try store.backfillSampleDeltas()
        let modelDeltaUpdated = try store.backfillModelSampleDeltas()
        let machineDeltaUpdated = try store.backfillMachineSampleDeltas()
        let dateUpdated = try UsageTool.allCases.reduce(0) { count, tool in
          count + (try store.normalizeDailyRollupDates(for: tool))
            + (try store.normalizeModelDailyRollupDates(for: tool))
            + (try store.normalizeMachineDailyRollupDates(for: tool))
        }
        let message =
          "Maintenance complete. Updated \(deltaUpdated + modelDeltaUpdated + machineDeltaUpdated) snapshots, normalized \(dateUpdated) daily totals."
        let now = Date()
        DispatchQueue.main.async {
          self.maintenanceMessage = message
          self.lastMaintenanceAt = now
          self.defaults.set(now.timeIntervalSince1970, forKey: DefaultsKey.lastMaintenanceAt)
          self.reloadFromStore()
          self.isMaintaining = false
        }
      } catch {
        DispatchQueue.main.async {
          self.maintenanceMessage = "Maintenance failed: \(error.localizedDescription)"
          self.isMaintaining = false
        }
      }
    }
  }

  private func runMaintenanceIfNeeded() {
    runMaintenance(force: false)
  }

  private static func intervalFromLegacy(minutes: Double) -> RefreshInterval {
    switch minutes {
    case ..<10:
      return .fiveMinutes
    case ..<30:
      return .fifteenMinutes
    case ..<120:
      return .oneHour
    case ..<600:
      return .fourHours
    default:
      return .oneDay
    }
  }

  private static func currentLoginItemEnabled() -> Bool {
    switch SMAppService.mainApp.status {
    case .enabled, .requiresApproval:
      return true
    default:
      return false
    }
  }

  private func setStartAtLogin(enabled: Bool) {
    guard !isUpdatingLoginItem else { return }
    isUpdatingLoginItem = true
    defer { isUpdatingLoginItem = false }

    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      if SMAppService.mainApp.status == .requiresApproval {
        loginItemMessage = "Enable VibePulse in System Settings > Login Items."
      } else {
        loginItemMessage = nil
      }
    } catch {
      loginItemMessage = "Login item update failed: \(error.localizedDescription)"
      startAtLogin = Self.currentLoginItemEnabled()
    }
  }

  private func scheduleTimer() {
    timer?.cancel()
    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .background))
    let intervalSeconds = max(60, refreshInterval.seconds)
    timer.schedule(deadline: .now() + .seconds(5), repeating: .seconds(intervalSeconds))
    timer.setEventHandler { [weak self] in
      Task { @MainActor in
        self?.refreshNow()
      }
    }
    timer.resume()
    self.timer = timer
  }

  private enum DefaultsKey {
    static let welcomeKey = "hasSeenWelcome"
    static let includeClaude = "includeClaude"
    static let includeCodex = "includeCodex"
    static let includePi = "includePi"
    static let includeOMP = "includeOMP"
    static let includeGemini = "includeGemini"
    static let includeOpenCode = "includeOpenCode"
    static let refreshMinutes = "refreshMinutes"
    static let refreshInterval = "refreshInterval"
    static let agentsviewPath = "agentsviewPath"
    static let maintenanceMode = "maintenanceMode"
    static let lastMaintenanceAt = "lastMaintenanceAt"
  }
}
