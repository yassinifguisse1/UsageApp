import ServiceManagement
import SwiftUI
import UsageCore

struct GeneralSettingsPane: View {
    @Bindable var model: UsageModel
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Picker("Readings", selection: $model.usesDemoReadings) {
                    Text("Live Usage").tag(false)
                    Text("Demo").tag(true)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(model.isDemo
                     ? "Demo shows sample readings. Switch to Live Usage, then connect each provider in its pane."
                     : "Connect each provider in its pane. Refresh Now in the menu checks them all.")
                    .settingsFootnote()
            }

            Section {
                Picker("Position", selection: $model.panelPlacement) {
                    ForEach(PanelPlacement.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Show the panel", selection: $model.revealsPanelOnHover) {
                    Text(model.panelPlacement == .notch ? "When pointing at the notch" : "When pointing at the edge")
                        .tag(true)
                    Text("Always").tag(false)
                }
                ForEach(Provider.allCases, id: \.self) { provider in
                    Toggle(isOn: $model[showing: provider]) {
                        Label {
                            Text(provider.name)
                        } icon: {
                            ProviderMark(provider: provider, size: 16)
                        }
                    }
                    .disabled(model[showing: provider] && model.visibleProviders.count == 1)
                }
                Picker("Check Codex every", selection: $model.codexRefreshMinutes) {
                    ForEach([1, 2, 5], id: \.self) { Text("\($0) min").tag($0) }
                }
            } header: {
                Text("Panel")
            } footer: {
                if model.panelPlacement == .notch {
                    Text("The panel hangs from the notch and shows the busiest reading beside it. On a display without a notch it sits in the middle of the menu bar.")
                        .settingsFootnote()
                }
            }

            Section {
                Toggle("Open at login", isOn: Binding(get: { opensAtLogin }, set: setOpensAtLogin))
                if loginStatus == .requiresApproval {
                    LabeledContent("Allow UsageApp in Login Items to finish turning this on.") {
                        Button("Open Login Items", action: SMAppService.openSystemSettingsLoginItems)
                    }
                    .settingsFootnote()
                }
                if let loginError {
                    Text(loginError).settingsFootnote()
                }
                Toggle("Check for updates automatically", isOn: $model.checksForUpdates)
                if let update = model.availableUpdate {
                    LabeledContent("UsageApp \(update.version.description) is available.") {
                        Link("Download", destination: update.url)
                    }
                }
            } header: {
                Text("App")
            } footer: {
                Text("The update check asks GitHub for the latest release once a day and sends no identifiers.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
        .settingsPaneFrame()
        .onAppear(perform: refreshLoginStatus)
    }

    private var opensAtLogin: Bool {
        loginStatus == .enabled || loginStatus == .requiresApproval
    }

    private func refreshLoginStatus() {
        loginStatus = SMAppService.mainApp.status
    }

    private func setOpensAtLogin(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            loginError = "UsageApp couldn’t change its login item. Move it to Applications and try again."
        }
        refreshLoginStatus()
    }
}
