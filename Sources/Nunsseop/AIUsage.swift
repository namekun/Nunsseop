import Foundation
import os
import SQLite3
import SwiftUI

/// Usage of AI coding tools, read from files those tools already keep on this Mac.
/// Limits: Claude's from Anthropic with Claude Code's own sign-in (ClaudeUsageAPI), the status line Nunsseop connects in Claude Code or the oh-my-claudecode HUD cache,
/// Codex's from Codex's session logs, or either from the usage cache gjc keeps, whichever was fetched last. Token totals add up the logs of every tool that used the provider's
/// models: Claude Code, Codex, gjc, omo and OpenCode.
@MainActor
final class AIUsageModel: ObservableObject {
    struct Window: Equatable {
        let percent: Double
        let resetsAt: Date?
    }

    /// A weekly limit of its own for one model, on top of the weekly limit for all of them.
    struct ModelWindow: Equatable {
        let name: String
        let window: Window
    }

    struct Provider: Identifiable, Equatable {
        let id: String
        let name: String
        var session: Window?
        var weekly: Window?
        var models: [ModelWindow] = []
        /// The subscription the limits belong to, such as "Max".
        var plan: String?
        /// Where asking Anthropic stands, for Claude only.
        var anthropic: ClaudeUsageAPI.Status?
        var sessionTokens: Int?
        var weeklyTokens: Int?
        var updatedAt: Date?
        /// The tool the limits were read from, when it isn't the provider's own.
        var limitsSource: String?
        /// The tools whose logs make up the token totals.
        var tools: [String] = []
    }

    /// Subscription limits are per account, so every tool's usage of a provider's models counts toward one of these.
    enum Family: String, CaseIterable, Sendable {
        case claude, codex

        var name: String { self == .claude ? "Claude" : "Codex" }
    }

    struct Limits: Equatable {
        var session: Window?
        var weekly: Window?
        var models: [ModelWindow] = []
        var plan: String?
        var updatedAt: Date
        var source: String?
    }

    struct TokenRecord: Equatable, Sendable {
        /// The message or request id, so the same response logged twice is counted once.
        let id: String?
        let family: Family
        let date: Date
        let tokens: Int
    }

    struct Totals: Equatable {
        var session = 0
        var weekly = 0
        var tools: [String] = []
    }

    @Published private(set) var providers: [Provider] = []
    @Published private(set) var loading = false
    /// Adding up the logs, which the token totals wait for.
    @Published private(set) var countingTokens = false
    /// A token refresh asked for while another refresh ran, which runs as soon as that one is done.
    private var tokensPending = false
    /// Likewise for limits alone, such as when Anthropic answers during a refresh.
    private var limitsPending = false

    /// Without `includeTokens` only the limits are read, which is cheap; the token totals from the last refresh are kept.
    func refresh(includeTokens: Bool = true) {
        guard !loading else {
            if includeTokens { tokensPending = true } else { limitsPending = true }
            return
        }
        loading = true
        Task.detached(priority: .utility) {
            // Anthropic isn't waited for: the card shows at once, and refreshes again when it answers.
            let limits = Self.limits { Task { @MainActor [weak self] in self?.refresh(includeTokens: false) } }
            let anthropic = ClaudeUsageAPI.status
            // Adding up the logs takes a while, so the limits (or where they will go) show first.
            if includeTokens {
                await MainActor.run {
                    self.countingTokens = true
                    self.publish(limits: limits, anthropic: anthropic, totals: nil)
                }
            }
            let totals = includeTokens ? Self.tokenTotals() : nil
            // Read again: Anthropic may have answered or given up while the logs were added up.
            let settled = ClaudeUsageAPI.status
            await MainActor.run {
                self.publish(limits: limits, anthropic: settled, totals: totals)
                self.countingTokens = false
                self.loading = false
                if self.tokensPending {
                    self.tokensPending = false
                    self.limitsPending = false
                    self.refresh(includeTokens: true)
                } else if self.limitsPending {
                    self.limitsPending = false
                    self.refresh(includeTokens: false)
                }
            }
        }
    }

