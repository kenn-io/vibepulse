# Dynamic agentsview Agent Discovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace VibePulse's compiled six-agent list with usage-driven discovery so every positive-cost agent reported by the installed agentsview version works automatically and can be hidden without stopping imports.

**Architecture:** Introduce a dynamic string-backed `UsageAgent`, discover qualifying identifiers from one aggregate `agentsview usage daily --json --breakdown --since 30d` call, then import every discovered agent from the same post-sync snapshot. Persist the last successful discovery set and explicit disabled IDs in `UserDefaults`; use disabled state only when reading data for presentation, never when importing or retaining it.

**Tech Stack:** Swift 5.9 package targeting macOS 13, SwiftUI, Swift Charts, Foundation `Process`, SQLite3, XCTest, agentsview usage JSON.

## Global Constraints

- VibePulse must not maintain a functional allowlist of supported agent identifiers.
- Discovery includes only agents whose summed agentsview cost is greater than zero in the explicit rolling `--since 30d` window.
- Newly discovered agents are enabled automatically.
- Disabled agents continue to import and remain stored; disabling affects totals, charts, legends, and breakdowns only.
- Agents that leave the discovery window disappear from Settings but retain stored usage and their disabled preference.
- Existing false values for the six legacy toggles migrate once into the dynamic disabled-ID set; remove the old keys after translation and do not retain dual reads or writes.
- One aggregate discovery command performs agentsview's on-demand sync; filtered per-agent commands use `--no-sync`.
- Unknown non-empty identifiers from agentsview or SQLite remain valid throughout commands, preferences, storage, maintenance, aggregation, and UI.
- Cosmetic display-name mappings may exist, but missing mappings cannot affect functionality.
- No SQLite schema migration is required because current tables already store agent identifiers as text.
- Test owned business logic and integration seams only; do not add tests that assert deleted symbols or preference keys remain absent.

---

## File Structure

### New files

- `Sources/VibePulse/Services/AgentPreferences.swift`
  - Owns dynamic discovery/disabled preference persistence and the one-time legacy-toggle migration.
- `Sources/VibePulse/Services/UsageRefreshService.swift`
  - Owns synchronous discover-then-import orchestration independently of `AppModel` and UI state.
- `Tests/VibePulseTests/AgentPreferencesTests.swift`
  - Covers default-enabled semantics, disappearance/reappearance, persistence, and legacy migration.
- `Tests/VibePulseTests/UsageRefreshServiceTests.swift`
  - Covers import-all behavior, independent agent failures, and discovery failure behavior.

### Renamed file

- Rename `Sources/VibePulse/Models/UsageTool.swift` to `Sources/VibePulse/Models/UsageAgent.swift`
  - Replaces the closed enum with the dynamic agent value and command construction.
- Rename `Tests/VibePulseTests/UsageToolTests.swift` to `Tests/VibePulseTests/UsageAgentTests.swift`
  - Covers arbitrary identifiers, labels, sorting, and exact command arguments.

### Modified files

- `Sources/VibePulse/Models/UsageModels.swift`
  - Changes all agent-bearing types and series keys from `UsageTool` to `UsageAgent`.
- `Sources/VibePulse/Services/UsageFetcher.swift`
  - Adds aggregate discovery parsing, a fetch protocol, and shared retry behavior.
- `Sources/VibePulse/Services/UsageStore.swift`
  - Accepts dynamic agents, reads unknown identifiers, exposes stored agents for maintenance, and sorts deterministically.
- `Sources/VibePulse/AppModel.swift`
  - Replaces six booleans with discovered agents plus a disabled-ID set, invokes `UsageRefreshService`, and filters only at presentation time.
- `Sources/VibePulse/Utils/HourlyUsageInferer.swift`
  - Accepts `UsageAgent`.
- `Sources/VibePulse/Utils/UsageSeriesAggregation.swift`
  - Keys model high-water state by `UsageAgent`.
- `Sources/VibePulse/Views/SettingsView.swift`
  - Renders dynamic discovered-agent checkboxes and discovery empty/loading copy.
- `Sources/VibePulse/Views/WelcomeView.swift`
  - States agentsview-driven compatibility instead of an exhaustive six-agent list.
- `README.md`
  - Documents dynamic support, 30-day positive-cost discovery, disabled-agent retention, and troubleshooting.
- Existing tests under `Tests/VibePulseTests/`
  - Replace enum literals with dynamic `UsageAgent` constants and add focused arbitrary-agent coverage.

---

### Task 1: Introduce the Dynamic Agent Domain Type

**Files:**
- Rename: `Sources/VibePulse/Models/UsageTool.swift` → `Sources/VibePulse/Models/UsageAgent.swift`
- Rename: `Tests/VibePulseTests/UsageToolTests.swift` → `Tests/VibePulseTests/UsageAgentTests.swift`
- Modify: `Sources/VibePulse/Models/UsageModels.swift`
- Modify: `Sources/VibePulse/Utils/HourlyUsageInferer.swift`
- Modify: `Sources/VibePulse/Utils/UsageSeriesAggregation.swift`
- Modify: `Tests/VibePulseTests/HourlyUsageInfererTests.swift`
- Modify: `Tests/VibePulseTests/UsageSeriesAggregationTests.swift`
- Modify: `Tests/VibePulseTests/UsageSeriesFiltersTests.swift`
- Modify: `Tests/VibePulseTests/UsageSeriesPaletteTests.swift`

