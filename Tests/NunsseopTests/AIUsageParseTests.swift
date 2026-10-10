import Foundation
import Testing
@testable import Nunsseop

struct AIUsageParseTests {
    private func data(_ lines: String...) -> Data { Data((lines.joined(separator: "\n") + "\n").utf8) }

    @Test func familyFollowsTheProviderThenTheModel() {
        #expect(AIUsageModel.family(provider: "anthropic", model: "claude-sonnet-5") == .claude)
        #expect(AIUsageModel.family(provider: "openai-codex", model: "gpt-5.5") == .codex)
        #expect(AIUsageModel.family(provider: "openai", model: nil) == .codex)
        #expect(AIUsageModel.family(provider: "Codex", model: nil) == .codex)
        #expect(AIUsageModel.family(provider: "chatgpt", model: "gpt-5.5") == .codex)
        // Other providers selling the same models don't count toward the subscriptions.
        for provider in ["openrouter", "github-copilot", "amazon-bedrock", "ollama", "google"] {
            #expect(AIUsageModel.family(provider: provider, model: "claude-opus-5") == nil)
            #expect(AIUsageModel.family(provider: provider, model: "gpt-5.5") == nil)
        }
        #expect(AIUsageModel.family(provider: nil, model: "claude-opus-5") == .claude)
        #expect(AIUsageModel.family(provider: "", model: "gpt-5.5-codex") == .codex)
        #expect(AIUsageModel.family(provider: nil, model: "gemini-3-pro") == nil)
    }

    @Test func claudeCodeCountsInputOutputAndCacheWrites() {
        let records = AIUsageModel.claudeCodeRecords(data(
            #"{"type":"user","timestamp":"2026-10-01T10:00:00.000Z","message":{"role":"user"}}"#,
            #"{"type":"assistant","timestamp":"2026-10-01T10:00:05.000Z","message":{"id":"msg_1","usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":300,"cache_read_input_tokens":5000}}}"#,
            #"{"type":"assistant","timestamp":"not a date","message":{"id":"msg_2","usage":{"input_tokens":1}}}"#,
            #"{"type":"assistant","timestamp":"2026-10-01T10:00:06Z","message":{"id":"msg_3","usage":{"output_tokens":4}}}"#
        ))
        #expect(records.map(\.id) == ["msg_1", "msg_3"])
        #expect(records.map(\.tokens) == [330, 4])
        #expect(records.first?.family == .claude)
        #expect(records.last?.date == ISO8601DateFormatter().date(from: "2026-10-01T10:00:06Z"))
    }

    @Test func piLogsMapProvidersAndUseResponseIds() {
        let records = AIUsageModel.piRecords(data(
            #"{"type":"message","id":"a1","timestamp":"2026-10-01T10:00:00.000Z","message":{"role":"assistant","provider":"anthropic","model":"claude-sonnet-5","usage":{"input":2,"output":100,"cacheRead":900,"cacheWrite":50},"timestamp":1790848800000,"responseId":"msg_x"}}"#,
            #"{"type":"message","id":"b2","timestamp":"2026-10-01T10:01:00.000Z","message":{"role":"assistant","provider":"openai-codex","model":"gpt-5.5","usage":{"input":7,"output":3,"cacheRead":0,"cacheWrite":0}}}"#,
            #"{"type":"message","id":"c3","timestamp":"2026-10-01T10:02:00.000Z","message":{"role":"assistant","provider":"google","model":"gemini-3-pro","usage":{"input":1,"output":1}}}"#
        ), file: "/s.jsonl")
        #expect(records.map(\.family) == [.claude, .codex])
        #expect(records.map(\.tokens) == [152, 10])
        #expect(records.map(\.id) == ["msg_x", "/s.jsonl#b2"])
        #expect(records.first?.date == Date(timeIntervalSince1970: 1_790_848_800))
    }

    @Test func codexLeavesOutCachedInputAndRepeatedCounts() {
        let line = #"{"timestamp":"2026-10-01T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":1000},"last_token_usage":{"input_tokens":900,"cached_input_tokens":600,"output_tokens":100}}}}"#
        let records = AIUsageModel.codexRecords(data(
            line, line,
            #"{"timestamp":"2026-10-01T10:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":null}}"#
        ), file: "/r.jsonl")
        #expect(records.map(\.tokens) == [400, 400])
        let totals = AIUsageModel.totals([("Codex", records)], now: Date(timeIntervalSince1970: 1_790_850_000))
        #expect(totals[.codex]?.weekly == 400)
    }

