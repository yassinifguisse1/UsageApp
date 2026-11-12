import Foundation

public enum CodexUsageParser {
    public static func parse(_ data: Data) throws -> [UsageWindow] {
        try windows(from: ProviderJSON.object(from: data))
    }

    static func windows(from result: ProviderJSON.Object) -> [UsageWindow] {
        let legacy = result["rateLimits"] as? ProviderJSON.Object
        let legacyID = legacy?["limitId"] as? String ?? "codex"
        var buckets = (result["rateLimitsByLimitId"] as? ProviderJSON.Object ?? [:])
            .compactMapValues { $0 as? ProviderJSON.Object }

        if let legacy {
            // Prefer the multi-bucket representation. Fill any missing legacy slots once.
            buckets[legacyID] = (buckets[legacyID] ?? [:]).merging(legacy) { current, old in
                current is NSNull ? old : current
            }
        }
        let primaryID = buckets.keys.contains("codex") ? "codex" : legacyID
        let orderedIDs = buckets.keys.sorted {
            if $0 == primaryID { return $1 != primaryID }
            if $1 == primaryID { return false }
            return $0 < $1
        }
        return orderedIDs.flatMap { id -> [UsageWindow] in
            guard let bucket = buckets[id] else { return [] }
            let name = (bucket["limitName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
            return ["primary", "secondary"].compactMap { slot in
                guard let object = bucket[slot] as? ProviderJSON.Object,
                      let percent = ProviderJSON.percent(object["usedPercent"]) else { return nil }
                let duration = durationLabel(object["windowDurationMins"])
                    ?? (slot == "primary" ? "Primary window" : "Secondary window")
                return UsageWindow(
                    id: "\(id)/\(slot)",
                    label: id == primaryID ? duration : "\(name) · \(duration)",
                    usedPercent: percent,
                    resetsAt: ProviderJSON.reset(object["resetsAt"]),
                    isPrimary: id == primaryID && slot == "primary"
                )
            }
        }
    }

    private static func durationLabel(_ value: Any?) -> String? {
        guard let number = ProviderJSON.number(value),
              let minutes = Int(exactly: number), minutes > 0 else { return nil }
        if minutes.isMultiple(of: 1440) { return "\(minutes / 1440)-day window" }
        if minutes.isMultiple(of: 60) { return "\(minutes / 60)-hour window" }
        return "\(minutes)-minute window"
    }
}
