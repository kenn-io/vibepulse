# Dynamic agentsview agent discovery for VibePulse

**Status:** Approved design, pending written-spec review
**Date:** 2026-07-17
**Author:** VibePulse maintainers with pi

## Goal

Make VibePulse work with every agent represented in the installed agentsview
version's usage reports, without requiring VibePulse to maintain a closed list
of supported agents.

VibePulse will dynamically discover agents with priced local usage during the
past 30 days. Discovered agents appear in Settings and are enabled by default.
Users can hide agents they do not care about without stopping imports or
deleting stored history.

The user-facing compatibility statement is:

> VibePulse supports agents parsed by agentsview when they have priced usage in
> the past 30 days.

This promise is intentionally tied to the installed agentsview version and its
usage output, not to a list compiled into a particular VibePulse release.

## Non-goals

- Listing every parser supported by agentsview when there is no corresponding
  local usage.
- Showing agents whose calculated 30-day cost is zero.
- Stopping imports when an agent is disabled in VibePulse.
- Deleting stored usage when an agent is disabled or leaves the discovery
  window.
- Reading agentsview's SQLite database or relying on an internal, unversioned
  API.
- Maintaining a functional allowlist of agent identifiers in VibePulse.
- Adding UI for renaming agents or manually entering agent identifiers.

## Current limitation

VibePulse currently models agents as the closed `UsageTool` enum. Commands,
preferences, storage reads, chart series, colors, and Settings toggles all
assume one of six compiled-in cases. An agent newly supported by agentsview is
therefore discarded or inaccessible until VibePulse adds another enum case and
ships a release.

The SQLite schema already stores the agent identifier as text. The primary
constraint is the Swift domain model and the fixed settings state, not the
persisted table shape.

## Discovery source

At the start of each refresh, VibePulse runs agentsview's public, versioned
usage command over an explicit rolling 30-day window:

```bash
agentsview usage daily --json --breakdown --since 30d
```

The `--breakdown` flag populates `daily[].agentBreakdowns`. VibePulse sums the
`cost` values by exact `agent` identifier across all returned days. An agent is
currently discovered when its summed cost is greater than zero.

Agent identifiers are opaque, stable strings owned by agentsview. VibePulse
must preserve them exactly when storing preferences, writing SQLite rows, and
passing `--agent` filters back to agentsview. Functional support must not depend
on a switch statement, known-name table, or identifier validation in
VibePulse.

The explicit `--since 30d` window keeps discovery aligned with the intended
rolling 30-day behavior even if agentsview changes its CLI default in a future
release. VibePulse will not infer discovery from all-time stored history,
parser registries, environment variables, or session counts.

## Refresh and import flow

Each refresh has two stages.

### 1. Discover qualifying agents

1. Run the aggregate 30-day command with JSON and agent breakdowns.
2. Parse all daily agent breakdown rows.
3. Sum cost by agent identifier.
4. Keep only identifiers whose aggregate cost is greater than zero.
5. Persist the resulting set as the last successful discovery set.

A successful discovery result is authoritative for which agents are visible in
Settings. It does not delete usage or preferences for agents that are no longer
in the set.

### 2. Import every discovered agent

For every discovered identifier, including identifiers disabled in the UI, run:

```bash
agentsview usage daily --json --agent <agent-id> --since 30d --no-sync
```

The aggregate discovery command performs the refresh's on-demand agentsview
sync once. Filtered imports use `--no-sync` so every agent is read from the same
post-sync snapshot without repeating an expensive sync for each identifier.
The existing daily-total and model-breakdown import behavior then stores the
agent's report under that exact identifier. Imports are independent: one
agent's failure does not prevent the remaining agents from refreshing.

Disabled state affects presentation only. It does not alter discovery, command
execution, SQLite writes, maintenance, or retention. This guarantees that
turning an agent back on immediately reveals all data VibePulse retained while
it was hidden.

An agent that leaves the 30-day discovery set is no longer imported until it
qualifies again. Its previously stored rows remain untouched. If it later
returns with positive 30-day cost, VibePulse resumes imports and restores its
saved enabled or disabled preference.

## Domain model

Replace the closed `UsageTool` enum with a dynamic, hashable, string-backed
agent value, referred to in this design as `UsageAgent`.

