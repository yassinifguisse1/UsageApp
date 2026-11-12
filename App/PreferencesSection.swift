import ServiceManagement
import SwiftUI
import UsageCore

struct PreferencesSection: View {
    let model: UsageModel
    let requestNotifications: () async -> Bool
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?
    @State private var notificationsDenied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("General")
                .font(.system(size: 16, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            Toggle("Open UsageApp at login", isOn: Binding(
                get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                set: setOpensAtLogin
            ))
            if loginStatus == .requiresApproval {
                note("Allow UsageApp in Login Items to finish turning this on.")
                Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let loginError { note(loginError) }

            Toggle("Check for updates daily", isOn: Binding(get: { model.checksForUpdates }, set: model.setChecksForUpdates))
            if let update = model.availableUpdate {
                Link("Download UsageApp \(update.version.description)", destination: update.url)
            }

            Divider()

            HStack {
                Toggle("Notify me at", isOn: Binding(get: { model.alertsEnabled }, set: setAlertsEnabled))
                Picker("Threshold", selection: Binding(get: { model.alertThreshold }, set: model.setAlertThreshold)) {
                    ForEach([75.0, 90, 95], id: \.self) { Text(UsageFormat.percent($0)).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .disabled(!model.alertsEnabled)
                Text("and at the limit")
                    .foregroundStyle(model.alertsEnabled ? .primary : .secondary)
            }
            Toggle("Notify when a window resets", isOn: Binding(get: { model.alertsOnReset }, set: model.setAlertsOnReset))
                .disabled(!model.alertsEnabled)
            if notificationsDenied {
                note("Notifications are off for UsageApp in System Settings.")
                Button("Open Notification Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                }
            } else {
                note("While notifications are on, UsageApp keeps checking in the background at a slower pace.")
            }

            Divider()

            Picker("Show the panel", selection: Binding(get: { model.revealsPanelOnHover }, set: model.setRevealsPanelOnHover)) {
                Text("When pointing at the edge").tag(true)
                Text("Always").tag(false)
            }
            .fixedSize()
            note("When pointing at the edge, a slim tab marks the panel. Move the pointer to the edge beside it to slide the panel out.")

            Text("Show in panel")
            HStack(spacing: 16) {
                ForEach(Provider.allCases, id: \.self) { provider in
                    let shown = !model.hiddenProviders.contains(provider)
                    Toggle(provider.name, isOn: Binding(get: { shown }, set: { model.setProvider(provider, shown: $0) }))
                        .toggleStyle(.checkbox)
                        .disabled(shown && model.visibleProviders.count == 1)
                }
            }

            Picker("Check Codex every", selection: Binding(get: { model.codexRefreshMinutes }, set: model.setCodexRefreshMinutes)) {
                ForEach([1, 2, 5], id: \.self) { Text("\($0) min").tag($0) }
            }
            .fixedSize()
        }
        .onAppear { loginStatus = SMAppService.mainApp.status }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func setOpensAtLogin(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            loginError = "UsageApp couldn’t change its login item. Move it to Applications and try again."
        }
        loginStatus = SMAppService.mainApp.status
    }

    private func setAlertsEnabled(_ enabled: Bool) {
        guard enabled else {
            model.setAlertsEnabled(false)
            return
        }
        Task {
            let allowed = await requestNotifications()
            notificationsDenied = !allowed
            model.setAlertsEnabled(allowed)
        }
    }
}
