import SwiftUI
import UsageCore

struct SetupView: View {
    let model: UsageModel
    let chooseExecutable: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Picker("Usage mode", selection: Binding(get: { model.isDemo }, set: model.setDemo)) {
                        Text("Demo").tag(true)
                        Text("Live Usage").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 230)
                    Spacer()
                    if model.refreshingCodex && !model.isDemo {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Refreshing Codex")
                    }
                    Button("Refresh Now", action: model.refresh)
                        .keyboardShortcut("r", modifiers: .command)
                }

                ForEach(Provider.allCases, id: \.self) { provider in
                    UsageDetails(reading: model.display(for: provider), isDemo: model.isDemo)
                        .padding(16)
                        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                }

                Divider()

                PerplexitySetupView(model: model)

                Divider()

                VStack(alignment: .leading, spacing: 9) {
                    Text("Connect Codex").font(.headline).accessibilityAddTraits(.isHeader)
                    Text("Run `codex login` in Terminal and sign in with ChatGPT. UsageApp looks for Codex in common install locations.")
                        .foregroundStyle(.secondary)
                    if let path = model.codexPath {
                        Text(path).font(.callout.monospaced()).textSelection(.enabled)
                    }
                    HStack {
                        Button("Choose Codex Executable…", action: chooseExecutable)
                        if model.codexPath != nil {
                            Button("Use Automatic Discovery") { model.setCodexExecutable(nil) }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("Connect Claude Code").font(.headline).accessibilityAddTraits(.isHeader)
                    Text("Follow the README’s Claude Code setup to add the bundled helper and keep your current status line. The first eligible Claude Code response supplies the usage data.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(22)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }
}
