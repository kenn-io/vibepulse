import Foundation
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
  @Published var menuTotalText: String = Formatters.currencyString(0)
  @Published var cumulativeSeries: [UsageSeriesPoint] = []
  @Published var dailySeries: [UsageSeriesPoint] = []
  @Published var monthlySeries: [UsageSeriesPoint] = []
  @Published var toolTotals: [ToolTotal] = []
  @Published var modelCumulativeSeries: [UsageSeriesPoint] = []
  @Published var modelDailySeries: [UsageSeriesPoint] = []
  @Published var modelMonthlySeries: [UsageSeriesPoint] = []
  @Published var modelTotals: [ToolTotal] = []
  @Published var machineCumulativeSeries: [UsageSeriesPoint] = []
  @Published var machineDailySeries: [UsageSeriesPoint] = []
  @Published var machineMonthlySeries: [UsageSeriesPoint] = []
  @Published var machineTotals: [ToolTotal] = []
  @Published private(set) var chartDateContext = UsageDateContext()
  @Published var lastUpdated: Date?
  @Published var statusMessage: String?
  @Published var isRefreshing = false
  @Published var isMaintaining = false
  @Published var chartMode: ChartMode = .today {
    didSet {
      guard chartMode != oldValue else { return }
      if chartMode == .oneYear || oldValue == .oneYear { reloadFromStoreIfTimezoneReady() }
      if chartMode == .oneYear { refreshIfNeeded() }
    }
  }
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
      sourceConfigurationGeneration += 1
      lastYearRefresh = nil
      lastUpdated = nil
    }
  }
  @Published var agentsviewServerURL: String {
    didSet {
      defaults.set(
        agentsviewServerURL, forKey: DefaultsKey.agentsviewServerURL
      )
      sourceConfigurationGeneration += 1
      lastYearRefresh = nil
      lastUpdated = nil
    }
  }
  @Published var includeAutomatedSessions: Bool {
    didSet {
      guard includeAutomatedSessions != oldValue else { return }
      defaults.set(includeAutomatedSessions, forKey: DefaultsKey.includeAutomatedSessions)
      reloadFromStoreIfTimezoneReady()
    }
  }
  private var effectiveIncludeAutomated: Bool {
    agentsviewServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || includeAutomatedSessions
  }
  @Published private(set) var machineLabelSnapshot: MachineLabels?
  @Published private(set) var discoveredAgents: [UsageAgent]
  @Published private(set) var disabledAgentIDs: Set<String>

  @Published var refreshInterval: RefreshInterval {
    didSet {
      defaults.set(refreshInterval.rawValue, forKey: DefaultsKey.refreshInterval)
      scheduleTimer()
    }
  }

  private let defaults: UserDefaults
  private let agentPreferences: AgentPreferences
  private let settingsWindowController = SettingsWindowController()
  private let welcomeWindowController = WelcomeWindowController()
  private var timer: DispatchSourceTimer?
  private var timeZoneObserver: NSObjectProtocol?
  private var timezoneRefreshState: UsageRefreshTimezoneState
  private var isUpdatingLoginItem = false
  private let combinedStore: UsageStore
  private let nonAutomatedStore: UsageStore
  private var store: UsageStore {
    effectiveIncludeAutomated ? combinedStore : nonAutomatedStore
  }
  private let refreshService: UsageRefreshService
  private let nonAutomatedRefreshService: UsageRefreshService
  private var sourceConfigurationGeneration = 0
  private var lastYearRefresh: UsageDateContext?

  init(
    defaults: UserDefaults = .standard,
    store suppliedStore: UsageStore? = nil,
    nonAutomatedStore suppliedNonAutomatedStore: UsageStore? = nil,
    fetcher: UsageFetching = UsageFetcher()
  ) {
    self.defaults = defaults
    timezoneRefreshState = UsageRefreshTimezoneState(
      lastSuccessfulTimeZone: defaults.string(forKey: DefaultsKey.lastUsageTimeZone),
      lastInvalidatedTimeZone: defaults.string(forKey: DefaultsKey.lastUsageInvalidatedTimeZone))
    let agentPreferences = AgentPreferences(defaults: defaults)
    agentPreferences.migrateLegacyPreferences()
    self.agentPreferences = agentPreferences
    discoveredAgents = agentPreferences.loadDiscoveredAgents()
    disabledAgentIDs = agentPreferences.loadDisabledAgentIDs()
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
    agentsviewServerURL =
      defaults.string(forKey: DefaultsKey.agentsviewServerURL) ?? ""
    includeAutomatedSessions =
      defaults.object(forKey: DefaultsKey.includeAutomatedSessions) as? Bool ?? true
    machineLabelSnapshot = defaults.data(forKey: DefaultsKey.machineLabels).flatMap {
      try? JSONDecoder().decode(MachineLabels.self, from: $0)
    }
    startAtLogin = Self.currentLoginItemEnabled()

    if SMAppService.mainApp.status == .requiresApproval {
      loginItemMessage = "Enable VibePulse in System Settings > Login Items."
    }

    // Each database falls back alone, so one unreadable file keeps the other's history.
    var databaseUnavailable = false
    func openStore(_ open: () throws -> UsageStore) -> UsageStore {
      do {
        return try open()
      } catch {
        databaseUnavailable = true
        return try! UsageStore(path: ":memory:")
      }
    }
    combinedStore = openStore { try suppliedStore ?? UsageStore.defaultStore() }
    nonAutomatedStore = openStore {
      try suppliedNonAutomatedStore
        ?? (suppliedStore != nil
          ? UsageStore(path: ":memory:") : UsageStore.defaultStore(includeAutomated: false))
    }
    if databaseUnavailable {
      statusMessage = "Database unavailable. Running without persistence."
    }
    refreshService = UsageRefreshService(fetcher: fetcher, store: combinedStore)
    nonAutomatedRefreshService = UsageRefreshService(fetcher: fetcher, store: nonAutomatedStore)
    timeZoneObserver = NotificationCenter.default.addObserver(
      forName: .NSSystemTimeZoneDidChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.handleSystemTimeZoneChange()
      }
    }

    let initialContext = UsageDateContext()
    if !timezoneRefreshState.shouldInvalidateCurrentDay(
      for: initialContext.timeZone.identifier)
    {
      reloadFromStore(context: initialContext)
    }
    scheduleTimer()
    refreshNow()
    runMaintenanceIfNeeded()
    DispatchQueue.main.async {
      self.showWelcomeIfNeeded()
    }
  }

  deinit {
    timer?.cancel()
    if let timeZoneObserver {
      NotificationCenter.default.removeObserver(timeZoneObserver)
    }
  }

  func refreshIfNeeded(now: Date = Date()) {
    let context = UsageDateContext(now: now)
    if let lastUpdated, statusMessage == nil,
      !needsYearRefresh(context: context),
      !timezoneRefreshState.shouldInvalidateCurrentDay(for: context.timeZone.identifier),
      lastUpdated >= context.startOfToday, lastUpdated <= now,
      now.timeIntervalSince(lastUpdated) < Double(refreshInterval.seconds)
    {
      return
    }
    refreshNow(now: now, refreshHistory: false)
  }

  private func needsYearRefresh(context: UsageDateContext) -> Bool {
    guard chartMode == .oneYear else { return false }
    guard let lastYearRefresh else { return true }
    return lastYearRefresh.todayKey != context.todayKey
      || lastYearRefresh.timeZone.identifier != context.timeZone.identifier
      || lastYearRefresh.now > context.now
  }

  func refreshNow(now: Date = Date(), refreshHistory: Bool = true) {
    guard !isRefreshing else { return }

    isRefreshing = true
    statusMessage = nil

    let sourceGeneration = sourceConfigurationGeneration
    let includeYear =
      (refreshHistory && chartMode == .oneYear)
      || needsYearRefresh(context: UsageDateContext(now: now))
    let serverURL = agentsviewServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let context = UsageDateContext(
      now: now, includesYear: includeYear, serverURL: serverURL)
    let retainedAgents = !includeYear && lastYearRefresh != nil ? discoveredAgents : []
    let previousAgents = discoveredAgents
    if includeYear { lastYearRefresh = nil }
    let invalidateCurrentDay = timezoneRefreshState.shouldInvalidateCurrentDay(
      for: context.timeZone.identifier)
    if invalidateCurrentDay {
      clearPublishedUsage()
    }

    DispatchQueue.global(qos: .background).async {
      [combinedStore, nonAutomatedStore, refreshService, nonAutomatedRefreshService] in
      do {
        // Both caches share one timezone marker, so both leave the old timezone together.
        if invalidateCurrentDay {
          for store in [combinedStore, nonAutomatedStore] {
            try store.deleteCurrentDaySamples(using: context)
            try store.deleteRefreshWindowRollups(using: context)
          }
        }
        let combined = Result {
          try refreshService.refresh(context: context, retainedAgents: retainedAgents)
        }
        // Only a server can exclude automation; the CLI never fills the non-automated cache.
        let nonAutomated =
          serverURL.isEmpty
          ? nil
          : Result {
            try nonAutomatedRefreshService.refresh(
              context: UsageDateContext(
                now: context.now, timeZone: context.timeZone,
                includesYear: context.includesYear, includeAutomated: false,
                serverURL: serverURL))
          }
        let reports = [combined, nonAutomated].compactMap { $0 }
        let succeeded = reports.compactMap { try? $0.get() }
        if succeeded.isEmpty { _ = try combined.get() }
        // Publish whichever report succeeded. The other's error keeps the refresh due for retry.
        var errors = succeeded.flatMap(\.importErrors)
        if case .failure(let error) = combined {
          errors.append(error.localizedDescription)
        }
        if case .failure(let error)? = nonAutomated {
          errors.append("Without automated sessions: \(error.localizedDescription)")
        }
        let keptAgents = succeeded.count < reports.count ? previousAgents : []
        let completedResult = UsageRefreshResult(
          discoveredAgents: Array(Set(succeeded.flatMap(\.discoveredAgents) + keptAgents))
            .sorted(),
          importErrors: errors,
          machineLabels: succeeded.lazy.compactMap(\.machineLabels).first)
        DispatchQueue.main.async {
          guard UsageDateContext().timeZone.identifier == context.timeZone.identifier else {
            self.timezoneRefreshState.markTimezoneChange()
            self.isRefreshing = false
            self.refreshNow()
            return
          }

          self.discoveredAgents = completedResult.discoveredAgents
          self.agentPreferences.saveDiscoveredAgents(self.discoveredAgents)
          if let machineLabels = completedResult.machineLabels {
            self.machineLabelSnapshot = machineLabels
            self.defaults.set(
              try? JSONEncoder().encode(machineLabels), forKey: DefaultsKey.machineLabels)
          }
          if completedResult.importErrors.isEmpty {
            self.statusMessage = nil
            if self.sourceConfigurationGeneration == sourceGeneration {
              self.lastUpdated = context.now
              if context.includesYear { self.lastYearRefresh = context }
            }
          } else {
            self.statusMessage = completedResult.importErrors.joined(separator: " | ")
          }
          self.timezoneRefreshState.completeRefresh(
            for: context.timeZone.identifier,
            invalidatedCurrentDay: invalidateCurrentDay,
            hasImportErrors: !completedResult.importErrors.isEmpty)
          self.persistTimezoneRefreshState()
          self.reloadFromStore(context: UsageDateContext())
          self.isRefreshing = false
          if !context.includesYear && self.needsYearRefresh(context: UsageDateContext()) {
            self.refreshIfNeeded()
          }
        }
      } catch {
        DispatchQueue.main.async {
          let contextStillCurrent =
            UsageDateContext().timeZone.identifier == context.timeZone.identifier
          if !contextStillCurrent {
            self.timezoneRefreshState.markTimezoneChange()
          }
          self.statusMessage = error.localizedDescription
          if contextStillCurrent {
            self.reloadFromStoreIfTimezoneReady()
          }
          self.isRefreshing = false
          if !contextStillCurrent
            || (!context.includesYear && self.needsYearRefresh(context: UsageDateContext()))
          {
            self.refreshNow()
          }
        }
      }
    }
  }

  private func handleSystemTimeZoneChange() {
    clearPublishedUsage()
    timezoneRefreshState.markTimezoneChange()
    refreshNow()
  }

  private func persistTimezoneRefreshState() {
    if let lastSuccessfulTimeZone = timezoneRefreshState.lastSuccessfulTimeZone {
      defaults.set(lastSuccessfulTimeZone, forKey: DefaultsKey.lastUsageTimeZone)
    }
    if let lastInvalidatedTimeZone = timezoneRefreshState.lastInvalidatedTimeZone {
      defaults.set(
        lastInvalidatedTimeZone,
        forKey: DefaultsKey.lastUsageInvalidatedTimeZone)
    }
  }

  private func clearPublishedUsage() {
    menuTotalText = Formatters.currencyString(0)
    cumulativeSeries = []
    dailySeries = []
    monthlySeries = []
    toolTotals = []
    modelCumulativeSeries = []
    modelDailySeries = []
    modelMonthlySeries = []
    modelTotals = []
    machineCumulativeSeries = []
    machineDailySeries = []
    machineMonthlySeries = []
    machineTotals = []
    lastUpdated = nil
    lastYearRefresh = nil
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

  // The snapshot remembers its server, so labels from a previously configured
  // server are never shown against the current one.
  var machineLabels: [String: String] {
    machineLabelSnapshot?.labels(forConfiguredServerURL: agentsviewServerURL) ?? [:]
  }

  var hasDiscoveryCache: Bool {
    agentPreferences.hasDiscoveryCache
  }

  func isAgentEnabled(_ agent: UsageAgent) -> Bool {
    !disabledAgentIDs.contains(agent.rawValue)
  }

  func setAgent(_ agent: UsageAgent, enabled: Bool) {
    if enabled {
      disabledAgentIDs.remove(agent.rawValue)
    } else {
      disabledAgentIDs.insert(agent.rawValue)
    }
    agentPreferences.saveDisabledAgentIDs(disabledAgentIDs)
    reloadFromStoreIfTimezoneReady()
  }

  private var activeTools: [UsageAgent] {
    AgentPreferences.enabledAgents(
      from: discoveredAgents,
      disabledAgentIDs: disabledAgentIDs)
  }

  private func reloadFromStore(context: UsageDateContext = UsageDateContext()) {
    let tools = activeTools
    let startOfDay = context.startOfToday
    let now = context.now
    var cumulativePoints: [UsageSeriesPoint] = []

    for tool in tools {
      let samples = store.fetchSamples(tool: tool, from: startOfDay, to: now)
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

    let displayContext = UsageDateContext(
      now: context.now, timeZone: context.timeZone, includesYear: chartMode == .oneYear)
    chartDateContext = displayContext
    let sinceKey = displayContext.usageWindowStartKey
    let rollups = store.fetchDailyRollups(
      since: sinceKey,
      through: context.todayKey,
      timeZone: context.timeZone)
    dailySeries = rollups.compactMap { rollup in
      guard
        tools.contains(rollup.tool),
        let date = DateHelper.date(fromKey: rollup.dateKey, in: context.timeZone)
      else {
        return nil
      }
      return UsageSeriesPoint(tool: rollup.tool, date: date, cost: rollup.totalCost)
    }

    let modelRollups = store.fetchModelDailyRollups(
      since: sinceKey,
      through: context.todayKey,
      tools: tools,
      timeZone: context.timeZone)
    modelDailySeries = aggregateModelDailySeries(
      modelRollups,
      timeZone: context.timeZone)
    let machineRollups = store.fetchMachineDailyRollups(
      since: sinceKey,
      through: context.todayKey,
      tools: tools,
      timeZone: context.timeZone)
    machineDailySeries = UsageSeriesAggregation.dailyMachineSeries(
      from: machineRollups,
      timeZone: context.timeZone)
    if chartMode == .oneYear {
      monthlySeries = UsageSeriesAggregation.monthlySeries(
        from: dailySeries, context: displayContext)
      modelMonthlySeries = UsageSeriesAggregation.monthlySeries(
        from: modelDailySeries, context: displayContext)
      machineMonthlySeries = UsageSeriesAggregation.monthlySeries(
        from: machineDailySeries, context: displayContext)
    }

    var totals: [ToolTotal] = []
    for tool in tools {
      let dailyTotal = store.dailyTotal(for: context.todayKey, tool: tool)
      let totalCost =
        dailyTotal ?? store.latestSample(
          tool: tool,
          from: context.startOfToday,
          to: context.startOfNextDay)?.totalCost ?? 0
      totals.append(ToolTotal(tool: tool, totalCost: totalCost))
    }
    toolTotals = totals
    modelTotals = aggregateModelTotals(modelRollups, todayKey: context.todayKey)
    machineTotals = UsageSeriesAggregation.machineTotals(
      from: machineRollups, dateKey: context.todayKey)
    let combined = totals.reduce(0) { $0 + $1.totalCost }
    menuTotalText = Formatters.currencyString(combined)
  }

  private func reloadFromStoreIfTimezoneReady() {
    let context = UsageDateContext()
    guard !timezoneRefreshState.shouldDeferStoreReload(for: context.timeZone.identifier) else {
      return
    }
    reloadFromStore(context: context)
  }

  private func aggregateModelDailySeries(
    _ rollups: [ModelDailyRollup],
    timeZone: TimeZone
  ) -> [UsageSeriesPoint] {
    var totalsByDateAndModel: [ModelDailyKey: Double] = [:]
    for rollup in rollups {
      let key = ModelDailyKey(dateKey: rollup.dateKey, modelName: rollup.modelName)
      totalsByDateAndModel[key, default: 0] += rollup.totalCost
    }

    return totalsByDateAndModel.compactMap { key, totalCost in
      guard let date = DateHelper.date(fromKey: key.dateKey, in: timeZone) else {
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

    DispatchQueue.global(qos: .background).async { [combinedStore, nonAutomatedStore] in
      do {
        let dateUpdated = try [combinedStore, nonAutomatedStore].reduce(0) { total, store in
          total
            + (try store.storedAgents().reduce(0) { count, tool in
              count + (try store.normalizeDailyRollupDates(for: tool))
                + (try store.normalizeModelDailyRollupDates(for: tool))
                + (try store.normalizeMachineDailyRollupDates(for: tool))
            })
        }
        let message =
          "Maintenance complete. Normalized \(dateUpdated) daily totals."
        let now = Date()
        DispatchQueue.main.async {
          self.maintenanceMessage = message
          self.lastMaintenanceAt = now
          self.defaults.set(now.timeIntervalSince1970, forKey: DefaultsKey.lastMaintenanceAt)
          self.reloadFromStoreIfTimezoneReady()
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
    timer.schedule(
      deadline: .now() + .seconds(intervalSeconds), repeating: .seconds(intervalSeconds))
    timer.setEventHandler { [weak self] in
      Task { @MainActor in
        self?.refreshNow(refreshHistory: false)
      }
    }
    timer.resume()
    self.timer = timer
  }

  private enum DefaultsKey {
    static let welcomeKey = "hasSeenWelcome"
    static let refreshMinutes = "refreshMinutes"
    static let includeAutomatedSessions = "includeAutomatedSessions"
    static let refreshInterval = "refreshInterval"
    static let agentsviewPath = "agentsviewPath"
    static let agentsviewServerURL = "agentsviewServerURL"
    static let machineLabels = "machineLabels"
    static let maintenanceMode = "maintenanceMode"
    static let lastMaintenanceAt = "lastMaintenanceAt"
    static let lastUsageTimeZone = "lastUsageTimeZone"
    static let lastUsageInvalidatedTimeZone = "lastUsageInvalidatedTimeZone"
  }
}