    /// Without `totals` the token totals from the last refresh are kept.
    private func publish(limits: [Family: Limits], anthropic: ClaudeUsageAPI.Status, totals: [Family: Totals]?) {
        providers = Family.allCases.compactMap { family in
            var provider = Provider(id: family.rawValue, name: family.name)
            if family == .claude { provider.anthropic = anthropic }
            if let limits = limits[family] {
                provider.session = limits.session
                provider.weekly = limits.weekly
                provider.models = limits.models
                provider.plan = limits.plan
                provider.updatedAt = limits.updatedAt
                provider.limitsSource = limits.source
            }
            if let totals {
                provider.sessionTokens = totals[family]?.session
                provider.weeklyTokens = totals[family]?.weekly
                provider.tools = totals[family]?.tools ?? []
            } else if let old = providers.first(where: { $0.id == provider.id }) {
                provider.sessionTokens = old.sessionTokens
                provider.weeklyTokens = old.weeklyTokens
                provider.tools = old.tools
            }
            let waiting = provider.anthropic == .waiting
            return provider.session == nil && provider.weekly == nil && provider.weeklyTokens == nil && !waiting ? nil : provider
        }
    }

    /// A window whose reset time has passed has started over.
    nonisolated private static func window(percent: Double?, resetsAt: Date?) -> Window? {
        guard let percent else { return nil }
        if let resetsAt, resetsAt < .now { return Window(percent: 0, resetsAt: nil) }
        return Window(percent: percent, resetsAt: resetsAt)
    }

    nonisolated private static let home = URL(fileURLWithPath: NSHomeDirectory())

