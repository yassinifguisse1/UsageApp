import Foundation
import Testing
import UsageCore

@Test func codexLegacyResultUsesEpochSecondsAndDoesNotInventASecondaryWindow() throws {
    let windows = try CodexUsageParser.parse(Data(#"""
    {
      "rateLimits": {
        "primary": {"usedPercent": 0, "windowDurationMins": 300, "resetsAt": 1781654400},
        "secondary": null
      }
    }
    """#.utf8))
    let first = try #require(windows.first)
    #expect(windows.count == 1)
    #expect(first.id == "codex/primary")
    #expect(first.usedPercent == 0)
    #expect(first.resetsAt == Date(timeIntervalSince1970: 1781654400))
    #expect(first.label == "5-hour window")
    #expect(first.isPrimary)
}

@Test func codexMultiBucketResultDeduplicatesAndKeepsAllReportedWindows() throws {
    let windows = try CodexUsageParser.parse(Data(#"""
    {
      "rateLimits": {
        "limitId": "codex",
        "primary": {"usedPercent": 5},
        "secondary": {"usedPercent": 12, "windowDurationMins": 10080}
      },
      "rateLimitsByLimitId": {
        "codex": {"primary": {"usedPercent": 20, "windowDurationMins": 300}},
        "fast": {
          "limitName": "Fast",
          "primary": {"usedPercent": 83, "windowDurationMins": 60},
          "secondary": {"usedPercent": 30, "windowDurationMins": 10080}
        },
        "missing": null
      }
    }
    """#.utf8))
    #expect(windows.map(\.id) == ["codex/primary", "codex/secondary", "fast/primary", "fast/secondary"])
    #expect(windows.map(\.usedPercent) == [20, 12, 83, 30])
    #expect(windows.filter(\.isPrimary).map(\.id) == ["codex/primary"])
    #expect(windows.last?.label == "Fast · 7-day window")
    #expect(windows.first?.resetsAt == nil)
}

@Test func codexRejectsMalformedFieldsWithoutDroppingOtherBuckets() throws {
    let windows = try CodexUsageParser.parse(Data(#"""
    {
      "rateLimitsByLimitId": {
        "codex": {
          "primary": {"usedPercent": true},
          "secondary": {"usedPercent": "0"}
        },
        "other": {
          "primary": {"usedPercent": 2.5, "resetsAt": "soon"},
          "secondary": {"usedPercent": 101}
        }
      }
    }
    """#.utf8))
    #expect(windows.map(\.id) == ["other/primary"])
    #expect(windows.first?.usedPercent == 2.5)
    #expect(windows.first?.resetsAt == nil)
    #expect(try CodexUsageParser.parse(Data("{}".utf8)).isEmpty)
    #expect(throws: (any Error).self) { try CodexUsageParser.parse(Data("[".utf8)) }
}

@Test func claudeParsesPartialSubscriptionAndGatewayDataWithoutTreatingAbsenceAsZero() throws {
    let observed = Date(timeIntervalSince1970: 1781654300)
    let sample = try ClaudeUsageParser.parse(Data(#"""
    {
      "rate_limits": {
        "five_hour": {"used_percentage": 23.5, "resets_at": 1781654400},
        "seven_day": {"used_percentage": false},
        "spend_limit": {"used_percentage": 0, "resets_at": null, "limit_usd": 500}
      }
    }
    """#.utf8), observedAt: observed)
    #expect(sample.observedAt == observed)
    #expect(sample.windows.map(\.id) == ["five_hour", "spend_limit"])
    #expect(sample.windows.map(\.usedPercent) == [23.5, 0])
    #expect(sample.windows.first?.isPrimary == true)
    #expect(sample.windows.last?.resetsAt == nil)

    let missing = try ClaudeUsageParser.parse(Data(#"{"context_window":{"used_percentage":0}}"#.utf8), observedAt: observed)
    #expect(missing.windows.isEmpty)
    #expect(throws: (any Error).self) {
        try ClaudeUsageParser.parse(Data("[]".utf8), observedAt: observed)
    }
}

@Test func unknownLimitShapesAreDistinguishedFromAbsentLimits() throws {
    let codexUnknown = Data(#"{"rateLimits":{"primary":{"usedFraction":0.4}}}"#.utf8)
    #expect(try CodexUsageParser.parse(codexUnknown).isEmpty)
    #expect(CodexUsageParser.reportsLimits(in: codexUnknown))
    #expect(!CodexUsageParser.reportsLimits(in: Data(#"{"rateLimits":{"primary":null,"secondary":null}}"#.utf8)))
    #expect(!CodexUsageParser.reportsLimits(in: Data("{}".utf8)))

    let claudeUnknown = Data(#"{"rate_limits":{"five_hours":{"used":40}}}"#.utf8)
    #expect(try ClaudeUsageParser.parse(claudeUnknown, observedAt: Date()).windows.isEmpty)
    #expect(ClaudeUsageParser.reportsLimits(in: claudeUnknown))
    #expect(!ClaudeUsageParser.reportsLimits(in: Data(#"{"rate_limits":{}}"#.utf8)))
    #expect(!ClaudeUsageParser.reportsLimits(in: Data(#"{"context_window":{"used_percentage":0}}"#.utf8)))
}