**Interfaces:**
- Produces: `struct UsageAgent: Hashable, Identifiable, Comparable, Sendable`
- Produces: `UsageAgent.init(_ rawValue: String)` for non-empty exact identifiers.
- Produces: `UsageAgent.rawValue`, `id`, `displayName`, `shortName`, `dailyCommand`, and static `discoveryCommand`.
- Produces: known convenience constants `.claude`, `.codex`, `.pi`, `.omp`, `.gemini`, `.openCode` for readability only; arbitrary identifiers require no registration.
- Produces: `UsageSeriesKey.agent(_ agent: UsageAgent)` and `UsageSeriesKey.agent` lookup.

- [ ] **Step 1: Rename the source and test files**

Run:

```bash
mv Sources/VibePulse/Models/UsageTool.swift Sources/VibePulse/Models/UsageAgent.swift
mv Tests/VibePulseTests/UsageToolTests.swift Tests/VibePulseTests/UsageAgentTests.swift
```

Expected: both files exist under their new names and SwiftPM continues discovering them automatically.

- [ ] **Step 2: Replace the old fixed-list tests with failing dynamic-agent tests**

Replace `Tests/VibePulseTests/UsageAgentTests.swift` with:

```swift
import XCTest

@testable import VibePulse

final class UsageAgentTests: XCTestCase {
  func testArbitraryAgentPreservesExactIdentifierInDailyCommand() {
    let agent = UsageAgent("future-agent_v2")

    XCTAssertEqual(agent.rawValue, "future-agent_v2")
    XCTAssertEqual(
      agent.dailyCommand,
      [
        "agentsview", "usage", "daily", "--json", "--agent", "future-agent_v2",
        "--since", "30d", "--no-sync",
      ])
  }

  func testDiscoveryCommandRequestsAgentBreakdownsForThirtyDays() {
    XCTAssertEqual(
      UsageAgent.discoveryCommand,
      ["agentsview", "usage", "daily", "--json", "--breakdown", "--since", "30d"])
  }

  func testKnownAndGeneratedDisplayNamesArePresentationOnly() {
    XCTAssertEqual(UsageAgent.claude.displayName, "Claude Code")
    XCTAssertEqual(UsageAgent.omp.displayName, "OhMyPi")
    XCTAssertEqual(UsageAgent("future-agent").displayName, "Future Agent")
  }

  func testAgentsSortByDisplayNameThenRawIdentifier() {
    let agents = [UsageAgent("zeta"), .claude, UsageAgent("alpha")]

    XCTAssertEqual(agents.sorted().map(\.rawValue), ["alpha", "claude", "zeta"])
  }
}
```

- [ ] **Step 3: Run the renamed test to verify it fails**

Run:

```bash
swift test --filter UsageAgentTests
```

Expected: FAIL because `UsageAgent` and its dynamic interfaces do not exist yet.

- [ ] **Step 4: Implement `UsageAgent` as a dynamic value**

Replace `Sources/VibePulse/Models/UsageAgent.swift` with:

```swift
import Foundation

struct UsageAgent: Hashable, Identifiable, Comparable, Sendable {
  let rawValue: String

  init(_ rawValue: String) {
    precondition(!rawValue.isEmpty, "UsageAgent identifiers must not be empty")
    self.rawValue = rawValue
  }

  var id: String { rawValue }

  var displayName: String {
    Self.knownDisplayNames[rawValue] ?? Self.generatedDisplayName(from: rawValue)
  }

  var shortName: String {
    rawValue == "claude" ? "CC" : displayName
  }

  var dailyCommand: [String] {
    [
      "agentsview", "usage", "daily", "--json", "--agent", rawValue,
      "--since", "30d", "--no-sync",
    ]
  }

  static let discoveryCommand = [
    "agentsview", "usage", "daily", "--json", "--breakdown", "--since", "30d",
  ]

  static let claude = UsageAgent("claude")
  static let codex = UsageAgent("codex")
  static let pi = UsageAgent("pi")
  static let omp = UsageAgent("omp")
  static let gemini = UsageAgent("gemini")
  static let openCode = UsageAgent("opencode")

  static func < (lhs: UsageAgent, rhs: UsageAgent) -> Bool {
    let lhsName = lhs.displayName.lowercased()
    let rhsName = rhs.displayName.lowercased()
    if lhsName == rhsName {
      return lhs.rawValue < rhs.rawValue
    }
    return lhsName < rhsName
  }

  private static let knownDisplayNames = [
    "claude": "Claude Code",
    "codex": "Codex",
    "pi": "Pi",
    "omp": "OhMyPi",
    "gemini": "Gemini",
    "opencode": "OpenCode",
  ]

  private static func generatedDisplayName(from rawValue: String) -> String {
    rawValue
      .replacingOccurrences(of: "_", with: "-")
      .split(separator: "-")
      .map { word in
        word.prefix(1).uppercased() + String(word.dropFirst())
      }
      .joined(separator: " ")
  }
}
```

The convenience constants are not a support registry. They exist only to keep known-agent call sites and tests readable.

- [ ] **Step 5: Replace `UsageTool` types throughout the domain layer**

In `Sources/VibePulse/Models/UsageModels.swift`:

- Change `UsageSeriesKey.agent(_ tool: UsageTool)` to `UsageSeriesKey.agent(_ agent: UsageAgent)`.
- Replace the computed `tool: UsageTool?` with:

```swift
var agent: UsageAgent? {
  guard kind == .agent, !value.isEmpty else { return nil }
  return UsageAgent(value)
}
```

- Change agent sorting to:

```swift
case .agent:
  return "000-\(agent?.displayName.lowercased() ?? value.lowercased())-\(value)"
```

- Change every `UsageTool` property or initializer argument in `UsageSample`, `ModelUsageSample`, `DailyRollup`, `ModelDailyRollup`, `UsageSeriesPoint`, and `ToolTotal` to `UsageAgent`.
- Rename their computed `tool` accessors to `agent` and return `series.agent`.