    nonisolated private static func files(under root: URL, modifiedSince date: Date, where match: (URL) -> Bool) -> [(URL, Date)] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return [] }
        var result: [(URL, Date)] = []
        for case let url as URL in enumerator where match(url) {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if modified >= date { result.append((url, modified)) }
        }
        return result
    }

    /// Parses ISO 8601 times with or without fractional seconds.
    nonisolated private static func isoParser() -> (String) -> Date? {
        let fractional = ISO8601DateFormatter(), whole = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return { fractional.date(from: $0) ?? whole.date(from: $0) }
    }

    /// Which subscription a response counts toward: the provider decides, since the same models are also sold by others
    /// (OpenRouter, Bedrock, Copilot…) whose usage doesn't count; the model name only when no provider is given.
    nonisolated static func family(provider: String?, model: String?) -> Family? {
        if let provider = provider?.lowercased(), !provider.isEmpty {
            if provider.hasPrefix("anthropic") { return .claude }
            if provider.hasPrefix("openai") || provider == "codex" || provider.hasPrefix("chatgpt") { return .codex }
            return nil
        }
        let model = model?.lowercased() ?? ""
        if model.contains("claude") { return .claude }
        if model.contains("gpt") || model.contains("codex") { return .codex }
        return nil
    }

    // MARK: Limits

    /// Each provider's limits from whichever source fetched them last.
    nonisolated private static func limits(answered: @escaping @Sendable () -> Void) -> [Family: Limits] {
        let anthropic = ClaudeUsageAPI.latest(answered: answered)
        var result: [Family: Limits] = [:]
        func offer(_ family: Family, _ limits: Limits?) {
            guard let limits, (limits.session ?? limits.weekly) != nil else { return }
            if let current = result[family], current.updatedAt >= limits.updatedAt { return }
            result[family] = limits
        }
        offer(.claude, (try? Data(contentsOf: home.appendingPathComponent(".claude/plugins/oh-my-claudecode/.usage-cache-anthropic.json"))).flatMap(omcLimits))
        offer(.claude, anthropic)
        offer(.claude, statusLineLimits())
        offer(.codex, codexLimits())
        let gjc = home.appendingPathComponent(".gjc/agent/agent.db").path
        // Only the usage cache is read; this database also holds gjc's credentials, which are never touched.
        for row in query(gjc, "SELECT value FROM cache WHERE key GLOB 'usage_cache:report:*'") {
            if let (family, limits) = gjcLimits(Data(row[0].utf8)) { offer(family, limits) }
        }
        return result
    }

    /// The oh-my-claudecode HUD's cache of Claude's limits.
    nonisolated static func omcLimits(_ data: Data) -> Limits? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = json["data"] as? [String: Any],
              let stamp = json["lastSuccessAt"] as? Double ?? json["timestamp"] as? Double else { return nil }
        let iso = isoParser()
        func date(_ key: String) -> Date? { (usage[key] as? String).flatMap { iso($0) } }
        return Limits(session: window(percent: usage["fiveHourPercent"] as? Double, resetsAt: date("fiveHourResetsAt")),
                      weekly: window(percent: usage["weeklyPercent"] as? Double, resetsAt: date("weeklyResetsAt")),
                      updatedAt: Date(timeIntervalSince1970: stamp / 1000))
    }

    /// The rate limits Claude Code last passed to its status line, kept by the script Nunsseop connects there.
    nonisolated private static func statusLineLimits() -> Limits? {
        let url = ClaudeStatusLine.Paths.live.snapshot
        guard let data = try? Data(contentsOf: url),
              let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return nil }
        return statusLineLimits(data, modified: modified)
    }

    /// Claude Code leaves out a window once its reset time has passed, and a copy kept from before that is dropped too.
    nonisolated static func statusLineLimits(_ data: Data, modified: Date) -> Limits? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = json["rate_limits"] as? [String: Any] else { return nil }
        func parse(_ key: String) -> Window? {
            guard let entry = limits[key] as? [String: Any], let percent = entry["used_percentage"] as? Double else { return nil }
            let reset = (entry["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
            if let reset, reset < .now { return nil }
            return Window(percent: percent, resetsAt: reset)
        }
        return Limits(session: parse("five_hour"), weekly: parse("seven_day"), updatedAt: modified, source: "Claude Code")
    }

    /// One provider's report from gjc's usage cache: 5-hour and 7-day windows with the time it was fetched.
    nonisolated static func gjcLimits(_ data: Data) -> (Family, Limits)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let report = json["value"] as? [String: Any] ?? json
        guard let family = family(provider: report["provider"] as? String, model: nil),
              let fetched = report["fetchedAt"] as? Double,
              let entries = report["limits"] as? [[String: Any]] else { return nil }
        var limits = Limits(updatedAt: Date(timeIntervalSince1970: fetched / 1000), source: "gjc")
        for entry in entries {
            let span = entry["window"] as? [String: Any], amount = entry["amount"] as? [String: Any]
            let percent = (amount?["usedFraction"] as? Double).map { $0 * 100 }
                ?? (amount?["unit"] as? String == "percent" ? amount?["used"] as? Double : nil)
            let reset = (span?["resetsAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
            switch span?["id"] as? String ?? (entry["scope"] as? [String: Any])?["windowId"] as? String {
            case "5h" where limits.session == nil: limits.session = window(percent: percent, resetsAt: reset)
            case "7d" where limits.weekly == nil: limits.weekly = window(percent: percent, resetsAt: reset)
            default: break
            }
        }
        return (family, limits)
    }

    /// Codex files each session's log under the YYYY/MM/DD it started, so only the latest few days' folders are searched
    /// for the newest log, rather than every session ever.
    nonisolated private static func codexLimits() -> Limits? {
        var days: [URL] = []
        func newest(in folder: URL, depth: Int) {
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { Int($0) != nil }
            for name in names.sorted(by: >) where days.count < 8 {
                let child = folder.appendingPathComponent(name)
                if depth == 2 { days.append(child) } else { newest(in: child, depth: depth + 1) }
            }
        }
        newest(in: home.appendingPathComponent(".codex/sessions"), depth: 0)
        let logs = days.flatMap {
            files(under: $0, modifiedSince: .distantPast) { $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("rollout-") }
        }
        guard let (file, modified) = logs.max(by: { $0.1 < $1.1 }), let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 1_000_000 ? size - 1_000_000 : 0)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }
        return codexLimits(text, modified: modified)
    }

    /// The last limits a Codex session log recorded, dated by that line (or the file, if the line has no time).
    nonisolated static func codexLimits(_ text: String, modified: Date) -> Limits? {
        for line in text.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let limits = (json["payload"] as? [String: Any])?["rate_limits"] as? [String: Any] else { continue }
            func parse(_ key: String) -> Window? {
                guard let entry = limits[key] as? [String: Any] else { return nil }
                let reset = (entry["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
                return window(percent: entry["used_percent"] as? Double, resetsAt: reset)
            }
            let stamp = (json["timestamp"] as? String).flatMap(isoParser())
            return Limits(session: parse("primary"), weekly: parse("secondary"), updatedAt: stamp ?? modified)
        }
        return nil
    }

    // MARK: Tokens

    /// Tokens used in the last five hours and seven days per provider, from every tool's logs.
    nonisolated private static func tokenTotals() -> [Family: Totals] {
        let now = Date()
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        var scanned = Set<String>()
        func scan(_ roots: [String], where match: (URL) -> Bool = { _ in true }, parse: (Data, String) -> [TokenRecord]) -> [TokenRecord] {
            roots.flatMap { files(under: home.appendingPathComponent($0), modifiedSince: weekAgo) { $0.pathExtension == "jsonl" && match($0) } }
                .sorted { $0.0.path < $1.0.path }
                .flatMap { url, modified in
                    scanned.insert(url.path)
                    return records(in: url, modified: modified, since: weekAgo, parse: parse)
                }
        }
        let sources: [(tool: String, records: [TokenRecord])] = [
            ("Claude Code", scan([".claude/projects"], parse: claudeCodeRecords)),
            ("Codex", scan([".codex/sessions"], where: { $0.lastPathComponent.hasPrefix("rollout-") }, parse: codexRecords)),
            ("gjc", scan([".gjc/agent/sessions"], parse: piRecords)),
            ("omo", scan([".omo/agent/sessions", ".omo/memory"], parse: piRecords)),
            ("OpenCode", openCodeRecords(since: weekAgo, scanned: &scanned)),
        ]
        // Files that left the 7-day window or were deleted are forgotten.
        let current = scanned
        parsed.withLock { $0 = $0.filter { current.contains($0.key) } }
        return totals(sources, now: now)
    }

    /// What was read from one file: enough to tell whether it changed, how far it was read, and its records.
    private struct ParsedFile: Sendable {
        let size: Int
        let modified: Date
        /// The file's inode, which changes when a log is replaced rather than appended to.
        var inode = 0
        let offset: Int
        let records: [TokenRecord]
    }

    /// Parse results per path, so a refresh only reads files that changed, and of a log that grew, only the new lines.
    nonisolated private static let parsed = OSAllocatedUnfairLock<[String: ParsedFile]>(initialState: [:])

    nonisolated static func records(in url: URL, modified: Date, since: Date, parse: (Data, String) -> [TokenRecord]) -> [TokenRecord] {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = attributes?[.size] as? Int ?? 0, inode = attributes?[.systemFileNumber] as? Int ?? 0
        let cached = parsed.withLock { $0[url.path] }.flatMap { $0.inode == inode ? $0 : nil }
        if let cached, cached.size == size, cached.modified == modified { return cached.records }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        // The logs are append-only: if the file grew and the old end is still the end of a line, read on from there.
        var start = 0, kept: [TokenRecord] = []
        if let cached, cached.offset > 0, size > cached.offset {
            try? handle.seek(toOffset: UInt64(cached.offset - 1))
            if (try? handle.read(upToCount: 1)) == Data([0x0A]) {
                start = cached.offset
                kept = cached.records
            }
        }
        if start == 0 { try? handle.seek(toOffset: 0) }
        let data = (try? handle.readToEnd()) ?? Data()
        // A line still being written is left for the next refresh.
        let end = data.lastIndex(of: 0x0A).map { $0 - data.startIndex + 1 } ?? 0
        let records = (kept + parse(data.prefix(end), url.path)).filter { $0.date >= since }
        let file = ParsedFile(size: size, modified: modified, inode: inode, offset: start + end, records: records)
        parsed.withLock { $0[url.path] = file }
        return records
    }

    /// The JSON objects on the lines of a log that contain `marker`, which skips most lines without decoding them.
    nonisolated private static func objects(in data: Data, containing marker: String) -> [[String: Any]] {
        let marker = Data(marker.utf8)
        return data.split(separator: 0x0A).compactMap { line in
            guard line.range(of: marker) != nil else { return nil }
            return try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
        }
    }

    /// Claude Code's conversation logs: input, output and cache-write tokens of each response.
    nonisolated static func claudeCodeRecords(_ data: Data, file: String = "") -> [TokenRecord] {
        let iso = isoParser()
        return objects(in: data, containing: "\"type\":\"assistant\"").compactMap { json in
            guard let date = (json["timestamp"] as? String).flatMap({ iso($0) }),
                  let message = json["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { return nil }
            let tokens = ["input_tokens", "output_tokens", "cache_creation_input_tokens"].reduce(0) { $0 + (usage[$1] as? Int ?? 0) }
            return TokenRecord(id: message["id"] as? String, family: .claude, date: date, tokens: tokens)
        }
    }

    /// Codex's session logs. Input counts cached tokens, which are left out as they are for Claude.
    nonisolated static func codexRecords(_ data: Data, file: String = "") -> [TokenRecord] {
        let iso = isoParser()
        return objects(in: data, containing: "\"token_count\"").compactMap { json in
            guard let info = (json["payload"] as? [String: Any])?["info"] as? [String: Any],
                  let last = info["last_token_usage"] as? [String: Any],
                  let date = (json["timestamp"] as? String).flatMap({ iso($0) }) else { return nil }
            let input = (last["input_tokens"] as? Int ?? 0) - (last["cached_input_tokens"] as? Int ?? 0)
            let tokens = max(0, input) + (last["output_tokens"] as? Int ?? 0)
            // Codex logs the same count again when only the limits changed, and a forked session's log starts with a copy
            // of the original's events; the running totals tell them apart without depending on the file.
            let total = (info["total_token_usage"] as? [String: Any]).map { usage in
                ["input_tokens", "cached_input_tokens", "output_tokens", "reasoning_output_tokens", "total_tokens"]
                    .map { String(usage[$0] as? Int ?? 0) }.joined(separator: "/")
            }
            return TokenRecord(id: total.map { "codex#\($0)" }, family: .codex, date: date, tokens: tokens)
        }
    }

    /// Session logs of gjc and omo, which share a format: each response with its provider, model and usage.
    nonisolated static func piRecords(_ data: Data, file: String = "") -> [TokenRecord] {
        let iso = isoParser()
        return objects(in: data, containing: "\"role\":\"assistant\"").compactMap { json in
            guard let message = json["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let family = family(provider: message["provider"] as? String, model: message["model"] as? String),
                  let date = (message["timestamp"] as? Double).map({ Date(timeIntervalSince1970: $0 / 1000) })
                      ?? (json["timestamp"] as? String).flatMap({ iso($0) }) else { return nil }
            let tokens = ["input", "output", "cacheWrite"].reduce(0) { $0 + (usage[$1] as? Int ?? 0) }
            let id = message["responseId"] as? String ?? (json["id"] as? String).map { "\(file)#\($0)" }
            return TokenRecord(id: id, family: family, date: date, tokens: tokens)
        }
    }

    /// One row of OpenCode's message table.
    nonisolated static func openCodeRecord(id: String, data: Data) -> TokenRecord? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["role"] as? String == "assistant",
              let usage = json["tokens"] as? [String: Any],
              let family = family(provider: json["providerID"] as? String, model: json["modelID"] as? String),
              let created = (json["time"] as? [String: Any])?["created"] as? Double else { return nil }
        let tokens = ["input", "output", "reasoning"].reduce(0) { $0 + (usage[$1] as? Int ?? 0) }
            + ((usage["cache"] as? [String: Any])?["write"] as? Int ?? 0)
        return TokenRecord(id: id, family: family, date: Date(timeIntervalSince1970: created / 1000), tokens: tokens)
    }

    /// OpenCode keeps its messages in SQLite, which is only queried again when the database or its log changed.
    nonisolated private static func openCodeRecords(since: Date, scanned: inout Set<String>) -> [TokenRecord] {
        let path = home.appendingPathComponent(".local/share/opencode/opencode.db").path
        let stamps = [path, path + "-wal"].compactMap { try? FileManager.default.attributesOfItem(atPath: $0) }
        guard let modified = stamps.compactMap({ $0[.modificationDate] as? Date }).max(), modified >= since else { return [] }
        let size = stamps.reduce(0) { $0 + ($1[.size] as? Int ?? 0) }
        scanned.insert(path)
        if let cached = parsed.withLock({ $0[path] }), cached.size == size, cached.modified == modified { return cached.records }
        let records = query(path, "SELECT id, data FROM message WHERE time_created >= \(Int64(since.timeIntervalSince1970 * 1000))")
            .compactMap { openCodeRecord(id: $0[0], data: Data($0[1].utf8)) }
        let file = ParsedFile(size: size, modified: modified, offset: 0, records: records)
        parsed.withLock { $0[path] = file }
        return records
    }

    /// Sums the records per provider, counting each response once even if several tools or files logged it.
    nonisolated static func totals(_ sources: [(tool: String, records: [TokenRecord])], now: Date = .now) -> [Family: Totals] {
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let sessionStart = now.addingTimeInterval(-5 * 3_600)
        var seen = Set<String>()
        var result: [Family: Totals] = [:]
        for (tool, records) in sources {
            for record in records where record.date >= weekAgo {
                guard record.tokens > 0 else { continue }
                if let id = record.id, !seen.insert(id).inserted { continue }
                var totals = result[record.family] ?? Totals()
                totals.weekly += record.tokens
                if record.date >= sessionStart { totals.session += record.tokens }
                if !totals.tools.contains(tool) { totals.tools.append(tool) }
                result[record.family] = totals
            }
        }
        return result
    }

    /// Text columns of a read-only query, or nothing if the database can't be opened.
    nonisolated private static func query(_ path: String, _ sql: String) -> [[String]] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        sqlite3_busy_timeout(db, 500)
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        var rows: [[String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append((0..<sqlite3_column_count(statement)).map { column in
                sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
            })
        }
        return rows
    }
}

struct AIUsageTab: View {
    @ObservedObject var usage: AIUsageModel
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 10) {
            if !settings.claudeLimitsAsked && !settings.claudeLimitsFromAnthropic {
                LiveLimitsPrompt(settings: settings) { usage.refresh(includeTokens: false) }
            }
            if usage.providers.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 22)).foregroundStyle(.white.opacity(0.4))
                    Text(usage.loading ? String(localized: "Loading…") : String(localized: "No AI usage found"))
                        .font(.system(size: 13, weight: .semibold))
                    if !usage.loading {
                        Text("Usage appears here once you have used Claude Code or Codex on this Mac.")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            ForEach(usage.providers) { provider in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(provider.name).font(.system(size: 13, weight: .semibold))
                        if let plan = provider.plan {
                            Text(verbatim: plan.uppercased())
                                .font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(.white.opacity(0.12)))
                        }
                        // The tools whose logs are counted, e.g. "Claude Code · gjc".
                        Text(verbatim: provider.tools.joined(separator: " · "))
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                        Spacer(minLength: 0)
                        if let updated = provider.updatedAt {
                            let text = String(localized: "Updated \(updated.formatted(.relative(presentation: .named)))")
                            Text(verbatim: provider.limitsSource.map { "\(text) · \($0)" } ?? text)
                                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                                .layoutPriority(1)
                        }
                    }
                    UsageBars(provider: provider)
                    if let session = provider.sessionTokens, let weekly = provider.weeklyTokens {
                        HStack(spacing: 12) {
                            TokenRow(title: String(localized: "Last 5 hours"), tokens: session)
                            TokenRow(title: String(localized: "Last 7 days"), tokens: weekly)
                        }
                    } else if usage.countingTokens {
                        HStack(spacing: 12) {
                            TokenRowSkeleton()
                            TokenRowSkeleton()
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .surface(RoundedRectangle(cornerRadius: 14))
            }
        }
        .foregroundStyle(.white)
        .task {
            // Limits are cheap to read, so they refresh often; the token totals scan logs and refresh every 2 minutes.
            var tick = 0
            while !Task.isCancelled {
                usage.refresh(includeTokens: tick % 6 == 0)
                tick += 1
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }
}

