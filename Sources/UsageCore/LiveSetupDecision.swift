public enum LiveSetupDecision: Equatable {
    case wait, open, finish

    /// Only call for a pending explicit switch to Live Usage.
    public static func evaluate(readings: [ProviderDisplay], checking: Bool) -> Self {
        if readings.contains(where: { $0.setupAction != nil }) { return .open }
        return checking ? .wait : .finish
    }
}