    @Test func codexForksCopyingEventsAreCountedOnce() {
        func line(_ time: String, total: Int, output: Int) -> String {
            #"{"timestamp":"2026-10-01T10:00:\#(time).000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":900,"output_tokens":\#(total - 900),"total_tokens":\#(total)},"last_token_usage":{"input_tokens":0,"output_tokens":\#(output)}}}}"#
        }
        let original = AIUsageModel.codexRecords(data(line("00", total: 1000, output: 100)), file: "/a.jsonl")
        // The fork starts with a copy of the original's event, then goes on by itself; the repeat has a new time.
        let fork = AIUsageModel.codexRecords(data(line("00", total: 1000, output: 100), line("05", total: 1000, output: 100),
                                                  line("09", total: 1050, output: 50)), file: "/b.jsonl")
        let totals = AIUsageModel.totals([("Codex", original + fork)], now: Date(timeIntervalSince1970: 1_790_850_000))
        #expect(totals[.codex]?.weekly == 150)
    }

    @Test func openCodeRowsCountReasoningAndCacheWrites() {
        let row = Data(#"{"role":"assistant","providerID":"openai","modelID":"gpt-5.5","tokens":{"input":500,"output":160,"reasoning":40,"cache":{"read":80000,"write":10}},"time":{"created":1790848800000}}"#.utf8)
        let record = AIUsageModel.openCodeRecord(id: "msg_oc", data: row)
        #expect(record == .init(id: "msg_oc", family: .codex, date: Date(timeIntervalSince1970: 1_790_848_800), tokens: 710))
        #expect(AIUsageModel.openCodeRecord(id: "u", data: Data(#"{"role":"user","time":{"created":1}}"#.utf8)) == nil)
    }

    @Test func totalsDeduplicateAcrossToolsAndSplitWindows() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func record(_ id: String?, hoursAgo: Double, _ tokens: Int, _ family: AIUsageModel.Family = .claude) -> AIUsageModel.TokenRecord {
            .init(id: id, family: family, date: now.addingTimeInterval(-hoursAgo * 3600), tokens: tokens)
        }
        let totals = AIUsageModel.totals([
            ("Claude Code", [record("m1", hoursAgo: 1, 100), record("m2", hoursAgo: 30, 50), record("old", hoursAgo: 200, 999)]),
            ("gjc", [record("m1", hoursAgo: 1, 100), record("m3", hoursAgo: 2, 7), record(nil, hoursAgo: 3, 0)]),
            ("omo", [record(nil, hoursAgo: 4, 0), record("m4", hoursAgo: 4, 0)]),
            ("OpenCode", [record("o1", hoursAgo: 6, 20, .codex), record("m4", hoursAgo: 4, 5)]),
        ], now: now)
        // An empty record doesn't use up its id, so the one with tokens still counts.
        #expect(totals[.claude] == .init(session: 112, weekly: 162, tools: ["Claude Code", "gjc", "OpenCode"]))
        #expect(totals[.codex] == .init(session: 0, weekly: 20, tools: ["OpenCode"]))
    }