In `Sources/VibePulse/Utils/HourlyUsageInferer.swift`, use this signature and initializer:

```swift
static func inferPoints(
  agent: UsageAgent,
  samples: [UsageSample],
  startOfDay: Date,
  end: Date
) -> [UsageSeriesPoint]
```

and create points with `UsageSeriesPoint(agent: agent, date: date, cost: ...)`.

In `Sources/VibePulse/Utils/UsageSeriesAggregation.swift`, change:

```swift
var highWaterByAgent: [UsageAgent: Double] = [:]
```

and key it with `sample.agent`.

- [ ] **Step 6: Update existing unit-test fixtures to the new labels**

Across the affected tests:

- Replace `tool:` with `agent:` in usage model initializers.
- Replace `UsageSeriesPoint(tool:` with `UsageSeriesPoint(agent:`.
- Replace `\.tool` assertions with `\.agent`.
- Keep `.claude`, `.codex`, `.pi`, and `.openCode` convenience constants where useful.

Add this focused arbitrary-agent assertion to `Tests/VibePulseTests/UsageSeriesFiltersTests.swift`:

```swift
func testVisibleDailySeriesAcceptsUnknownAgentIdentifiers() {
  let today = DateHelper.date(fromKey: DateHelper.dateKey(for: Date()))!
  let future = UsageAgent("future-agent")
  let points = [UsageSeriesPoint(agent: future, date: today, cost: 1)]

  let visible = UsageSeriesFilters.visibleDailySeries(points, mode: .sevenDays)

  XCTAssertEqual(visible.map(\.agent), [future])
}
```

- [ ] **Step 7: Run the focused domain tests**

Run:

```bash
swift test --filter 'UsageAgentTests|HourlyUsageInfererTests|UsageSeriesAggregationTests|UsageSeriesFiltersTests|UsageSeriesPaletteTests'
```

Expected: PASS for all selected tests.

- [ ] **Step 8: Commit the dynamic domain type**

```bash
git add Sources/VibePulse/Models Sources/VibePulse/Utils \
  Tests/VibePulseTests/UsageAgentTests.swift \
  Tests/VibePulseTests/HourlyUsageInfererTests.swift \
  Tests/VibePulseTests/UsageSeriesAggregationTests.swift \
  Tests/VibePulseTests/UsageSeriesFiltersTests.swift \
  Tests/VibePulseTests/UsageSeriesPaletteTests.swift
git commit -m "Replace fixed usage tools with dynamic agents"
```

---

### Task 2: Add Aggregate Agent Discovery to `UsageFetcher`

**Files:**
- Modify: `Sources/VibePulse/Services/UsageFetcher.swift`
- Modify: `Tests/VibePulseTests/UsageFetcherTests.swift`

**Interfaces:**
- Produces: `protocol UsageFetching: Sendable` with `discoverAgents()` and `fetchDailyTotals(for:)`.
- Produces: `UsageFetcher.discoverAgents() throws -> [UsageAgent]`.
- Produces: `UsageFetcher.parseDiscoveredAgents(data:) throws -> [UsageAgent]`.
- Consumes: `UsageAgent.discoveryCommand` and `UsageAgent.dailyCommand` from Task 1.

- [ ] **Step 1: Write failing discovery parser tests**

Append to `Tests/VibePulseTests/UsageFetcherTests.swift`:

```swift
func testParseDiscoveredAgentsSumsThirtyDayBreakdownsAndDropsZeroCostAgents() throws {
  let json = """
    {
      "daily": [
        {
          "date": "2026-07-01",
          "agentBreakdowns": [
            { "agent": "claude", "cost": 2.5 },
            { "agent": "future-agent", "cost": 0 }
          ]
        },
        {
          "date": "2026-07-02",
          "agentBreakdowns": [
            { "agent": "claude", "cost": 1.5 },
            { "agent": "future-agent", "cost": 3 }
          ]
        }
      ]
    }
    """

  let agents = try UsageFetcher.parseDiscoveredAgents(
    data: try XCTUnwrap(json.data(using: .utf8)))

  XCTAssertEqual(agents.map(\.rawValue), ["claude", "future-agent"])
}

func testParseDiscoveredAgentsReturnsEmptyForValidEmptyReport() throws {
  let data = try XCTUnwrap(#"{"daily":[]}"#.data(using: .utf8))

  XCTAssertEqual(try UsageFetcher.parseDiscoveredAgents(data: data), [])
}

func testParseDiscoveredAgentsRejectsMalformedRequiredBreakdownRows() throws {
  let data = try XCTUnwrap(
    #"{"daily":[{"date":"2026-07-02","agentBreakdowns":[{"agent":"future-agent"}]}]}"#
      .data(using: .utf8))

  XCTAssertThrowsError(try UsageFetcher.parseDiscoveredAgents(data: data))
}
```

- [ ] **Step 2: Run the parser tests to verify they fail**

Run:

```bash
swift test --filter UsageFetcherTests
```

Expected: FAIL because `parseDiscoveredAgents` does not exist.

- [ ] **Step 3: Add the fetch protocol and discovery entry point**

At the top of `Sources/VibePulse/Services/UsageFetcher.swift`, add:

```swift
protocol UsageFetching: Sendable {
  func discoverAgents() throws -> [UsageAgent]
  func fetchDailyTotals(for agent: UsageAgent) throws -> [DailyTotal]
}
```

Make `UsageFetcher` conform and replace the old method signature with:

```swift
func discoverAgents() throws -> [UsageAgent] {
  try withRetry {
    let data = try runCommand(UsageAgent.discoveryCommand)
    return try Self.parseDiscoveredAgents(data: data)
  }
}

func fetchDailyTotals(for agent: UsageAgent) throws -> [DailyTotal] {
  try withRetry {
    let data = try runCommand(agent.dailyCommand)
    return try Self.parseDailyTotals(data: data)
  }
}
```

