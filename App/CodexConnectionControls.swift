import AppKit
import SwiftUI
import UsageCore

struct CodexConnectionControls: View {
    let model: UsageModel
    let reading: ProviderDisplay
    let chooseExecutable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if reading.setupAction == .installCodex || reading.setupAction == .updateCodex {
                Link("Codex CLI Install Instructions", destination: URL(string: "https://github.com/openai/codex#quickstart")!)
            }

            if reading.setupAction == .signInToCodex {
                Button(copied ? "Copied" : "Copy codex login", action: copyLoginCommand)
            }

            ViewThatFits(in: .horizontal) {
                HStack {
                    check
                    executableControl
                }
                VStack(alignment: .leading) {
                    check
                    executableControl
                }
            }
        }
        .onChange(of: reading.setupAction) { copied = false }
    }

    @State private var copied = false

    private var check: some View {
        HStack(spacing: 7) {
            Button("Check Connection", action: model.checkCodex)
                .disabled(model.refreshingCodex)
            if model.refreshingCodex {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Checking Codex")
            }
        }
    }

    @ViewBuilder private var executableControl: some View {
        if reading.setupAction == .installCodex {
            Button("Choose Executable…", action: chooseExecutable)
        } else {
            Menu("Codex CLI") {
                Button("Choose Executable…", action: chooseExecutable)
                if model.codexPath != nil {
                    Button("Use Automatic Discovery") { model.setCodexExecutable(nil) }
                }
            }
            .fixedSize()
        }
    }

    private func copyLoginCommand() {
        let command: String
        if let path = model.codexPath {
            command = "'" + path.replacing("'", with: "'\\''") + "' login"
        } else {
            command = "codex login"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copied = true
    }
}