`UsageAgent` has:

- `id` or `rawValue`: the exact agentsview identifier;
- `displayName`: a presentation label;
- `shortName`: a compact chart label when useful;
- command construction that appends the exact identifier after `--agent`.

All usage-bearing models, store APIs, aggregation utilities, series keys, and
palette inputs use `UsageAgent` instead of a closed enum. Reading an unfamiliar
identifier from SQLite must construct a valid agent value rather than discard
the row.

Known identifiers may have curated presentation labels, for example `claude`
as “Claude Code” and `omp` as “OhMyPi.” This mapping is cosmetic only. Unknown
identifiers receive a deterministic readable label derived from the raw value,
with separators converted to spaces and words capitalized where practical. A
missing curated label must never disable imports, storage, filtering, charting,
or settings controls.

Agent ordering is deterministic. Settings sorts by case-insensitive display
name with the raw identifier as a tie-breaker. Chart and legend ordering use
the same stable rule rather than enum declaration order.

## Settings and presentation

The fixed six-checkbox grid becomes a dynamic list based on the last successful
discovery set.

The section includes concise explanatory copy:

> Agents with priced usage in the past 30 days are discovered through
> agentsview.

Each discovered agent has a checkbox. New agents are enabled by default.
Unchecking an agent excludes it from:

- the menu bar combined total;
- tool totals;
- hourly and cumulative charts;
- daily charts;
- agent-grouped legends and breakdowns.

Unchecking does not stop imports or remove stored rows. Settings should make
this behavior clear without adding confirmation dialogs.

When discovery has completed successfully but no positive-cost agents qualify,
the section shows a compact empty state explaining that no priced agents were
found in the past 30 days. It does not render an empty grid.

While discovery is in progress, Settings continues showing the last successful
set. This avoids controls disappearing temporarily during refresh.

## Preference persistence

Persist two dynamic values in `UserDefaults`:

1. `discoveredAgentIDs`: the last successfully discovered set of raw agent
   identifiers;
2. `disabledAgentIDs`: raw identifiers the user explicitly turned off.

Enabled state is derived rather than stored individually:

```text
enabled = discoveredAgentIDs contains id && disabledAgentIDs does not contain id
```

A newly discovered identifier is enabled automatically because it is absent
from `disabledAgentIDs`. Removing an identifier from the discovery set does not
remove it from `disabledAgentIDs`; if the agent later reappears, its explicit
preference is restored.

The persisted discovery set is a cache for stable startup and failure behavior,
not an alternate source of truth. It is replaced only after a successful
aggregate discovery command and parse.

## Legacy preference migration

Existing releases persist six Boolean settings: Claude Code, Codex, Pi, OMP,
Gemini, and OpenCode. On the first launch of the dynamic implementation,
VibePulse performs a one-time forward migration:

1. For each legacy key that exists and is `false`, add its corresponding exact
   agentsview identifier to `disabledAgentIDs`.
2. Existing `true` values require no entry because enabled is the default.
3. Remove all six legacy keys after translation.
4. Use only the dynamic preference set after migration; do not retain a
   permanent dual-read or dual-write path.

This preserves explicit choices made by existing users while removing the
fixed-agent preference model.

## Storage and retention

No parallel database tables or compatibility schema are needed. Existing usage
tables already store agent identifiers as text.

Store APIs must stop converting database text through a closed enum. Any
non-empty identifier read from a usage row is valid. Existing rows for the six
known identifiers remain readable without rewriting them.

Maintenance operates over agent identifiers present in storage rather than a
compiled list. Date normalization and delta backfills must therefore include
unknown and currently undiscovered agents as well as visible agents.

Neither discovery changes nor toggle changes delete rows. Historical retention
continues to follow the existing VibePulse database behavior.

## Failure handling

### Discovery failure

If the aggregate discovery command fails or returns unusable JSON:

- retain the previous `discoveredAgentIDs` cache;
- retain every agent's stored data and disabled preference;
- keep the existing Settings controls visible;
- report the agentsview error through the existing status surface;
- do not replace the discovery cache with an empty set.

No per-agent import starts from an untrusted discovery result. The next
scheduled or manual refresh retries discovery.