Extract the current three-attempt behavior into:

```swift
private func withRetry<T>(_ operation: () throws -> T) throws -> T {
  let maxAttempts = 3
  let retryDelay: TimeInterval = 0.3

  for attempt in 1...maxAttempts {
    do {
      return try operation()
    } catch FetchError.agentsviewNotFound(let path) {
      throw FetchError.agentsviewNotFound(path)
    } catch {
      if attempt == maxAttempts { throw error }
      Thread.sleep(forTimeInterval: retryDelay)
    }
  }

  throw FetchError.commandFailed("retry loop exhausted")
}
```

- [ ] **Step 4: Implement strict aggregate discovery parsing**

Add to `UsageFetcher`:

```swift
static func parseDiscoveredAgents(data: Data) throws -> [UsageAgent] {
  if let text = String(data: data, encoding: .utf8),
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  {
    throw FetchError.invalidOutput
  }

  guard
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
    let dailyRows = root["daily"] as? [[String: Any]]
  else {
    throw FetchError.invalidOutput
  }

  var costByAgent: [String: Double] = [:]
  for dailyRow in dailyRows {
    guard let breakdowns = dailyRow["agentBreakdowns"] as? [[String: Any]] else {
      throw FetchError.invalidOutput
    }
    for breakdown in breakdowns {
      guard
        let rawAgent = breakdown["agent"] as? String,
        !rawAgent.isEmpty,
        let cost = parseNumber(breakdown["cost"])
      else {
        throw FetchError.invalidOutput
      }
      costByAgent[rawAgent, default: 0] += cost
    }
  }

  return costByAgent
    .filter { $0.value > 0 }
    .map { UsageAgent($0.key) }
    .sorted()
}
```

Change `parseNumber` from `private` to `private static` only if needed by the new method; both parsers remain within the same type.

- [ ] **Step 5: Run fetcher tests**

Run:

```bash
swift test --filter UsageFetcherTests
```

Expected: PASS.

- [ ] **Step 6: Commit discovery parsing**

```bash
git add Sources/VibePulse/Services/UsageFetcher.swift \
  Tests/VibePulseTests/UsageFetcherTests.swift
git commit -m "Discover priced agents from agentsview usage"
```

---

### Task 3: Make SQLite Storage and Maintenance Agent-Dynamic

**Files:**
- Modify: `Sources/VibePulse/Services/UsageStore.swift`
- Modify: `Tests/VibePulseTests/UsageStoreTests.swift`

**Interfaces:**
- Consumes: `UsageAgent` from Task 1.
- Produces: every store API currently taking or returning `UsageTool` instead takes or returns `UsageAgent`.
- Produces: `UsageStore.storedAgents() -> [UsageAgent]` returning distinct non-empty identifiers across all usage tables.

- [ ] **Step 1: Add failing arbitrary-agent storage and maintenance tests**

Add to `Tests/VibePulseTests/UsageStoreTests.swift`:

```swift
func testStoreRoundTripsArbitraryAgentIdentifiers() throws {
  let store = try UsageStore(path: ":memory:")
  let agent = UsageAgent("future-agent")
  let date = Date()
  let dateKey = DateHelper.dateKey(for: date)

  try store.upsertDailyTotals(
    agent: agent,
    totals: [DailyTotal(dateKey: dateKey, cost: 4.25)])
  try store.insertSample(agent: agent, totalCost: 4.25, recordedAt: date)

  XCTAssertEqual(store.dailyTotal(for: dateKey, agent: agent), 4.25)
  XCTAssertEqual(
    store.fetchSamples(agent: agent, from: Date.distantPast, to: Date.distantFuture).map(\.agent),
    [agent])
  XCTAssertEqual(store.fetchDailyRollups(since: dateKey).map(\.agent), [agent])
}

func testStoredAgentsIncludesUnknownAgentsFromPersistedUsage() throws {
  let store = try UsageStore(path: ":memory:")
  let agent = UsageAgent("future-agent")

  try store.upsertDailyTotals(
    agent: agent,
    totals: [DailyTotal(dateKey: "2026-07-02", cost: 1)])

  XCTAssertEqual(store.storedAgents(), [agent])
}
```

- [ ] **Step 2: Run store tests to verify the dynamic API is missing**

Run:

```bash
swift test --filter UsageStoreTests
```

Expected: FAIL on `agent:` labels and `storedAgents()`.

- [ ] **Step 3: Convert store signatures and row decoding to `UsageAgent`**

In `Sources/VibePulse/Services/UsageStore.swift`:

- Rename public and private method labels from `tool:` to `agent:`.
- Replace every `UsageTool` type with `UsageAgent`.
- Bind `agent.rawValue` into the existing SQLite `tool` columns.
- When decoding a `tool` column, replace enum conversion with:

```swift
let rawAgent = String(cString: agentCString)
guard !rawAgent.isEmpty else { continue }
let agent = UsageAgent(rawAgent)
```

- Replace enum-index sorting with stable agent sorting:

```swift
if $0.modelName == $1.modelName {
  return $0.agent < $1.agent
}
```

- Remove `toolOrder(_:)` entirely after all callers use `UsageAgent` ordering.

Do not rename SQLite columns or create a migration; the column name is an internal schema detail and its text values already match agentsview identifiers.

- [ ] **Step 4: Add `storedAgents()` for dynamic maintenance**

Add this public method to `UsageStore`:

