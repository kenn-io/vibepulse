import Combine
import Foundation
import XCTest

@testable import VibePulse

final class ServerAuthenticationTests: XCTestCase {
  @MainActor
  func testChangingServersLoadsTheirOwnTokenAndInvalidatesUsage() async throws {
    let suite = "VibePulseTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: "hasSeenWelcome")
    defaults.set("manual", forKey: "maintenanceMode")
    defaults.set("https://archive.example.com", forKey: "agentsviewServerURL")
    let tokens = MemoryServerTokens()
    tokens.tokens["https://archive.example.com"] = "stored-token"
    let model = AppModel(
      defaults: defaults, store: try UsageStore(path: ":memory:"), serverTokens: tokens,
      fetcher: UsageFetcher(requestLoader: { _ in Data(#"{"daily":[]}"#.utf8) }))
    let finished = expectation(description: "initial refresh")
    let subscription = model.$isRefreshing.filter { !$0 }.first().sink { _ in finished.fulfill() }
    await fulfillment(of: [finished], timeout: 3)
    withExtendedLifetime(subscription) {}

    XCTAssertEqual(model.agentsviewServerToken, "stored-token")
    model.setServerToken(" edited-token\n")
    XCTAssertEqual(try tokens.read(server: "https://archive.example.com"), "edited-token")
    XCTAssertTrue(defaults.bool(forKey: "usageSourceNeedsInvalidation"))
    model.agentsviewServerURL = "https://other.example.com"
    XCTAssertEqual(model.agentsviewServerToken, "")
    model.agentsviewServerURL = "https://archive.example.com"
    XCTAssertEqual(model.agentsviewServerToken, "edited-token")
    model.setServerToken("")
    XCTAssertEqual(try tokens.read(server: "https://archive.example.com"), "")

    tokens.readError = NSError(
      domain: "TokenTests", code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Keychain unavailable"])
    model.agentsviewServerURL = "https://other.example.com"
    XCTAssertEqual(model.agentsviewServerToken, "")
    XCTAssertEqual(model.serverTokenError, "Keychain unavailable")
    tokens.writeError = tokens.readError
    model.setServerToken("unsaved-token")
    XCTAssertEqual(model.agentsviewServerToken, "")
    XCTAssertEqual(model.serverTokenError, "Keychain unavailable")
    XCTAssertNil(tokens.tokens["https://other.example.com"])
  }

  func testUsageAndMachineRequestsCarryTheCapturedToken() throws {
    var requests: [URLRequest] = []
    let fetcher = UsageFetcher(requestLoader: { request in
      requests.append(request)
      if request.url!.path == "/api/v1/machines" {
        return Data(#"{"machines":[],"machine_labels":{}}"#.utf8)
      }
      return Data(
        #"{"daily":[{"date":"2026-08-10","totalCost":7,"agentBreakdowns":[{"agent":"codex","cost":7}]}]}"#
          .utf8)
    })
    let context = UsageDateContext(
      serverURL: "https://archive.example.com", serverToken: "test-server-token")
    XCTAssertEqual(try fetcher.discoverAgents(using: context), [.codex])
    XCTAssertEqual(try fetcher.fetchDailyTotals(for: .codex, using: context).map(\.cost), [7])
    _ = try fetcher.fetchMachineLabels(using: context)
    XCTAssertEqual(
      requests.map { $0.value(forHTTPHeaderField: "Authorization") },
      [
        "Bearer test-server-token", "Bearer test-server-token", "Bearer test-server-token",
      ])
    XCTAssertEqual(
      requests.map { $0.url!.path },
      [
        "/api/v1/usage/summary", "/api/v1/usage/summary", "/api/v1/machines",
      ])
  }

  func testAnonymousServerRequestsHaveNoAuthorizationHeader() throws {
    let fetcher = UsageFetcher(requestLoader: { request in
      XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
      return Data(#"{"daily":[]}"#.utf8)
    })
    XCTAssertEqual(
      try fetcher.discoverAgents(using: UsageDateContext(serverURL: "https://archive.example.com")),
      [])
  }
}
