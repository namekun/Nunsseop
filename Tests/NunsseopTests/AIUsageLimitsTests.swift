import Foundation
import SQLite3
import Testing
@testable import Nunsseop

struct AIUsageLimitsTests {
    private typealias Limits = AIUsageModel.Limits
    private typealias Window = AIUsageModel.Window

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nunsseop-aiusage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // MARK: Codex log tail

    private let codexLine = #"{"timestamp":"2026-10-01T10:00:00.000Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":10.0},"secondary":{"used_percent":15.0}}}}"#

    /// A log whose last line holds the limits, after a line of Korean text that a cut can land inside.
    private func koreanLog(in folder: URL) throws -> (file: URL, lastLineBytes: Int) {
        let file = folder.appendingPathComponent("rollout-test.jsonl")
        let text = String(repeating: "한글", count: 20) + "\n" + codexLine + "\n"
        try Data(text.utf8).write(to: file)
        return (file, codexLine.utf8.count + 1)
    }

    @Test func codexLimitsSurviveATailCutInsideAMultiByteCharacter() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (file, lastLine) = try koreanLog(in: folder)
        // Counting back from the line's start the cut falls inside the last 3-byte character (1 and 2 bytes in), exactly
        // after it, then inside the one before.
        for extra in 2...5 {
            let text = try #require(AIUsageModel.tailText(of: file, maxBytes: lastLine + extra), "cut \(extra) bytes into the line before")
            let limits = try #require(AIUsageModel.codexLimits(text, modified: .distantPast))
            #expect(limits.session?.percent == 10)
            #expect(limits.weekly?.percent == 15)
        }
    }

    @Test func tailTextReadsTheWholeFileWhenItIsShorterThanTheLimit() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("log.jsonl")
        try Data("a\nb\n".utf8).write(to: file)
        #expect(AIUsageModel.tailText(of: file, maxBytes: 1_000_000) == "a\nb\n")
        #expect(AIUsageModel.tailText(of: file, maxBytes: 2) == "b\n")
        #expect(AIUsageModel.tailText(of: folder.appendingPathComponent("missing.jsonl"), maxBytes: 10) == nil)
    }

    // MARK: Codex lines

    @Test func codexLimitsSkipsUnusableLinesAndStaleWindows() throws {
        let later = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
        let valid = #"{"timestamp":"2026-10-01T10:00:00.000Z","payload":{"rate_limits":{"primary":{"used_percent":10.0,"resets_at":\#(later)},"secondary":{"used_percent":15.0,"resets_at":\#(later)}}}}"#
        let cutFirstLine = #"ted_tokens":5},"rate_limits":{"primary":{"used_percent":99"#
        let nullLimits = #"{"timestamp":"2026-10-01T10:05:00.000Z","payload":{"rate_limits":null}}"#
        let notAnObject = #"{"timestamp":"2026-10-01T10:06:00.000Z","payload":{"rate_limits":"none"}}"#
        let text = [cutFirstLine, valid, nullLimits, notAnObject].joined(separator: "\n")
        let limits = try #require(AIUsageModel.codexLimits(text, modified: .distantPast))
        #expect(limits.session == Window(percent: 10, resetsAt: Date(timeIntervalSince1970: TimeInterval(later))))
        #expect(limits.weekly == Window(percent: 15, resetsAt: Date(timeIntervalSince1970: TimeInterval(later))))
        #expect(limits.updatedAt == ISO8601DateFormatter().date(from: "2026-10-01T10:00:00Z"))
        // Nothing but unusable lines.
        #expect(AIUsageModel.codexLimits([cutFirstLine, nullLimits].joined(separator: "\n"), modified: .now) == nil)
    }

    @Test func codexWindowsWhoseResetPassedHaveStartedOver() throws {
        let past = Int(Date().addingTimeInterval(-1).timeIntervalSince1970)
        let line = #"{"payload":{"rate_limits":{"primary":{"used_percent":100.0,"resets_at":\#(past)},"secondary":{"used_percent":40.0}}}}"#
        let limits = try #require(AIUsageModel.codexLimits(line, modified: Date(timeIntervalSince1970: 1_790_000_000)))
        #expect(limits.session == Window(percent: 0, resetsAt: nil))
        #expect(limits.weekly == Window(percent: 40, resetsAt: nil))
        // Without a time on the line the file's own is used.
        #expect(limits.updatedAt == Date(timeIntervalSince1970: 1_790_000_000))
    }

    @Test func codexLimitsNeedARateLimitsLine() {
        #expect(AIUsageModel.codexLimits("", modified: .now) == nil)
        #expect(AIUsageModel.codexLimits(#"{"payload":{"type":"agent_message"}}"#, modified: .now) == nil)
    }

    // MARK: gjc

    private func gjc(provider: String = "anthropic", fetchedAt: String = #""fetchedAt":1790889000000,"#, _ limits: String) -> Data {
        Data(#"{"value":{"provider":"\#(provider)",\#(fetchedAt)"limits":[\#(limits)]}}"#.utf8)
    }

    private func entry(id: String, amount: String, resetsAt: Double? = nil) -> String {
        let reset = resetsAt.map { #","resetsAt":\#(Int64($0))"# } ?? ""
        return #"{"scope":{"windowId":"\#(id)"},"window":{"id":"\#(id)"\#(reset)},"amount":\#(amount)}"#
    }

    private var inAnHour: Double { Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000 }

    @Test func gjcPercentComesOnlyFromAFractionOrAPercentUnit() throws {
        // Tokens are not a percentage, so the window is left out rather than shown as 4000%.
        let tokens = try #require(AIUsageModel.gjcLimits(gjc(entry(id: "5h", amount: #"{"used":4000,"unit":"tokens"}"#))))
        #expect(tokens.1.session == nil)
        // A fraction of 0 is a value, not a missing one, and wins over `used`.
        let zero = try #require(AIUsageModel.gjcLimits(gjc(entry(id: "5h", amount: #"{"used":9,"usedFraction":0,"unit":"percent"}"#))))
        #expect(zero.1.session == Window(percent: 0, resetsAt: nil))
        let half = try #require(AIUsageModel.gjcLimits(gjc(entry(id: "5h", amount: #"{"used":3,"usedFraction":0.5,"unit":"tokens"}"#))))
        #expect(half.1.session?.percent == 50)
        let used = try #require(AIUsageModel.gjcLimits(gjc(entry(id: "7d", amount: #"{"used":20,"unit":"percent"}"#))))
        #expect(used.1.weekly?.percent == 20)
    }

    @Test func gjcFirstEntryOfAWindowWins() throws {
        let (_, limits) = try #require(AIUsageModel.gjcLimits(gjc([
            entry(id: "5h", amount: #"{"usedFraction":0.25}"#),
            entry(id: "5h", amount: #"{"usedFraction":0.75}"#),
            entry(id: "7d", amount: #"{"usedFraction":0.5}"#),
            entry(id: "7d", amount: #"{"usedFraction":0.1}"#),
            entry(id: "30d", amount: #"{"usedFraction":0.9}"#),
        ].joined(separator: ","))))
        #expect(limits.session?.percent == 25)
        #expect(limits.weekly?.percent == 50)
    }

    @Test func gjcWindowIdFallsBackToTheScope() throws {
        let json = #"{"limits":[{"scope":{"windowId":"7d"},"amount":{"usedFraction":0.3}}],"provider":"anthropic","fetchedAt":1790889000000}"#
        let (family, limits) = try #require(AIUsageModel.gjcLimits(Data(json.utf8)))
        #expect(family == .claude)
        #expect(limits.weekly?.percent == 30)
        #expect(limits.session == nil)
    }

    @Test func gjcWindowsWhoseResetPassedHaveStartedOver() throws {
        let past = Date().addingTimeInterval(-0.001).timeIntervalSince1970 * 1000
        let (_, limits) = try #require(AIUsageModel.gjcLimits(gjc([
            entry(id: "5h", amount: #"{"usedFraction":0.95}"#, resetsAt: past),
            entry(id: "7d", amount: #"{"usedFraction":0.95}"#, resetsAt: inAnHour),
        ].joined(separator: ","))))
        #expect(limits.session == Window(percent: 0, resetsAt: nil))
        #expect(limits.weekly?.percent == 95)
    }

    @Test func gjcProviderAndRequiredFields() throws {
        let one = entry(id: "5h", amount: #"{"usedFraction":0.5}"#)
        #expect(try #require(AIUsageModel.gjcLimits(gjc(provider: "openai-codex", one))).0 == .codex)
        #expect(AIUsageModel.gjcLimits(gjc(provider: "openrouter", one)) == nil)
        #expect(AIUsageModel.gjcLimits(gjc(fetchedAt: "", one)) == nil)
        #expect(AIUsageModel.gjcLimits(Data(#"{"value":{"provider":"anthropic","fetchedAt":1}}"#.utf8)) == nil)
        #expect(AIUsageModel.gjcLimits(Data("not json".utf8)) == nil)
    }

    // MARK: Choosing between sources

    @Test func newestLimitsWinAndEmptyOnesAreIgnored() {
        func limits(_ percent: Double, at seconds: TimeInterval, source: String? = nil, plan: String? = nil) -> Limits {
            Limits(session: Window(percent: percent, resetsAt: nil), plan: plan, updatedAt: Date(timeIntervalSince1970: seconds), source: source)
        }
        let omc = limits(1, at: 100), api = limits(2, at: 200, plan: "Max"), statusLine = limits(3, at: 150, source: "Claude Code")
        #expect(AIUsageModel.pick([(.claude, omc), (.claude, api), (.claude, statusLine)])[.claude] == api)
        // Whatever the order they come in.
        #expect(AIUsageModel.pick([(.claude, statusLine), (.claude, api), (.claude, omc)])[.claude] == api)
        // A tie keeps the one offered first.
        #expect(AIUsageModel.pick([(.claude, limits(4, at: 300)), (.claude, limits(5, at: 300))])[.claude]?.session?.percent == 4)
        // Each provider has its own.
        let codex = limits(6, at: 10)
        #expect(AIUsageModel.pick([(.claude, api), (.codex, codex)]) == [.claude: api, .codex: codex])
        // Limits with no window, or none at all, are never kept, however new.
        let empty = Limits(updatedAt: Date(timeIntervalSince1970: 999))
        #expect(AIUsageModel.pick([(.claude, omc), (.claude, empty), (.claude, nil)])[.claude] == omc)
        #expect(AIUsageModel.pick([(.codex, empty), (.codex, nil)]).isEmpty)
        let weeklyOnly = Limits(weekly: Window(percent: 7, resetsAt: nil), updatedAt: Date(timeIntervalSince1970: 50))
        #expect(AIUsageModel.pick([(.claude, weeklyOnly)])[.claude] == weeklyOnly)
    }

    // MARK: SQLite

    private func makeDatabase(at url: URL) throws {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        try #require(sqlite3_open(url.path, &db) == SQLITE_OK)
        let sql = """
        CREATE TABLE cache (key TEXT, value TEXT);
        INSERT INTO cache VALUES ('usage_cache:report:a', '{"a":1}');
        INSERT INTO cache VALUES ('other:b', 'b');
        CREATE TABLE secrets (name TEXT, token TEXT);
        INSERT INTO secrets VALUES ('gjc', 'hunter2');
        """
        try #require(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
    }

    @Test func queryIsReadOnlyAndTolerant() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = folder.appendingPathComponent("agent.db")
        try makeDatabase(at: database)
        let before = try Data(contentsOf: database)
        let entries = try FileManager.default.contentsOfDirectory(atPath: folder.path)

        #expect(AIUsageModel.query(database.path, "SELECT value FROM cache WHERE key GLOB 'usage_cache:report:*'") == [[#"{"a":1}"#]])
        #expect(AIUsageModel.query(database.path, "SELECT key, value FROM cache ORDER BY key") == [["other:b", "b"], ["usage_cache:report:a", #"{"a":1}"#]])
        // Writes are refused.
        #expect(AIUsageModel.query(database.path, "INSERT INTO cache VALUES ('x', 'y')") == [])
        #expect(AIUsageModel.query(database.path, "DELETE FROM cache") == [])
        #expect(AIUsageModel.query(database.path, "DROP TABLE secrets") == [])
        #expect(AIUsageModel.query(database.path, "SELECT count(*) FROM cache") == [["2"]])
        #expect(AIUsageModel.query(database.path, "SELECT count(*) FROM secrets") == [["1"]])
        // A bad statement, a missing file and a file that isn't a database give nothing.
        #expect(AIUsageModel.query(database.path, "SELEC garbage") == [])
        #expect(AIUsageModel.query(folder.appendingPathComponent("nonexistent.db").path, "SELECT 1") == [])
        let text = folder.appendingPathComponent("not-a-database.db")
        try Data("just some text, nothing like SQLite\n".utf8).write(to: text)
        #expect(AIUsageModel.query(text.path, "SELECT 1") == [])

        #expect(try Data(contentsOf: database) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == (entries + ["not-a-database.db"]).sorted())
    }
}
