import Foundation

struct AgentPreferences {
  private let defaults: UserDefaults

  init(defaults: UserDefaults) {
    self.defaults = defaults
  }

  var hasDiscoveryCache: Bool {
    defaults.object(forKey: Keys.discoveredAgentIDs) != nil
  }

  func loadDiscoveredAgents() -> [UsageAgent] {
    let ids = defaults.stringArray(forKey: Keys.discoveredAgentIDs) ?? []
    return Set(ids.filter { !$0.isEmpty }).map(UsageAgent.init).sorted()
  }

  func saveDiscoveredAgents(_ agents: [UsageAgent]) {
    defaults.set(agents.map(\.rawValue).sorted(), forKey: Keys.discoveredAgentIDs)
  }

  func loadDisabledAgentIDs() -> Set<String> {
    Set((defaults.stringArray(forKey: Keys.disabledAgentIDs) ?? []).filter { !$0.isEmpty })
  }

  func saveDisabledAgentIDs(_ ids: Set<String>) {
    defaults.set(ids.sorted(), forKey: Keys.disabledAgentIDs)
  }

  func migrateLegacyPreferences() {
    var disabled = loadDisabledAgentIDs()
    for (legacyKey, agentID) in Keys.legacyAgents {
      if let enabled = defaults.object(forKey: legacyKey) as? Bool, !enabled {
        disabled.insert(agentID)
      }
      defaults.removeObject(forKey: legacyKey)
    }
    saveDisabledAgentIDs(disabled)
  }

  static func enabledAgents(
    from discoveredAgents: [UsageAgent],
    disabledAgentIDs: Set<String>
  ) -> [UsageAgent] {
    discoveredAgents.filter { !disabledAgentIDs.contains($0.rawValue) }
  }

  private enum Keys {
    static let discoveredAgentIDs = "discoveredAgentIDs"
    static let disabledAgentIDs = "disabledAgentIDs"
    static let legacyAgents = [
      ("includeClaude", "claude"),
      ("includeCodex", "codex"),
      ("includePi", "pi"),
      ("includeOMP", "omp"),
      ("includeGemini", "gemini"),
      ("includeOpenCode", "opencode"),
    ]
  }
}
