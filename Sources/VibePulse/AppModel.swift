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
      if agentsviewPath != oldValue { sourceConfigurationChanged() }
    }
  }
  @Published var agentsviewServerURL: String {
    didSet {
      defaults.set(
        agentsviewServerURL, forKey: DefaultsKey.agentsviewServerURL
      )
      if agentsviewServerURL != oldValue { sourceConfigurationChanged() }
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
  private var pendingRefresh: (now: Date, refreshHistory: Bool)?
  private var sourceNeedsInvalidation = false
  private let fetcher: UsageFetching
  private var isFetchingMachineLabels = false

  init(
    defaults: UserDefaults = .standard,
    store suppliedStore: UsageStore? = nil,
    nonAutomatedStore suppliedNonAutomatedStore: UsageStore? = nil,
    fetcher: UsageFetching = UsageFetcher()
  ) {
    self.defaults = defaults
    self.fetcher = fetcher
    sourceNeedsInvalidation = defaults.bool(forKey: DefaultsKey.sourceNeedsInvalidation)
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
    if !sourceNeedsInvalidation,
      !timezoneRefreshState.shouldInvalidateCurrentDay(
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
    // Keep the newest request and any explicit request for history. Repeated menu
    // opens while busy need one follow-up, not one request per open or no request.
    pendingRefresh = (now, refreshHistory || (pendingRefresh?.refreshHistory ?? false))
    guard !isRefreshing else { return }
    isRefreshing = true
    Task {
      while let request = pendingRefresh {
        pendingRefresh = nil
        await refreshUsage(now: request.now, refreshHistory: request.refreshHistory)
      }
      isRefreshing = false
    }
  }

  private func sourceConfigurationChanged() {
    sourceConfigurationGeneration += 1
    sourceNeedsInvalidation = true
    defaults.set(true, forKey: DefaultsKey.sourceNeedsInvalidation)
    clearPublishedUsage()
    if isRefreshing { refreshNow(refreshHistory: false) }
  }

  private func refreshUsage(now: Date, refreshHistory: Bool) async {
    statusMessage = nil
    let sourceGeneration = sourceConfigurationGeneration
    let includeYear =
      (refreshHistory && chartMode == .oneYear)
      || needsYearRefresh(context: UsageDateContext(now: now))
    let context = UsageDateContext(
      now: now, includesYear: includeYear,
      serverURL: agentsviewServerURL.trimmingCharacters(in: .whitespacesAndNewlines),
      agentsviewPath: agentsviewPath)
    let retainedAgents = !includeYear && lastYearRefresh != nil ? discoveredAgents : []
    let previousAgents = discoveredAgents
    if includeYear { lastYearRefresh = nil }
    let invalidateCurrentDay = timezoneRefreshState.shouldInvalidateCurrentDay(
      for: context.timeZone.identifier)
    if invalidateCurrentDay { clearPublishedUsage() }

    if sourceNeedsInvalidation || invalidateCurrentDay {
      // A source change invalidates the entire displayed history, including the
      // inactive scope. Wait for obsolete writes before clearing either cache.
      let invalidationContext = UsageDateContext(
        now: now, timeZone: context.timeZone,
        includesYear: sourceNeedsInvalidation || context.includesYear)
      let invalidation = await Task.detached(priority: .userInitiated) {
        [combinedStore, nonAutomatedStore] in
        Result {
          for store in [combinedStore, nonAutomatedStore] {
            try store.deleteCurrentDaySamples(using: invalidationContext)
            try store.deleteRefreshWindowRollups(using: invalidationContext)
          }
        }
      }.value
      guard refreshContextIsCurrent(context, sourceGeneration: sourceGeneration) else { return }
      do {
        try invalidation.get()
        sourceNeedsInvalidation = false
        defaults.set(false, forKey: DefaultsKey.sourceNeedsInvalidation)
      } catch {
        statusMessage = error.localizedDescription
        return
      }
    }

    refreshMachineLabels(context: context, sourceGeneration: sourceGeneration)
    // Prioritize the visible history, then update the other cache without holding
    // the first result off screen. CLI mode only supports the combined history.
    let scopes =
      context.serverURL.isEmpty ? [true] : [effectiveIncludeAutomated, !effectiveIncludeAutomated]
    var succeeded: [UsageRefreshResult] = []
    var errors: [String] = []
    for includeAutomated in scopes {
      let service = includeAutomated ? refreshService : nonAutomatedRefreshService
      let scopeContext = UsageDateContext(
        now: context.now, timeZone: context.timeZone, includesYear: context.includesYear,
        includeAutomated: includeAutomated, serverURL: context.serverURL,
        agentsviewPath: context.agentsviewPath)
      let report = await Task.detached(priority: .userInitiated) {
        Result { try service.refresh(context: scopeContext, retainedAgents: retainedAgents) }
      }.value
      guard refreshContextIsCurrent(context, sourceGeneration: sourceGeneration) else { return }
      switch report {
      case .success(let result):
        succeeded.append(result)
        errors += result.importErrors
        if let labels = result.machineLabels { publishMachineLabels(labels) }
        // Keep the other scope's agents until its discovery has completed.
        let agents = Array(Set(succeeded.flatMap(\.discoveredAgents) + previousAgents)).sorted()
        let agentsChanged = discoveredAgents != agents
        discoveredAgents = agents
        timezoneRefreshState.completeRefresh(
          for: context.timeZone.identifier, invalidatedCurrentDay: invalidateCurrentDay,
          hasImportErrors: !errors.isEmpty)
        persistTimezoneRefreshState()
        if includeAutomated == effectiveIncludeAutomated || agentsChanged {
          reloadFromStore(context: UsageDateContext())
        }
      case .failure(let error):
        errors.append(
          (includeAutomated ? "" : "Without automated sessions: ") + error.localizedDescription)
      }
    }
    if !succeeded.isEmpty {
      let keptAgents = succeeded.count < scopes.count ? previousAgents : []
      let agents = Array(Set(succeeded.flatMap(\.discoveredAgents) + keptAgents)).sorted()
      let agentsChanged = discoveredAgents != agents
      discoveredAgents = agents
      agentPreferences.saveDiscoveredAgents(discoveredAgents)
      if agentsChanged { reloadFromStore(context: UsageDateContext()) }
    }
    statusMessage = errors.isEmpty ? nil : errors.joined(separator: " | ")
    if errors.isEmpty {
      lastUpdated = context.now
      if context.includesYear { lastYearRefresh = context }
    }
    if !context.includesYear && needsYearRefresh(context: UsageDateContext()) {
      refreshNow(refreshHistory: false)
    }
  }

  private func refreshContextIsCurrent(
    _ context: UsageDateContext, sourceGeneration: Int
  ) -> Bool {
    let timezoneChanged = UsageDateContext().timeZone.identifier != context.timeZone.identifier
    if timezoneChanged {
      clearPublishedUsage()
      timezoneRefreshState.markTimezoneChange()
    }
    guard !timezoneChanged, sourceGeneration == sourceConfigurationGeneration else {
      if pendingRefresh == nil { refreshNow(refreshHistory: false) }
      return false
    }
    return true
  }

  private func refreshMachineLabels(context: UsageDateContext, sourceGeneration: Int) {
    guard !context.serverURL.isEmpty, !isFetchingMachineLabels else { return }
    isFetchingMachineLabels = true
    Task { [weak self, fetcher] in
      let labels = await Task.detached(priority: .utility) {
        try? fetcher.fetchMachineLabels(using: context)
      }.value
      guard let self else { return }
      self.isFetchingMachineLabels = false
      guard self.sourceConfigurationGeneration == sourceGeneration else {
        self.refreshMachineLabels(
          context: UsageDateContext(
            serverURL: self.agentsviewServerURL.trimmingCharacters(in: .whitespacesAndNewlines)),
          sourceGeneration: self.sourceConfigurationGeneration)
        return
      }
      if let labels { self.publishMachineLabels(labels) }
    }
  }

  private func publishMachineLabels(_ labels: MachineLabels) {
    machineLabelSnapshot = labels
    defaults.set(try? JSONEncoder().encode(labels), forKey: DefaultsKey.machineLabels)
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
    guard !sourceNeedsInvalidation,
      !timezoneRefreshState.shouldDeferStoreReload(for: context.timeZone.identifier)
    else {
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
    static let sourceNeedsInvalidation = "usageSourceNeedsInvalidation"
    static let machineLabels = "machineLabels"
    static let maintenanceMode = "maintenanceMode"
    static let lastMaintenanceAt = "lastMaintenanceAt"
    static let lastUsageTimeZone = "lastUsageTimeZone"
    static let lastUsageInvalidatedTimeZone = "lastUsageInvalidatedTimeZone"
  }
}