/// Asked once: whether to read Claude Code's sign-in and ask Anthropic for the limits. Either answer is final here;
/// Settings › Services can change it later.
private struct LiveLimitsPrompt: View {
    @ObservedObject var settings: AppSettings
    let turnedOn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Live Claude limits?").font(.system(size: 13, weight: .semibold))
            Text("Nunsseop can read the sign-in Claude Code keeps in the Keychain and ask Anthropic directly for your 5-hour and weekly limits, about once an hour, so they update without Claude Code running.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Button("Turn On") {
                    settings.claudeLimitsFromAnthropic = true
                    settings.claudeLimitsAsked = true
                    turnedOn()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color.accentColor.opacity(0.8)))
                Button("No Thanks") { settings.claudeLimitsAsked = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(.white.opacity(0.15)))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: 230, maxHeight: .infinity, alignment: .topLeading)
        .surface(RoundedRectangle(cornerRadius: 14))
    }
}

private struct TokenRow: View {
    let title: String
    let tokens: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            Text("\(tokens.formatted(.number.notation(.compactName))) tokens")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The 5-hour and weekly limits, then each model's weekly limit. Past two bars they share rows two by two,
/// so a model's limit doesn't push the token totals out of the card.
private struct UsageBars: View {
    let provider: AIUsageModel.Provider