```swift
func storedAgents() -> [UsageAgent] {
  queue.sync {
    let sql = """
      SELECT tool FROM samples
      UNION SELECT tool FROM daily_rollups
      UNION SELECT tool FROM model_samples
      UNION SELECT tool FROM model_daily_rollups;
      """
    var agents = Set<UsageAgent>()
    do {
      try withStatement(sql) { statement in
        while sqlite3_step(statement) == SQLITE_ROW {
          guard let agentCString = sqlite3_column_text(statement, 0) else { continue }
          let rawAgent = String(cString: agentCString)
          guard !rawAgent.isEmpty else { continue }
          agents.insert(UsageAgent(rawAgent))
        }
      }
    } catch {
      return []
    }
    return agents.sorted()
  }
}
```

- [ ] **Step 5: Update existing store tests and raw SQLite helpers**

In `Tests/VibePulseTests/UsageStoreTests.swift`:

- Replace `tool:` labels with `agent:`.
- Replace model fields and assertions from `.tool` to `.agent`.
- Change helper parameters and tuple types from `UsageTool` to `UsageAgent`.
- Continue binding `agent.rawValue` into raw SQL helpers because the schema column remains `tool`.

- [ ] **Step 6: Run store tests**

Run:

```bash
swift test --filter UsageStoreTests
```

Expected: PASS, including arbitrary-agent round trips and stored-agent discovery.

- [ ] **Step 7: Commit dynamic storage**

```bash
git add Sources/VibePulse/Services/UsageStore.swift \
  Tests/VibePulseTests/UsageStoreTests.swift
git commit -m "Store arbitrary agents without enum filtering"
```

---

### Task 4: Add Discover-Then-Import Refresh Orchestration

**Files:**
- Create: `Sources/VibePulse/Services/UsageRefreshService.swift`
- Create: `Tests/VibePulseTests/UsageRefreshServiceTests.swift`

**Interfaces:**
- Consumes: `UsageFetching` from Task 2 and dynamic `UsageStore` APIs from Task 3.
- Produces: `struct UsageRefreshResult: Sendable { let discoveredAgents: [UsageAgent]; let importErrors: [String] }`.
- Produces: `UsageRefreshService.refresh(todayKey:sampleTime:) throws -> UsageRefreshResult`.
- Behavior: discovery failure throws before imports; individual import failures are returned while remaining agents continue.

- [ ] **Step 1: Write failing refresh-service tests**

Create `Tests/VibePulseTests/UsageRefreshServiceTests.swift`:

```swift
import XCTest

@testable import VibePulse

final class UsageRefreshServiceTests: XCTestCase {
  func testRefreshImportsEveryDiscoveredAgent() throws {
    let first = UsageAgent("future-agent")
    let second = UsageAgent("other-agent")
    let fetcher = StubUsageFetcher(
      discoveredAgents: [first, second],
      totalsByAgent: [
        first: [DailyTotal(dateKey: "2026-07-17", cost: 2)],
        second: [DailyTotal(dateKey: "2026-07-17", cost: 3)],
      ])
    let store = try UsageStore(path: ":memory:")
    let service = UsageRefreshService(fetcher: fetcher, store: store)

    let result = try service.refresh(
      todayKey: "2026-07-17",
      sampleTime: Date(timeIntervalSince1970: 1_752_710_400))

    XCTAssertEqual(result.discoveredAgents, [first, second].sorted())
    XCTAssertEqual(fetcher.requestedAgents, [first, second])
    XCTAssertEqual(store.dailyTotal(for: "2026-07-17", agent: first), 2)
    XCTAssertEqual(store.dailyTotal(for: "2026-07-17", agent: second), 3)
    XCTAssertEqual(result.importErrors, [])
  }

  func testRefreshContinuesAfterOneAgentImportFails() throws {
    let failed = UsageAgent("failed-agent")
    let successful = UsageAgent("successful-agent")
    let fetcher = StubUsageFetcher(
      discoveredAgents: [failed, successful],
      totalsByAgent: [successful: [DailyTotal(dateKey: "2026-07-17", cost: 3)]],
      failingAgents: [failed])
    let store = try UsageStore(path: ":memory:")
    let service = UsageRefreshService(fetcher: fetcher, store: store)

    let result = try service.refresh(todayKey: "2026-07-17", sampleTime: Date())

    XCTAssertEqual(fetcher.requestedAgents, [failed, successful])
    XCTAssertEqual(store.dailyTotal(for: "2026-07-17", agent: successful), 3)
    XCTAssertEqual(result.importErrors.count, 1)
    XCTAssertTrue(result.importErrors[0].hasPrefix("Failed Agent:"))
  }

  func testDiscoveryFailurePreventsImports() throws {
    let fetcher = StubUsageFetcher(discoveryError: StubError.discoveryFailed)
    let store = try UsageStore(path: ":memory:")
    let service = UsageRefreshService(fetcher: fetcher, store: store)

    XCTAssertThrowsError(
      try service.refresh(todayKey: "2026-07-17", sampleTime: Date()))
    XCTAssertEqual(fetcher.requestedAgents, [])
  }
}

private enum StubError: LocalizedError {
  case discoveryFailed
  case importFailed

  var errorDescription: String? {
    switch self {
    case .discoveryFailed: return "discovery failed"
    case .importFailed: return "import failed"
    }
  }
}

private final class StubUsageFetcher: UsageFetching, @unchecked Sendable {
  private let discoveredAgents: [UsageAgent]
  private let totalsByAgent: [UsageAgent: [DailyTotal]]
  private let failingAgents: Set<UsageAgent>
  private let discoveryError: Error?
  private(set) var requestedAgents: [UsageAgent] = []

  init(
    discoveredAgents: [UsageAgent] = [],
    totalsByAgent: [UsageAgent: [DailyTotal]] = [:],
    failingAgents: Set<UsageAgent> = [],
    discoveryError: Error? = nil
  ) {
    self.discoveredAgents = discoveredAgents
    self.totalsByAgent = totalsByAgent
    self.failingAgents = failingAgents
    self.discoveryError = discoveryError
  }

  func discoverAgents() throws -> [UsageAgent] {
    if let discoveryError { throw discoveryError }
    return discoveredAgents
  }

  func fetchDailyTotals(for agent: UsageAgent) throws -> [DailyTotal] {
    requestedAgents.append(agent)
    if failingAgents.contains(agent) { throw StubError.importFailed }
    return totalsByAgent[agent] ?? []
  }
}
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run:

```bash
swift test --filter UsageRefreshServiceTests
```

Expected: FAIL because `UsageRefreshService` and `UsageRefreshResult` do not exist.

- [ ] **Step 3: Implement the refresh service**

Create `Sources/VibePulse/Services/UsageRefreshService.swift`:

```swift
import Foundation

