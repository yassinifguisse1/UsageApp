import SwiftUI
import UsageCore

struct ProviderSettingsPane: View {
    @Bindable var model: UsageModel
    let provider: Provider
    let chooseExecutable: () -> Void

    var body: some View {
        let reading = model.display(for: provider)
        Form {
            Section {
                UsageDetails(reading: reading, isDemo: model.isDemo, trend: model.trend(for: provider))
                    .padding(.vertical, 4)
            }

            Section("Connection") {
                if model.isDemo {
                    LabeledContent("Demo readings are showing.") {
                        Button("Switch to Live Usage") { model.usesDemoReadings = false }
                    }
                } else {
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
        }
        .formStyle(.grouped)
        .settingsPaneFrame()
    }
}

extension View {
    /// Settings panes share one width. Each pane's height follows its content, up to a limit.
    func settingsPaneFrame() -> some View {
        frame(width: 540)
            .frame(minHeight: 260, idealHeight: 520, maxHeight: 640)
    }

    func settingsFootnote() -> some View {
        font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