    private var bars: [(title: String, window: AIUsageModel.Window)] {
        var bars: [(title: String, window: AIUsageModel.Window)] = []
        if let window = provider.session { bars.append((String(localized: "5-hour"), window)) }
        if let window = provider.weekly {
            bars.append((provider.models.isEmpty ? String(localized: "Weekly") : String(localized: "Weekly · all models"), window))
        }
        bars += provider.models.map { (String(localized: "Weekly · \($0.name)"), $0.window) }
        return bars
    }

    var body: some View {
        let bars = bars
        if bars.isEmpty && provider.anthropic == .waiting {
            UsageBarSkeleton()
            UsageBarSkeleton()
        } else if bars.count > 2 {
            Grid(horizontalSpacing: 16, verticalSpacing: 6) {
                ForEach(Array(stride(from: 0, to: bars.count, by: 2)), id: \.self) { start in
                    GridRow {
                        UsageBar(title: bars[start].title, window: bars[start].window)
                        if start + 1 < bars.count {
                            UsageBar(title: bars[start + 1].title, window: bars[start + 1].window)
                        } else {
                            Color.clear.gridCellUnsizedAxes(.vertical)
                        }
                    }
                }
            }
        } else {
            ForEach(bars, id: \.title) { bar in UsageBar(title: bar.title, window: bar.window) }
        }
        if provider.anthropic == .signedOut {
            Text("Sign in to Claude Code again to update the limits.")
                .font(.system(size: 10)).foregroundStyle(.orange.opacity(0.9)).lineLimit(1)
        }
    }
}

/// Where a limit bar goes while a request to Anthropic is out, laid out like `UsageBar`.
private struct UsageBarSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Capsule().frame(width: 96, height: 9)
                Spacer()
                Capsule().frame(width: 26, height: 9)
            }
            .frame(height: 13)
            Capsule().frame(height: 6)
        }
        .modifier(SkeletonPulse())
    }
}

/// Where a token total goes while the logs are being added up, laid out like `TokenRow`.
private struct TokenRowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Capsule().frame(width: 64, height: 8).frame(height: 12)
            Capsule().frame(width: 88, height: 10).frame(height: 15)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SkeletonPulse())
    }
}

/// Gray shapes that fade in and out while what they stand for loads.
private struct SkeletonPulse: ViewModifier {
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white.opacity(dim ? 0.06 : 0.14))
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: dim)
            .onAppear { dim = true }
            .accessibilityLabel(Text("Loading…"))
    }
}

private struct UsageBar: View {
    let title: String
    let window: AIUsageModel.Window

    private var tint: Color {
        window.percent >= 90 ? .red : window.percent >= 70 ? .orange : .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(.system(size: 11, weight: .medium))
                if let reset = window.resetsAt {
                    Text("Resets \(reset, format: .relative(presentation: .named))")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                }
                Spacer()
                Text("\(Int(window.percent.rounded()))%").font(.system(size: 11, weight: .semibold).monospacedDigit())
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(tint).frame(width: proxy.size.width * min(1, max(0, window.percent / 100)))
                }
            }
            .frame(height: 6)
        }
    }
}
