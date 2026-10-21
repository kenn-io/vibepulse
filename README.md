# VibePulse

VibePulse is a macOS menu bar app that tracks token spend for locally used AI coding agents parsed by [agentsview](https://github.com/kenn-io/agentsview).

## Highlights

- Agents parsed by the installed agentsview version appear when they have positive-cost usage in the selected history window
- Combined daily total in the menu bar (what you would pay per token without a subscription)
- Today view shows cumulative spend over the day
- 7-day and 30-day views show daily totals
- 1-year view shows monthly totals for the last 12 calendar months, including the current month
- Group charts by agent, model, or machine
- Configurable refresh schedule
- Built-in data maintenance for historical imports

## Screenshots

<p align="center">
  <img src="docs/screenshots/vibepulse_today.png" alt="Today view" width="48%" />
  <img src="docs/screenshots/vibepulse_30day.png" alt="30-day view" width="48%" />
</p>

## Requirements

- macOS 13+ (Ventura)
- [agentsview](https://github.com/kenn-io/agentsview) current release installed with `usage daily --timezone` support (`agentsview` on PATH or path set in Settings)
- Local usage from at least one agentsview-parsed agent with priced activity in the past year

## Install

1. Download the latest `.dmg` from GitHub Releases.
2. Drag `VibePulse.app` to your Applications folder.
3. Launch it. If macOS blocks the app, open System Settings -> Privacy & Security and allow it.

## First run

<p align="center">
  <img src="docs/screenshots/vibepulse_welcome.png" alt="Welcome" width="50%" />
</p>

- A welcome window explains the agentsview requirement, notes the default 15-minute refresh cadence, and lets you toggle start at login.
- You can revisit Settings from the menu bar at any time.

## agentsview setup

Install agentsview:

```bash
curl -fsSL https://agentsview.io/install.sh | bash
```

This installs `agentsview` to `~/.local/bin/agentsview` or `/usr/local/bin/agentsview`.

VibePulse runs outside your shell, so if `agentsview` is installed to a non-standard location, set the path in **Settings -> Dependencies**. To read from a PostgreSQL-backed `agentsview pg serve` instance instead, set its URL there; for example, `http://127.0.0.1:18080`.

For mise installations, VibePulse automatically checks `~/.local/share/mise/shims/agentsview` before standalone installations. The shim follows your mise-selected version as it changes. If you set the path manually, enter the absolute path to the shim, expanding `~` to your home directory. The field accepts an executable file path; shell commands such as `mise exec -- agentsview` belong in a terminal.

## Settings

<p align="center">
  <img src="docs/screenshots/vibepulse_settings.png" alt="Settings" width="50%" />
</p>

- **Data Sources**: VibePulse discovers agents with positive-cost usage in the past 30 days, or the past 12 calendar months after selecting **1 Year**. Turning one off hides it from totals and charts without stopping imports or deleting history.
- **Include automated sessions**: Enabled by default under Data Sources. Turn it off to exclude automated reviews from server reports. Both reports are fetched on every server refresh and cached separately, so changing this setting switches histories without fetching again. This setting is unavailable with the local CLI, which always includes automated sessions.
- **Startup**: Start VibePulse at login (macOS may require approval).
- **Dependencies**: Set an `agentsview pg serve` URL, or a custom local `agentsview` path.
- **Refresh**: Choose how often the app refreshes (5m, 15m, 1h, 4h, 1d). Opening the menu reuses fresh data until that interval expires. The Refresh button always fetches immediately.
- **Data Maintenance**: Normalize historical data and rerun import fixes.

Select **1 Year** to import older history and show monthly totals. The first load can take longer than a normal refresh. The app keeps that history locally and reuses the year import for the rest of the day while it is running. Between year imports, scheduled refreshes fetch only 30 days. While viewing the year, a new day or source/timezone change renews the year import, and **Refresh** reloads it immediately.

## Security & privacy

- All usage data stays local on your machine.
- Usage databases live in `~/Library/Application Support/VibePulse/`: `vibepulse.sqlite` holds combined usage and `vibepulse-non-automated.sqlite` holds usage without automation.
- VibePulse has no analytics or telemetry.
- It runs an aggregate agentsview usage report to discover agents, then filtered per-agent reports to store their usage. Server connections fetch both combined and non-automated reports; the local CLI supplies only combined usage. Normal refreshes cover 30 days; year imports cover the last 12 calendar months. Reports come from the configured server when present, otherwise from the local CLI. The Machine view uses labels from the CLI report or the configured server to show names instead of installation IDs.

## Troubleshooting

- **Agent not shown**: Run `agentsview usage daily --format json --breakdown --since 30d --timezone America/Los_Angeles` in Terminal, replacing the timezone with your system's IANA identifier. The agent must appear in `agentBreakdowns` with positive total cost during that window.
- **No data**: Run `agentsview usage daily` in Terminal to verify usage data exists.
- **agentsview not found**: Install agentsview or set the path in Settings -> Dependencies.
- **Start at login**: macOS may require approval in System Settings -> Login Items.

## Local development

```bash
swift run
```

## Build a DMG

```bash
scripts/build_dmg.sh v0.1.0
```

The DMG will be created in `dist/`.


## License

MIT