struct UsageRefreshResult: Sendable {
  let discoveredAgents: [UsageAgent]
  let importErrors: [String]
}

final class UsageRefreshService: @unchecked Sendable {
  private let fetcher: UsageFetching
  private let store: UsageStore

  init(fetcher: UsageFetching, store: UsageStore) {
    self.fetcher = fetcher
    self.store = store
  }

  func refresh(todayKey: String, sampleTime: Date) throws -> UsageRefreshResult {
    let agents = try fetcher.discoverAgents().sorted()
    var errors: [String] = []

    for agent in agents {
      do {
        let totals = try fetcher.fetchDailyTotals(for: agent)
        try store.upsertDailyTotals(agent: agent, totals: totals)
        if let todayTotal = totals.first(where: {
          DateHelper.normalizedDateKey(from: $0.dateKey) == todayKey
        }) {
          try store.insertSample(
            agent: agent,
            totalCost: todayTotal.cost,
            recordedAt: sampleTime)
          if let modelBreakdowns = todayTotal.modelBreakdowns {
            try store.insertModelSamplesForRefresh(
              agent: agent,
              modelBreakdowns: modelBreakdowns,
              recordedAt: sampleTime)
          }
        }
      } catch {
        errors.append("\(agent.displayName): \(error.localizedDescription)")
      }
    }

    return UsageRefreshResult(
      discoveredAgents: agents,
      importErrors: errors)
  }
}
```

There is intentionally no enabled/disabled input. This is the boundary that guarantees all discovered agents import regardless of presentation preference.

- [ ] **Step 4: Run refresh-service tests**

Run:

```bash
swift test --filter UsageRefreshServiceTests
```

Expected: PASS.

- [ ] **Step 5: Commit refresh orchestration**

```bash
git add Sources/VibePulse/Services/UsageRefreshService.swift \
  Tests/VibePulseTests/UsageRefreshServiceTests.swift
