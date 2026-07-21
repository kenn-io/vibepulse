import SwiftUI

struct WelcomeView: View {
  @EnvironmentObject private var model: AppModel
  let onDismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Welcome to VibePulse")
        .font(.title2)

      Text(
        "VibePulse reads local AI coding-agent usage through agentsview. "
          + "Agents with priced usage in the past 30 days are discovered automatically. "
          + "Make sure agentsview is installed; you can set a custom path in Settings."
      )
      .font(.callout)
      .foregroundColor(.secondary)

      Toggle("Start VibePulse at login", isOn: $model.startAtLogin)

      if let message = model.loginItemMessage {
        Text(message)
          .font(.caption)
          .foregroundColor(.secondary)
      }

      HStack {
        Button("Open Settings") {
          model.openSettings()
        }
        .buttonStyle(.borderless)

        Spacer()

        Button("Continue") {
          onDismiss()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 360)
  }
}
