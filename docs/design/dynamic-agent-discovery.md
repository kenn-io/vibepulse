
# Dynamic agentsview agent discovery

## Problem

VibePulse used to model supported coding agents as a closed `UsageTool` enum
with six compiled-in cases (Claude Code, Codex, Pi, OMP, Gemini, OpenCode).
Commands, preferences, storage, chart series, and Settings toggles all assumed
one of those cases, so an agent newly supported by agentsview was invisible
until VibePulse added another enum case and shipped a release. The SQLite
schema already stored agent identifiers as plain text, so the constraint was
in the Swift domain model and the fixed Settings UI, not the persisted data.

VibePulse now discovers agents dynamically: any agent agentsview reports with
positive cost in the trailing 30 days works automatically, without a
VibePulse-specific release. The compatibility statement is: VibePulse
supports agents parsed by agentsview when they have priced usage in the past
30 days. This ties the promise to the installed agentsview version's output,
not to a list compiled into VibePulse.

## Non-goals

- Listing every parser agentsview supports when there is no corresponding
  local usage.
- Showing agents whose calculated 30-day cost is zero.
- Stopping imports when an agent is disabled in VibePulse's Settings.
- Deleting stored usage when an agent is disabled or leaves the discovery
  window.
- Reading agentsview's SQLite database directly or relying on an internal,
  unversioned API.
- UI for renaming agents or manually entering agent identifiers.

## Domain model

`Sources/VibePulse/Models/UsageAgent.swift` replaces the enum with a
`Hashable, Identifiable, Comparable, Sendable` value type wrapping a
non-empty raw agentsview identifier (`UsageAgent(_ rawValue: String)`,
preconditioned non-empty). All usage-bearing models, store APIs, aggregation
utilities, series keys, and the color palette take `UsageAgent` instead of
the old enum, and reading an unfamiliar identifier from SQLite constructs a
valid agent rather than discarding the row.

`displayName` looks up a small curated table (`claude` → "Claude Code", `omp`
→ "OhMyPi", `opencode` → "OpenCode", `copilot` → "GitHub Copilot", and so on)
and falls back to a generated label for unknown identifiers — hyphens and
underscores become spaces, and each word is capitalized. A missing curated
label never disables imports, storage, filtering, charting, or Settings
controls; the curated table is cosmetic only. A handful of static
convenience constants (`.claude`, `.codex`, `.pi`, `.omp`, `.gemini`,
`.openCode`) exist purely for readable call sites and tests, not as a
registry that gates functionality — arbitrary identifiers need no
registration.

Ordering is deterministic everywhere (Settings, charts, legends): by
case-insensitive display name, with the raw identifier as a tie-breaker,
rather than enum declaration order.

## Discovery and import flow

Each refresh runs in two stages, orchestrated by
`Sources/VibePulse/Services/UsageRefreshService.swift`:

1. **Discover.** Run `agentsview usage daily --format json --breakdown
   --since 30d --timezone <tz>` once. This also performs agentsview's
   on-demand sync. `UsageFetcher.parseDiscoveredAgents` sums the `cost`
   field across every `agentBreakdowns` row by exact agent identifier and
   keeps only identifiers whose summed cost is greater than zero. The
   result becomes the new `discoveredAgents` list, persisted as the last
   successful discovery set.
2. **Import every discovered agent**, regardless of its enabled/disabled
   preference, with `agentsview usage daily --format json --breakdown
   --agent <id> --since 30d --timezone <tz> --no-sync`. `--no-sync` avoids
   repeating agentsview's sync per agent, since discovery already
   synced once. Reports run with at most two concurrent fetches, then import
   in sorted agent order. Each agent's import is independent — one agent's failure is
   recorded as an error and does not stop the remaining agents from
   importing. If an older agentsview build rejects `--breakdown` or
   `--timezone`, `UsageFetcher` retries without the unsupported flag (or
   surfaces a dedicated "upgrade agentsview" error for timezone).

Disabled state affects presentation only — it never changes which commands
run, what gets written to SQLite, or what maintenance touches. Turning an
agent back on immediately reveals everything VibePulse retained while it was
hidden.

An agent that drops out of the 30-day discovery window stops being imported
until it qualifies again, but its stored rows and disabled/enabled
preference are left untouched; if it reappears later, both resume as before.

## Preference persistence and migration

`Sources/VibePulse/Services/AgentPreferences.swift` persists two values in
`UserDefaults`:

- `discoveredAgentIDs` — the last successfully discovered set, a cache for
  stable startup and failure behavior, replaced only after a successful
  discovery parse.
- `disabledAgentIDs` — identifiers the user explicitly turned off.

Enabled state is derived, not stored directly:
`AgentPreferences.enabledAgents(from:disabledAgentIDs:)` filters discovered
agents whose raw identifier is absent from `disabledAgentIDs`. A newly
discovered identifier is therefore enabled by default. Removing an
identifier from the discovery set does not remove it from
`disabledAgentIDs`, so a reappearing agent's explicit preference is
restored rather than reset.

On first launch, `migrateLegacyPreferences()` performs a one-time forward
migration from the six legacy Boolean keys (`includeClaude`, `includeCodex`,
`includePi`, `includeOMP`, `includeGemini`, `includeOpenCode`): each legacy
key that is explicitly `false` adds its identifier to `disabledAgentIDs`;
`true` values need no entry since enabled is the default. All six legacy
keys are removed after translation — there is no permanent dual-read path.

## AppModel integration

`AppModel` holds `discoveredAgents` and `disabledAgentIDs` as published
state, exposes `isAgentEnabled(_:)` / `setAgent(_:enabled:)` for Settings,
and derives `activeTools` (discovered minus disabled) for every
presentation path: the menu bar total, chart series, daily rollups, and
legend/breakdown totals. `hasDiscoveryCache` reports whether a discovery
result has ever been persisted, which Settings uses to distinguish "still
discovering for the first time" from "discovery previously found nothing."

A thrown discovery error leaves `discoveredAgents` and the persisted cache
unchanged — a failed refresh never replaces trusted state with nothing. A
*successful* empty discovery does replace the cache with an empty list, which
is a legitimate outcome (no positive-cost agents right now), distinct from a
failed discovery.

Maintenance (`UsageStore.storedAgents()` plus date normalization) enumerates
agents actually present in storage rather than a compiled list, so it also
covers agents that are currently hidden, disabled, or no longer discovered.

## Settings and copy

The Settings "Data Sources" section renders one checkbox per entry in
`discoveredAgents`, sorted by the same deterministic rule as the rest of the
app. While discovery is in flight, Settings continues to show the last
successful set instead of a blank control, so controls do not flicker away
during a refresh. If discovery has completed and found nothing, Settings
shows a one-line empty state rather than an empty grid. The section's
helper text and the Welcome window both describe agentsview-driven discovery
rather than naming a fixed agent list; the README states the same
compatibility boundary.

## Testing strategy

- Discovery parsing: sums multi-day breakdown costs per identifier,
  accepts arbitrary future identifiers, excludes zero-cost agents, and
  treats an empty valid report as a successful empty discovery.
- Domain identity: known-identifier curated labels, deterministic generated
  labels for unknown identifiers, and stable ordering.
- Refresh behavior: imports every discovered agent including disabled ones,
  continues after one agent's import fails, and leaves the cached discovery
  list untouched when discovery itself fails.
- Preferences: enabled-by-default for newly discovered agents, disabled
  preference surviving disappearance and rediscovery, and legacy toggle
  migration with key removal.
- Store and maintenance: round-trips arbitrary agent identifiers and
  includes hidden/unknown agents in maintenance operations.