git commit -m "Import every dynamically discovered agent"
```

---

### Task 5: Persist Dynamic Agent Preferences and Migrate Legacy Toggles

**Files:**
- Create: `Sources/VibePulse/Services/AgentPreferences.swift`
- Create: `Tests/VibePulseTests/AgentPreferencesTests.swift`

**Interfaces:**
- Produces: `AgentPreferences.init(defaults:)`.
- Produces: `hasDiscoveryCache`, `loadDiscoveredAgents()`, `saveDiscoveredAgents(_:)`, `loadDisabledAgentIDs()`, `saveDisabledAgentIDs(_:)`, and `migrateLegacyPreferences()`.
- Behavior: enabled state is absence from `disabledAgentIDs`; discovery visibility and enabled preference remain separate.

- [ ] **Step 1: Write failing preference and migration tests**

Create `Tests/VibePulseTests/AgentPreferencesTests.swift`:

```swift
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
  }

  private func makeDefaults() throws -> UserDefaults {
    let suiteName = "AgentPreferencesTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
swift test --filter AgentPreferencesTests
```

Expected: FAIL because `AgentPreferences` does not exist.

- [ ] **Step 3: Implement the preference store and one-time migration**

Create `Sources/VibePulse/Services/AgentPreferences.swift`:

```swift
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
```

- [ ] **Step 4: Run preference tests**

Run:

```bash
swift test --filter AgentPreferencesTests
```

Expected: PASS.

- [ ] **Step 5: Commit preference persistence**

```bash
git add Sources/VibePulse/Services/AgentPreferences.swift \
  Tests/VibePulseTests/AgentPreferencesTests.swift
git commit -m "Persist dynamic agent visibility choices"
```

---

### Task 6: Integrate Discovery, Filtering, and Maintenance in `AppModel`

**Files:**
- Modify: `Sources/VibePulse/AppModel.swift`
- Modify: `Sources/VibePulse/Services/UsageStore.swift`
- Modify: `Tests/VibePulseTests/AgentPreferencesTests.swift`
- Modify: `Tests/VibePulseTests/UsageRefreshServiceTests.swift`

**Interfaces:**
- Consumes: `UsageRefreshService`, `AgentPreferences`, `UsageAgent`, and `UsageStore.storedAgents()`.
- Produces: `@Published private(set) var discoveredAgents: [UsageAgent]`.
- Produces: `@Published private(set) var disabledAgentIDs: Set<String>`.
- Produces: `var hasDiscoveryCache: Bool`, `func isAgentEnabled(_:)`, and `func setAgent(_:enabled:)` for Settings.
- Produces: private `activeAgents` derived from discovered agents minus disabled IDs.

- [ ] **Step 1: Add a focused enabled-selection test to the preference suite**

Add a small pure helper to `AgentPreferences`:

```swift
static func enabledAgents(
  from discoveredAgents: [UsageAgent],
  disabledAgentIDs: Set<String>
) -> [UsageAgent] {
  discoveredAgents.filter { !disabledAgentIDs.contains($0.rawValue) }
}
```

First add this failing test to `Tests/VibePulseTests/AgentPreferencesTests.swift`:

```swift
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
```

Run:

```bash
swift test --filter AgentPreferencesTests/testEnabledAgentsExcludeDisabledWithoutRemovingDiscovery
```

Expected: FAIL until the pure helper is added, then PASS.

- [ ] **Step 2: Replace six published booleans with dynamic state**

In `Sources/VibePulse/AppModel.swift`, remove `includeClaude`, `includeCodex`, `includePi`, `includeOMP`, `includeGemini`, and `includeOpenCode`.

Add:

```swift
@Published private(set) var discoveredAgents: [UsageAgent]
@Published private(set) var disabledAgentIDs: Set<String>

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
  reloadFromStore()
}
```

Change the stored dependencies to:

```swift
private let defaults: UserDefaults
private let agentPreferences: AgentPreferences
private let refreshService: UsageRefreshService
private let store: UsageStore
```

At initialization:

1. Set `defaults` from `.standard`.
2. Construct `AgentPreferences`.
3. Run `migrateLegacyPreferences()` before loading disabled IDs.
4. Load cached discovered agents and disabled IDs.
5. Resolve the existing persistent or in-memory `UsageStore`.
6. Construct `UsageRefreshService(fetcher: UsageFetcher(), store: store)`.

Keep the existing timers, login-item behavior, welcome flow, and maintenance scheduling unchanged.

- [ ] **Step 3: Replace refresh logic with discover-then-import orchestration**

Remove the early guard that requires an enabled source. `refreshNow()` must always be able to discover agents.

Use this background shape:

```swift
let todayKey = DateHelper.dateKey(for: Date())
DispatchQueue.global(qos: .background).async { [refreshService] in
  do {
    let result = try refreshService.refresh(
      todayKey: todayKey,
      sampleTime: Date())
    let refreshTime = Date()
    DispatchQueue.main.async {
      self.discoveredAgents = result.discoveredAgents
      self.agentPreferences.saveDiscoveredAgents(result.discoveredAgents)
      self.statusMessage = result.importErrors.isEmpty
        ? nil
        : result.importErrors.joined(separator: " | ")
      if result.importErrors.isEmpty {
        self.lastUpdated = refreshTime
      }
      self.reloadFromStore()
      self.isRefreshing = false
    }
  } catch {
    DispatchQueue.main.async {
      self.statusMessage = error.localizedDescription
      self.reloadFromStore()
      self.isRefreshing = false
    }
  }
}
```

A thrown discovery error does not assign `discoveredAgents` or save the cache. A successful empty discovery assigns and persists `[]`.

- [ ] **Step 4: Derive active presentation agents dynamically**

Replace the `UsageTool.allCases` switch with:

```swift
private var activeAgents: [UsageAgent] {
  AgentPreferences.enabledAgents(
    from: discoveredAgents,
    disabledAgentIDs: disabledAgentIDs)
}
```

In `reloadFromStore()`, replace every `tools` variable and store call with `agents` and the dynamic APIs from Task 3. Build `UsageSeriesPoint(agent:...)` and `ToolTotal(agent:...)` values.

Model aggregation remains scoped to active agents, ensuring a disabled agent's model costs also disappear from model-grouped charts and totals.

- [ ] **Step 5: Make maintenance enumerate stored agents**

Replace the `UsageTool.allCases.reduce` date-normalization loop with:

```swift
let dateUpdated = try store.storedAgents().reduce(0) { count, agent in
  count + (try store.normalizeDailyRollupDates(for: agent))
    + (try store.normalizeModelDailyRollupDates(for: agent))
}
```

This includes unknown, disabled, and currently undiscovered agents that still have stored rows.

- [ ] **Step 6: Compile and run service/preference/store tests**

Run:

```bash
swift test --filter 'AgentPreferencesTests|UsageRefreshServiceTests|UsageStoreTests'
```

Expected: PASS.

- [ ] **Step 7: Run the full suite to catch remaining enum references**

Run:

```bash
swift test
```

Expected: PASS. If compilation reports `UsageTool`, `includeClaude`, or other removed symbols, update those production call sites to the dynamic interfaces; do not add aliases or compatibility wrappers.

- [ ] **Step 8: Verify removed fixed-agent references by source search**

Run:

```bash
grep -R "UsageTool\|includeClaude\|includeCodex\|includePi\|includeOMP\|includeGemini\|includeOpenCode" \
  Sources Tests || true
```

Expected: no matches. This is a one-time verification command, not a test committed to the suite.

- [ ] **Step 9: Commit AppModel integration**

```bash
git add Sources/VibePulse/AppModel.swift \
  Sources/VibePulse/Services/UsageStore.swift \
  Sources/VibePulse/Services/AgentPreferences.swift \
  Tests/VibePulseTests/AgentPreferencesTests.swift \
  Tests/VibePulseTests/UsageRefreshServiceTests.swift
git commit -m "Drive usage state from discovered agents"
```

---

### Task 7: Render Dynamic Settings and Update Product Copy

**Files:**
- Modify: `Sources/VibePulse/Views/SettingsView.swift`
- Modify: `Sources/VibePulse/Views/WelcomeView.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: `AppModel.discoveredAgents`, `hasDiscoveryCache`, `isAgentEnabled(_:)`, and `setAgent(_:enabled:)`.
- Produces: dynamic checkbox controls sorted by `UsageAgent` ordering.
- Produces: clear loading/empty explanatory copy without changing import behavior.

