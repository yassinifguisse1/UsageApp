import AppKit
import SwiftUI
import UsageCore

struct ClaudeConnectionControls: View {
    let model: UsageModel
    let reading: ProviderDisplay
    @State private var preview: ClaudeSetupInstaller.Preview?
    @State private var busy = false
    @State private var error: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if reading.setupAction == .configureClaude || (!model.claudeConnection.isConfigured && reading.state == .unavailable) {
                    Button("Review Setup", action: review)
                        .disabled(busy)
                }
                Button("Check for Reading", action: model.checkClaude)
                    .disabled(busy)
                if model.claudeConnection.canUndo {
                    Button("Undo Setup") { changeSettings(nil) }
                        .disabled(busy)
                }
                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Updating Claude Code setup")
                }
            }

            if let error {
                Text(error)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DisclosureGroup("Manual Setup") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Use manual setup for custom settings directories, project overrides, or shell commands with arguments or pipelines.")
                        .foregroundStyle(.secondary)
                    Button(copied ? "Copied Instructions" : "Copy Manual Instructions", action: copyInstructions)
                    Link("Claude Code Status Line Help", destination: URL(string: "https://code.claude.com/docs/en/statusline")!)
                }
                .padding(.top, 8)
            }
        }
        .sheet(item: $preview) { item in
            ClaudeSetupReview(preview: item, applying: busy, onApply: { changeSettings(item) })
                .interactiveDismissDisabled(busy)
        }
    }

    private func review() {
        error = nil
        let installer = model.claudeInstaller
        busy = true
        Task {
            let result = await Task.detached { Result { try installer.preview() } }.value
            busy = false
            switch result {
            case .success(let next): preview = next
            case .failure(let problem): error = problem.localizedDescription
            }
        }
    }

    private func changeSettings(_ reviewed: ClaudeSetupInstaller.Preview?) {
        guard !busy else { return }
        error = nil
        busy = true
        let installer = model.claudeInstaller
        Task {
            let result = await Task.detached {
                Result {
                    if let reviewed { try installer.apply(reviewed) }
                    else { try installer.undo() }
                }
            }.value
            busy = false
            preview = nil
            switch result {
            case .success: model.claudeSetupChanged(wasUndone: reviewed == nil)
            case .failure(let problem): error = problem.localizedDescription
            }
        }
    }

    private func copyInstructions() {
        let helper = Bundle.main.url(forAuxiliaryExecutable: "usageapp-claude-status")?.path
            ?? "/Applications/UsageApp.app/Contents/MacOS/usageapp-claude-status"
        let source = "'" + helper.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let instructions = """
        Run in Terminal:
          mkdir -p "$HOME/.local/bin"
          install -m 755 \(source) "$HOME/.local/bin/usageapp-claude-status"

        In a local Claude Code session, run /status to identify your active settings. Back up the existing statusLine command. Keep all other settings and status-line options.

        In your editable settings.json, set statusLine.type to command. If you have no existing status line, set statusLine.command to this JSON value:
          "\\"$HOME/.local/bin/usageapp-claude-status\\""

        If you already have a script, pass its absolute path and any arguments after --. For shell expressions or pipelines, put the original command in an executable script that uses the same shell. For example:
          "\\"$HOME/.local/bin/usageapp-claude-status\\" -- \\"$HOME/.claude/my-status-line.sh\\""

        Ask your administrator about managed settings. Use Claude Code normally in a trusted project and check for a reading after an assistant response.
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(instructions, forType: .string)
        copied = true
    }
}
