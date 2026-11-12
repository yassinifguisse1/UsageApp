import SwiftUI
import UsageCore

struct SetupView: View {
    let model: UsageModel
    let chooseExecutable: () -> Void
    let requestNotifications: () async -> Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Picker("Usage mode", selection: Binding(get: { model.isDemo }, set: model.setDemo)) {
                        Text("Demo").tag(true)
                        Text("Live Usage").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 230)
                    Spacer()
                    if !model.isDemo {
                        Button("Refresh Now", action: model.refresh)
                            .keyboardShortcut("r", modifiers: .command)
                    }
                }

                if model.isDemo {
                    Text("These are sample readings. Switch to Live Usage to check or connect each provider.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Connect any provider to start seeing your actual usage.")
                        .foregroundStyle(.secondary)
                }

                PreferencesSection(model: model, requestNotifications: requestNotifications)
                    .padding(16)
                    .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

                ForEach(Provider.allCases, id: \.self) { provider in
                    let reading = model.display(for: provider)
                    VStack(alignment: .leading, spacing: 14) {
                        UsageDetails(reading: reading, isDemo: model.isDemo, trend: model.trend(for: provider))
                        if !model.isDemo {
                            Divider()
                            switch provider {
                            case .codex:
                                CodexConnectionControls(model: model, reading: reading, chooseExecutable: chooseExecutable)
                            case .claude:
                                ClaudeConnectionControls(model: model, reading: reading)
                            case .perplexity:
                                PerplexitySetupView(model: model)
                            }
                        }
                    }
                    .padding(16)
                    .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(22)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }
}
