import XCTest

@testable import VibePulse

final class AgentPreferencesTests: XCTestCase {
  func testNewlyDiscoveredAgentDefaultsToEnabled() throws {
    let defaults = try makeDefaults()
    let preferences = AgentPreferences(defaults: defaults)
    let agent = UsageAgent("future-agent")

    preferences.saveDiscoveredAgents([agent])

    XCTAssertEqual(preferences.loadDiscoveredAgents(), [agent])
    XCTAssertFalse(preferences.loadDisabledAgentIDs().contains(agent.rawValue))
  }

  func testDisabledPreferenceSurvivesDisappearanceAndRediscovery() throws {
    let defaults = try makeDefaults()
    let preferences = AgentPreferences(defaults: defaults)
    let agent = UsageAgent("future-agent")

    preferences.saveDisabledAgentIDs([agent.rawValue])
    preferences.saveDiscoveredAgents([])
    preferences.saveDiscoveredAgents([agent])

    XCTAssertEqual(preferences.loadDiscoveredAgents(), [agent])
    XCTAssertEqual(preferences.loadDisabledAgentIDs(), [agent.rawValue])
  }

  func testLegacyFalseTogglesMigrateIntoDisabledAgentIDs() throws {
    let defaults = try makeDefaults()
    defaults.set(false, forKey: "includeGemini")
    defaults.set(false, forKey: "includeOpenCode")
    defaults.set(true, forKey: "includeClaude")
    let preferences = AgentPreferences(defaults: defaults)

    preferences.migrateLegacyPreferences()

    XCTAssertEqual(preferences.loadDisabledAgentIDs(), ["gemini", "opencode"])
    XCTAssertNil(defaults.object(forKey: "includeGemini"))
    XCTAssertNil(defaults.object(forKey: "includeOpenCode"))
    XCTAssertNil(defaults.object(forKey: "includeClaude"))
  }

  func testEnabledAgentsExcludeDisabledWithoutRemovingDiscovery() {
    let hidden = UsageAgent("hidden-agent")
    let visible = UsageAgent("visible-agent")
    let discovered = [hidden, visible]

    let enabled = AgentPreferences.enabledAgents(
      from: discovered,
      disabledAgentIDs: [hidden.rawValue])

    XCTAssertEqual(enabled, [visible])
    XCTAssertEqual(discovered, [hidden, visible])
  }

  private func makeDefaults() throws -> UserDefaults {
    let suiteName = "AgentPreferencesTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }
}
