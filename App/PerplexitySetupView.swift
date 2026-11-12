import SwiftUI
import UsageCore

struct PerplexitySetupView: View {
    let model: UsageModel
    @State private var remaining: Int?
    @State private var allowance: Int?
    @State private var hasReset = false
    @State private var resetDate = Date.now
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Track Perplexity Computer").font(.headline).accessibilityAddTraits(.isHeader)
            Text("Enter the plan credit balance and allowance from Perplexity Usage. Enter the reset time if it’s shown.")
                .foregroundStyle(.secondary)
            Link("Open Perplexity Usage", destination: URL(string: "https://www.perplexity.ai/account/usage")!)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Remaining plan credits").accessibilityHidden(true)
                    TextField("Remaining plan credits", value: $remaining, format: .number)
                        .labelsHidden()
                        .frame(width: 110)
                }
                GridRow {
                    Text("Plan credit allowance").accessibilityHidden(true)
                    TextField("Plan credit allowance", value: $allowance, format: .number)
                        .labelsHidden()
                        .frame(width: 110)
                }
            }

            Toggle("Include reset time", isOn: $hasReset)
            if hasReset {
                DatePicker("Reset time", selection: $resetDate, displayedComponents: [.date, .hourAndMinute])
            }

            HStack {
                Button("Save Reading", action: save)
                    .disabled(snapshot == nil)
                if model.perplexitySnapshot != nil {
                    Button("Clear Reading", action: clear)
                }
                if saved {
                    Text(model.isDemo ? "Saved for Live Usage" : "Reading saved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: remaining) { saved = false }
        .onChange(of: allowance) { saved = false }
        .onChange(of: hasReset) { saved = false }
        .onChange(of: resetDate) { saved = false }
    }

    private var snapshot: PerplexityCreditSnapshot? {
        let now = Date.now
        guard let remaining, let allowance, !hasReset || resetDate > now else { return nil }
        let reading = PerplexityCreditSnapshot(
            remaining: remaining, allowance: allowance,
            recordedAt: now, resetsAt: hasReset ? resetDate : nil
        )
        return reading.usedPercent != nil ? reading : nil
    }

    private func load() {
        let snapshot = model.perplexitySnapshot
        remaining = snapshot?.remaining
        allowance = snapshot?.allowance
        hasReset = snapshot?.resetsAt != nil
        resetDate = snapshot?.resetsAt ?? Date.now
    }

    private func save() {
        guard let snapshot else { return }
        model.setPerplexitySnapshot(snapshot)
        saved = true
    }

    private func clear() {
        model.setPerplexitySnapshot(nil)
        load()
        saved = false
    }
}
