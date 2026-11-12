import SwiftUI
import UsageCore

struct ClaudeSetupReview: View {
    let preview: ClaudeSetupInstaller.Preview
    let applying: Bool
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review Claude Code Setup")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(preview.createsSettingsFile ? "UsageApp will create your personal settings file." :
                    "UsageApp will update the status-line command in your personal settings.")
            Text(preview.settingsURL.path)
                .font(.callout.monospaced())
                .textSelection(.enabled)

            if let original = preview.originalCommand {
                LabeledContent("Current command") {
                    Text(original).textSelection(.enabled)
                }
            }
            LabeledContent("New command") {
                Text(preview.installedCommand).textSelection(.enabled)
            }
            Text(preview.originalCommand == nil
                 ? "The helper receives usage from Claude Code. You can undo setup in Settings."
                 : "Your existing script will still receive Claude Code’s input and provide the status-line output. You can undo setup in Settings.")
                .foregroundStyle(.secondary)
            Text("If your session uses a custom settings path or an override, use Manual Setup for that session.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                if applying { ProgressView().controlSize(.small).accessibilityLabel("Applying setup") }
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(applying)
                Button("Apply Setup", action: onApply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(applying)
            }
        }
        .padding(22)
        .frame(width: 470)
    }
}