- [ ] **Step 1: Replace the fixed Settings grid with dynamic controls**

In `SettingsView.dataSourcesSection`, use:

```swift
private var dataSourcesSection: some View {
  settingsSection("Data Sources") {
    VStack(alignment: .leading, spacing: 10) {
      helperText(
        "Agents with priced usage in the past 30 days are discovered through agentsview. "
          + "Turning one off hides it without stopping imports or deleting history."
      )

      if model.discoveredAgents.isEmpty {
        if model.isRefreshing && !model.hasDiscoveryCache {
          HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            helperText("Discovering local agents…")
          }
        } else {
          helperText("No agents with priced usage were found in the past 30 days.")
        }
      } else {
        LazyVGrid(
          columns: [
            GridItem(.flexible(minimum: 150), alignment: .leading),
            GridItem(.flexible(minimum: 150), alignment: .leading),
          ],
          alignment: .leading,
          spacing: 8
        ) {
          ForEach(model.discoveredAgents) { agent in
            sourceToggle(agent)
          }
        }
      }
    }
  }
}
```

Replace the old binding helper with:

```swift
private func sourceToggle(_ agent: UsageAgent) -> some View {
  Toggle(
    agent.displayName,
    isOn: Binding(
      get: { model.isAgentEnabled(agent) },
      set: { model.setAgent(agent, enabled: $0) }
    )
  )
  .toggleStyle(.checkbox)
  .frame(maxWidth: .infinity, alignment: .leading)
}
```

Do not disable checkboxes during refresh; the displayed list is the last successful cache and remains stable until a successful discovery replaces it.

- [ ] **Step 2: Update welcome copy**

Replace the exhaustive list in `Sources/VibePulse/Views/WelcomeView.swift` with:

```swift
Text(
  "VibePulse reads local AI coding-agent usage through agentsview. "
    + "Agents with priced usage in the past 30 days are discovered automatically. "
    + "Make sure agentsview is installed; you can set a custom path in Settings."
)
```

- [ ] **Step 3: Update README compatibility and settings documentation**

Revise `README.md` so it states:

- VibePulse tracks locally used agents parsed by agentsview.
- Familiar agents can be mentioned only as examples, not an exhaustive list.
- Requirements say at least one agentsview-parsed agent with priced local usage.
- Data Sources Settings shows agents with positive cost in the rolling past 30 days.
- Turning an agent off hides it but imports and retains its history.
- Security/privacy says VibePulse runs one aggregate discovery report and filtered per-agent usage reports.
- Troubleshooting tells users to run:

```bash
agentsview usage daily --json --breakdown --since 30d
```

and explains that an agent must appear with positive cost before VibePulse shows it.

- [ ] **Step 4: Format and build the app**

Run:

```bash
./scripts/format.sh
swift build
```

Expected: formatting exits 0 and the app builds successfully.

- [ ] **Step 5: Run all tests**

Run:

```bash
swift test
```

Expected: all tests pass with zero failures.

- [ ] **Step 6: Commit UI and documentation**

```bash
git add Sources/VibePulse/Views/SettingsView.swift \
  Sources/VibePulse/Views/WelcomeView.swift README.md
git commit -m "Show dynamically discovered agents in settings"
```

---

### Task 8: Final Verification and Review

**Files:**
- Verify all modified source, tests, docs, and plan files.

**Interfaces:**
- Consumes: all prior tasks.
- Produces: verified implementation matching the approved design.

- [ ] **Step 1: Run repository formatting and whitespace checks**

Run:

```bash
./scripts/format.sh
git diff --check
```

Expected: both commands exit 0 with no whitespace errors.

- [ ] **Step 2: Run the full test suite from a clean build**

Run:

```bash
swift package clean
swift test
```

Expected: build succeeds and every XCTest passes.

- [ ] **Step 3: Build the distributable app path**

Run:

```bash
./scripts/build_dmg.sh dev
```

Expected: the release build and DMG packaging complete successfully and produce the development DMG under `dist/`.

- [ ] **Step 4: Verify the fixed allowlist is gone and dynamic commands remain**

Run:

```bash
grep -R "enum UsageTool\|UsageTool.allCases\|includeClaude\|includeCodex\|includePi\|includeOMP\|includeGemini\|includeOpenCode" \
  Sources Tests || true
grep -R "--breakdown.*--since.*30d\|--agent.*--since.*30d.*--no-sync" \
  Sources/VibePulse/Models/UsageAgent.swift
```

Expected: the first search has no matches; the second shows the aggregate discovery and filtered import command definitions.

- [ ] **Step 5: Review behavior against the acceptance criteria**

Confirm from code and tests:

- arbitrary non-empty agents pass through the complete domain and store;
- aggregate discovery filters by positive 30-day cost;
- every discovered agent imports regardless of disabled preference;
- disabled agents are excluded only by `AppModel.activeAgents` when reading for presentation;
- discovery failure retains cached agents because assignment occurs only on success;
- successful empty discovery persists an empty cache;
- maintenance enumerates stored agents;
- legacy false toggles migrate into disabled IDs and old keys are removed;
- Settings and README describe agentsview-driven compatibility rather than a fixed list.

Expected: every item has a concrete implementation location and passing focused test where it represents owned business logic.

- [ ] **Step 6: Request code review**

Use the `requesting-code-review` skill to review the complete diff against:

```text
docs/superpowers/specs/2026-07-17-dynamic-agentsview-agent-discovery-design.md
```

Apply valid findings with the `receiving-code-review` skill, then rerun Steps 1 through 4.

- [ ] **Step 7: Inspect final repository state**

Run:

```bash
git status --short
git log --oneline --decorate -8
```

Expected: only intentional implementation changes are present, or the working tree is clean if all task commits include every change.