### Individual import failure

If one discovered agent's filtered report fails:

- record an error prefixed with that agent's display name;
- continue importing all remaining discovered agents;
- retain the failed agent's previous daily totals and samples;
- keep the agent visible and preserve its toggle.

The overall refresh status may report multiple agent failures using the
existing combined-error presentation.

### Empty and zero-cost data

An empty but valid aggregate report is a successful discovery with no visible
agents. Agents present only in session counts, or present in breakdowns with a
30-day aggregate cost of exactly zero, remain hidden for now.

A positive cost explicitly reported by agentsview qualifies even if agentsview
has no computed pricing rate for that source. VibePulse treats agentsview's
reported `cost` as authoritative.

## Compatibility boundary

VibePulse supports an agent when all of the following are true:

1. the installed agentsview version parses the agent's local data;
2. `agentsview usage daily --json --breakdown --since 30d` includes the agent
   in an `agentBreakdowns` row during the past 30 days;
3. those rows sum to a positive cost;
4. the per-agent `usage daily --json --agent <id>` report follows the supported
   JSON contract VibePulse consumes.

Within that boundary, VibePulse accepts the identifier dynamically and does not
need an agent-specific release. Agents that do not expose token or cost data
through agentsview are outside the visible set until agentsview can report a
positive cost for them.

VibePulse should parse only the fields it needs and ignore unknown additive
JSON fields. Discovery fails clearly when required daily agent-breakdown fields
are absent or malformed rather than silently interpreting a different shape.

## Documentation and copy changes

Update README requirements, highlights, Settings documentation, welcome copy,
and troubleshooting text to avoid presenting Claude Code, Codex, Pi, Gemini,
OMP, and OpenCode as an exhaustive support list.

Examples may name familiar agents, but they must be introduced as examples.
The primary wording should state that VibePulse discovers locally used,
positive-cost agents through agentsview's rolling 30-day usage report.

Troubleshooting should direct users to:

```bash
agentsview usage daily --json --breakdown --since 30d
```

when an expected agent does not appear. The explanation should mention the
30-day and positive-cost requirements.

## Testing strategy

### Discovery parsing

- Parse multiple daily `agentBreakdowns` arrays and sum costs by identifier.
- Include arbitrary future identifiers without code changes.
- Exclude zero-cost aggregate agents.
- Treat an empty valid report as a successful empty discovery.
- Reject malformed required agent breakdown fields without replacing cached
  discovery state.

### Dynamic identity and presentation

- Construct agents from arbitrary non-empty database and report identifiers.
- Preserve exact raw identifiers in commands, storage, and preferences.
- Verify curated labels for known identifiers.
- Verify deterministic generated labels and ordering for unknown identifiers.
- Verify palette and series logic can accept previously unseen agents.

### Refresh behavior

- Import every discovered agent, including disabled agents.
- Continue after one agent import fails.
- Retain the prior discovery list when discovery fails.
- Replace the visible discovery list after a successful empty result.
- Verify newly discovered agents default to enabled.

### Filtering and persistence

- Exclude disabled agents from totals, charts, and breakdowns.
- Keep disabled agents' imported rows available in storage.
- Restore data immediately when an agent is re-enabled.
- Retain disabled preferences when an agent disappears and reappears.
- Migrate existing false legacy toggles into `disabledAgentIDs`, remove the
  legacy keys, and avoid a permanent fallback path.

### Store and maintenance

- Read and write usage for arbitrary agent identifiers.
- Include unknown and currently hidden identifiers in maintenance operations.
- Preserve existing known-agent rows without a database rewrite.

## Acceptance criteria

The feature is complete when:

- no compiled enum or functional allowlist limits which agents can be imported;
- Settings shows exactly the positive-cost agents discovered from the latest
  successful rolling 30-day report;
- every discovered agent is imported whether enabled or disabled;
- new agents default to visible and enabled;
- disabling an agent affects presentation only and never deletes or stops
  storing its data;
- agent choices survive disappearance, rediscovery, app restart, and migration
  from existing fixed toggles;
- discovery and individual import failures preserve prior usable state;
- documentation states that all qualifying agents parsed by agentsview should
  work without a VibePulse-specific support update.
