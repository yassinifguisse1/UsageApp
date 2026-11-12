import SwiftUI
import UsageCore

struct NotificationSettingsPane: View {
    @Bindable var model: UsageModel
    let requestNotifications: () async -> Bool
    @State private var denied = false

    var body: some View {
        Form {
            Section {
                Toggle("Usage alerts", isOn: $model.alertsEnabled)
                Picker("Notify at", selection: $model.alertThreshold) {
                    ForEach([75.0, 90, 95], id: \.self) { Text(UsageFormat.percent($0)).tag($0) }
                }
                .disabled(!model.alertsEnabled)
                Toggle("Notify when a window resets", isOn: $model.alertsOnReset)
                    .disabled(!model.alertsEnabled)
            } footer: {
                Text("Claude Code and Codex alerts arrive once per window period at your chosen level and again at the limit. While alerts are on, UsageApp keeps checking with the panel hidden, at a slower pace.")
                    .settingsFootnote()
            }

            if denied {
                Section {
                    LabeledContent("Notifications are off for UsageApp.") {
                        Button("Open Notification Settings", action: openNotificationSettings)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .settingsPaneFrame()
        .onChange(of: model.alertsEnabled) { _, enabled in
            if enabled { confirmPermission() }
        }
    }

    private func confirmPermission() {
        Task {
            let allowed = await requestNotifications()
            denied = !allowed
            if !allowed { model.alertsEnabled = false }
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
