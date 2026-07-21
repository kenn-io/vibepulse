import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        dataSourcesSection
        sectionDivider
        startupSection
        sectionDivider
        dependenciesSection
        sectionDivider
        refreshSection
        sectionDivider
        maintenanceSection
        sectionDivider
        aboutSection
      }
      .padding(.horizontal, 28)
      .padding(.vertical, 22)
    }
    .frame(width: 620, height: 620)
    .background(Color(nsColor: .windowBackgroundColor))
  }

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
              ProgressView()
                .controlSize(.small)
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

  private var startupSection: some View {
    settingsSection("Startup") {
      settingsRow("Launch") {
        VStack(alignment: .leading, spacing: 4) {
          Toggle("Start at login", isOn: $model.startAtLogin)
            .toggleStyle(.checkbox)

          if let message = model.loginItemMessage {
            helperText(message)
          }
        }
      }
    }
  }

  private var dependenciesSection: some View {
    settingsSection("Dependencies") {
      settingsRow("agentsview path", alignment: .top) {
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 8) {
            TextField(
              "Leave blank to auto-detect",
              text: $model.agentsviewPath
            )
            .textFieldStyle(.roundedBorder)

            Button("Clear") {
              model.agentsviewPath = ""
            }
            .disabled(model.agentsviewPath.isEmpty)
          }

          helperText("Example: ~/.local/bin/agentsview")
        }
      }
    }
  }

  private var refreshSection: some View {
    settingsSection("Refresh") {
      settingsRow("Update Frequency") {
        HStack(spacing: 14) {
          Picker("Update Frequency", selection: $model.refreshInterval) {
            ForEach(RefreshInterval.allCases) { interval in
              Text(interval.title).tag(interval)
            }
          }
          .labelsHidden()
          .frame(width: 210, alignment: .leading)

          Button("Refresh Now") {
            model.refreshNow()
          }
          .disabled(model.isRefreshing)
        }
      }
    }
  }

  private var maintenanceSection: some View {
    settingsSection("Maintenance") {
      settingsRow("Data Maintenance", alignment: .top) {
        VStack(alignment: .leading, spacing: 8) {
          Picker("Data Maintenance", selection: $model.maintenanceMode) {
            ForEach(MaintenanceMode.allCases) { mode in
              Text(mode.title).tag(mode)
            }
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(width: 280, alignment: .leading)

          helperText(model.maintenanceMode.detail)

          HStack(spacing: 12) {
            Button("Run Maintenance Now") {
              model.runMaintenance(force: true)
            }
            .disabled(model.isMaintaining)

            if let lastRun = model.lastMaintenanceAt {
              helperText("Last run \(lastRun.formatted(date: .omitted, time: .shortened))")
            }
          }

          if let message = model.maintenanceMessage {
            helperText(message)
          }
        }
      }
    }
  }

  private var aboutSection: some View {
    settingsSection("About") {
      settingsRow("") {
        VStack(alignment: .leading, spacing: 5) {
          Text(AppInfo.displayName)
            .font(.headline)

          HStack(spacing: 14) {
            helperText("Version \(AppInfo.version)")
            helperText("Git \(AppInfo.gitHash)")
          }

          helperText("Built \(AppInfo.buildDate)")
          helperText("Copyright (c) \(AppInfo.currentYear) Wes McKinney")
        }
      }
    }
  }

  private var sectionDivider: some View {
    Divider()
      .padding(.vertical, 14)
  }

  private func settingsSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.headline)
      content()
    }
  }

  private func settingsRow<Content: View>(
    _ title: String,
    alignment: VerticalAlignment = .center,
    @ViewBuilder content: () -> Content
  ) -> some View {
    HStack(alignment: alignment, spacing: 16) {
      Text(title)
        .font(.callout)
        .foregroundColor(.secondary)
        .frame(width: 130, alignment: .trailing)

      content()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

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

  private func helperText(_ text: String) -> some View {
    Text(text)
      .font(.caption)
      .foregroundColor(.secondary)
  }
}