    @Test func logsAreReadIncrementallyUntilReplaced() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nunsseop-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        var chunks: [String] = []
        func read() throws -> [String] {
            let modified = try #require(url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            return AIUsageModel.records(in: url, modified: modified, since: .distantPast) { data, _ in
                chunks.append(String(decoding: data, as: UTF8.self))
                return data.split(separator: 0x0A).map { .init(id: String(decoding: $0, as: UTF8.self), family: .claude, date: .now, tokens: 1) }
            }.compactMap(\.id)
        }
        func append(_ text: String) throws {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
            try handle.close()
        }
        try Data("a\nb\n".utf8).write(to: url)
        #expect(try read() == ["a", "b"])
        // A line still being written waits until it's finished, and then only the new lines are read.
        try append("c\nd")
        #expect(try read() == ["a", "b", "c"])
        try append("\n")
        #expect(try read() == ["a", "b", "c", "d"])
        #expect(chunks == ["a\nb\n", "c\n", "d\n"])
        // Truncated in place: read again from the start.
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("x\n".utf8))
        try handle.close()
        #expect(try read() == ["x"])
        // Replaced with the same size: read again.
        try Data("y\n".utf8).write(to: url, options: .atomic)
        #expect(try read() == ["y"])
        // Replaced with a longer file whose old end happens to be a line end: still read again, not appended to.
        try Data("q\nr\n".utf8).write(to: url, options: .atomic)
        #expect(try read() == ["q", "r"])
        #expect(chunks.last == "q\nr\n")
    }

    @Test func gjcReportGivesBothWindows() throws {
        let later = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        let json = """
        {"value":{"provider":"anthropic","fetchedAt":1790889000000,"limits":[
          {"scope":{"windowId":"5h"},"window":{"id":"5h","resetsAt":\(later)},"amount":{"used":4,"usedFraction":0.04,"unit":"percent"}},
          {"scope":{"windowId":"7d"},"window":{"id":"7d","resetsAt":\(later)},"amount":{"used":20,"unit":"percent"}}]}}
        """
        let (family, limits) = try #require(AIUsageModel.gjcLimits(Data(json.utf8)))
        #expect(family == .claude)
        #expect(limits.source == "gjc")
        #expect(limits.updatedAt == Date(timeIntervalSince1970: 1_790_889_000))
        #expect(limits.session?.percent == 4)
        #expect(limits.weekly?.percent == 20)
        #expect(AIUsageModel.gjcLimits(Data(#"{"value":{"provider":"google","fetchedAt":1,"limits":[]}}"#.utf8)) == nil)
    }

    @Test func omcAndCodexLimitsCarryTheirTimes() throws {
        let omc = try #require(AIUsageModel.omcLimits(Data(#"{"lastSuccessAt":1790000000000,"data":{"fiveHourPercent":13,"weeklyPercent":3,"weeklyResetsAt":"2020-01-01T00:00:00.000Z"}}"#.utf8)))
        #expect(omc.updatedAt == Date(timeIntervalSince1970: 1_790_000_000))
        #expect(omc.session?.percent == 13)
        #expect(omc.weekly == .init(percent: 0, resetsAt: nil))
        #expect(omc.source == nil)

        let text = #"{"timestamp":"2026-10-01T10:00:00.000Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":10.0},"secondary":{"used_percent":15.0}}}}"#
        let codex = try #require(AIUsageModel.codexLimits(text, modified: .distantPast))
        #expect(codex.session?.percent == 10)
        #expect(codex.weekly?.percent == 15)
        #expect(codex.updatedAt == ISO8601DateFormatter().date(from: "2026-10-01T10:00:00Z"))
    }

    @Test func statusLineSnapshotGivesBothWindows() throws {
        let later = Date().addingTimeInterval(3600).timeIntervalSince1970
        let json = #"{"model":{"id":"x"},"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":\#(Int(later))},"seven_day":{"used_percentage":41,"resets_at":\#(Int(later))}}}"#
        let stamp = Date(timeIntervalSince1970: 1_790_000_000)
        let limits = try #require(AIUsageModel.statusLineLimits(Data(json.utf8), modified: stamp))
        #expect(limits.session?.percent == 23.5)
        #expect(limits.weekly?.percent == 41)
        #expect(limits.session?.resetsAt == Date(timeIntervalSince1970: TimeInterval(Int(later))))
        #expect(limits.updatedAt == stamp)
        #expect(limits.source == "Claude Code")
    }

    @Test func statusLineSnapshotIgnoresWindowsThatHaveReset() throws {
        let later = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
        let json = #"{"rate_limits":{"five_hour":{"used_percentage":90,"resets_at":1738425600},"seven_day":{"used_percentage":10,"resets_at":\#(later)}}}"#
        let limits = try #require(AIUsageModel.statusLineLimits(Data(json.utf8), modified: .now))
        #expect(limits.session == nil)
        #expect(limits.weekly?.percent == 10)

        let onlyWeekly = #"{"rate_limits":{"seven_day":{"used_percentage":5,"resets_at":\#(later)}}}"#
        #expect(AIUsageModel.statusLineLimits(Data(onlyWeekly.utf8), modified: .now)?.session == nil)
        #expect(AIUsageModel.statusLineLimits(Data(#"{"rate_limits":{"five_hour":{"used_percentage":90,"resets_at":1738425600}}}"#.utf8), modified: .now)?.session == nil)
        #expect(AIUsageModel.statusLineLimits(Data(#"{"model":{}}"#.utf8), modified: .now) == nil)
        #expect(AIUsageModel.statusLineLimits(Data("not json".utf8), modified: .now) == nil)
    }
}
