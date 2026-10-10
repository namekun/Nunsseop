import Foundation

/// Command-line tools whose notifications Nunsseop can show, each wired up by editing that tool's own config.
/// Every change keeps the tool's other settings, and the JSON and TOML files are backed up first.
enum NotifyIntegration: String, CaseIterable, Identifiable {
    case claudeCode, codex, gemini, openCode

    enum IntegrationError: Error { case unreadableConfig }

    var id: String { rawValue }

    var name: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .gemini: "Gemini CLI"
        case .openCode: "OpenCode"
        }
    }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// The file Nunsseop changes or adds.
    var configURL: URL {
        switch self {
        case .claudeCode: Self.home.appendingPathComponent(".claude/settings.json")
        case .codex: Self.home.appendingPathComponent(".codex/config.toml")
        case .gemini: Self.home.appendingPathComponent(".gemini/settings.json")
        case .openCode: Self.home.appendingPathComponent(".config/opencode/plugins/nunsseop.js")
        }
    }

    /// Shown only when the tool has been used on this Mac.
    var isPresent: Bool {
        let folder = self == .openCode ? Self.home.appendingPathComponent(".config/opencode")
                                       : configURL.deletingLastPathComponent()
        return FileManager.default.fileExists(atPath: folder.path)
    }

    /// The hooks Nunsseop keeps in a JSON tool's settings. Claude Code also reports its sessions for the agents
    /// count; Gemini CLI's event names aren't known well enough for that.
    var hooks: JSONHook.Table {
        let notice = (event: "Notification", command: NotifyServer.hookCommand(title: name))
        guard self == .claudeCode else { return [notice] }
        let agent = NotifyServer.agentHookCommand
        return [notice] + ["Notification", "UserPromptSubmit", "Stop", "StopFailure", "SessionEnd"].map { ($0, agent) }
    }

    var isInstalled: Bool {
        switch self {
        case .claudeCode, .gemini:
            return (try? Self.loadJSON(at: configURL)).map(JSONHook.isInstalled(in:)) ?? false
        case .codex:
            return (try? String(contentsOf: configURL, encoding: .utf8)).map(CodexNotify.isInstalled(in:)) ?? false
        case .openCode:
            return FileManager.default.fileExists(atPath: configURL.path)
        }
    }

    /// Connecting, disconnecting and the update at launch all change the same files, so they take turns here.
    static let queue = DispatchQueue(label: "nunsseop.integrations")

    /// Connects the tool, or brings a connection from an older version up to date (a hook command without
    /// the X-App header, say), leaving a connection that's already current alone.
    func install() throws { try Self.queue.sync { try installNow() } }

    func uninstall() throws { try Self.queue.sync { try uninstallNow() } }

    private func installNow() throws {
        switch self {
        case .claudeCode, .gemini:
            let settings = try Self.loadJSON(at: configURL)
            guard let updated = try JSONHook.updating(hooks, in: settings) else { return }
            try Self.writeJSON(updated, to: configURL)
        case .codex:
            let text = try Self.loadText(at: configURL)
            let script = CodexNotify.scriptURL
            if (try? String(contentsOf: script, encoding: .utf8)) != CodexNotify.script {
                try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(CodexNotify.script.utf8).write(to: script, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            }
            guard !CodexNotify.isInstalled(in: text) else { return }
            try Self.writeText(CodexNotify.adding(to: text), to: configURL)
        case .openCode:
            guard (try? String(contentsOf: configURL, encoding: .utf8)) != Self.openCodePlugin else { return }
            // Through write(), so a plugin edited by hand is kept as a backup.
            try Self.write(Data(Self.openCodePlugin.utf8), to: configURL)
        }
    }

    /// Updates every connected tool to this version's hook, script or plugin, in the background; the rest stay
    /// untouched, except for agent hooks of ours that a deleted notice hook left behind in a JSON tool's settings.
    static func updateConnected() {
        queue.async {
            for tool in allCases {
                if tool.isInstalled {
                    try? tool.installNow()
                } else if tool == .claudeCode || tool == .gemini {
                    try? tool.uninstallNow()
                }
            }
        }
    }

    private func uninstallNow() throws {
        switch self {
        case .claudeCode, .gemini:
            let settings = try Self.loadJSON(at: configURL)
            // Any of our hooks, not only the notice one, so agent hooks left behind by a deleted notice hook go too.
            guard JSONHook.holdsAny(in: settings) else { return }
            try Self.writeJSON(JSONHook.removing(from: settings), to: configURL)
        case .codex:
            let text = try Self.loadText(at: configURL)
            guard CodexNotify.isInstalled(in: text) else { return }
            try Self.writeText(CodexNotify.removing(from: text), to: configURL)
        case .openCode:
            try? FileManager.default.removeItem(at: configURL)
        }
    }

    // MARK: Files

    static func loadJSON(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        guard let settings = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            throw IntegrationError.unreadableConfig
        }
        return settings
    }

    private static func loadText(at url: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func writeJSON(_ settings: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: settings,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try write(data, to: url)
    }

    private static func writeText(_ text: String, to url: URL) throws {
        try write(Data(text.utf8), to: url)
    }

    /// Keeps the previous file as `<name>.nunsseop-backup` before replacing it.
    private static func write(_ data: Data, to url: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            let backup = url.appendingPathExtension("nunsseop-backup")
            try? fileManager.removeItem(at: backup)
            try fileManager.copyItem(at: url, to: backup)
        } else {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        try data.write(to: url, options: .atomic)
    }

    /// OpenCode loads every file in its plugins folder; this one reports finished sessions.
    static let openCodePlugin = """
        // Added by Nunsseop: shows OpenCode's finished sessions in the notch. Delete this file to stop.
        import { readFileSync } from "node:fs"
        import { homedir } from "node:os"

        export const NunsseopPlugin = async () => ({
          event: async ({ event }) => {
            if (event.type !== "session.idle") return
            try {
              const token = readFileSync(`${homedir()}/Library/Application Support/Nunsseop/notify-token`, "utf8").trim()
              await fetch("http://127.0.0.1:\(NotifyServer.port)/notify", {
                method: "POST",
                headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
                body: JSON.stringify({ title: "OpenCode", message: "Finished", app: process.env.__CFBundleIdentifier }),
                signal: AbortSignal.timeout(2000),
              })
            } catch {}
          },
        })

        """
}

/// Claude Code and Gemini CLI both read hooks from a JSON settings file, as groups per event name.
/// A group can hold other tools' hooks and a matcher besides Nunsseop's, so everything here works on single hooks.
enum JSONHook {
    /// The hooks a tool should have: an event name and the command it runs, once each.
    typealias Table = [(event: String, command: String)]

    private static let noticeEvent = "Notification"

    /// Any of Nunsseop's hooks: the one for the agents count (`/agent`), which is ours under any event, or the
    /// notice one (`/notify`), which is ours only under Notification. Under another event it's a command the user
    /// pasted from "Copy command for scripts", and stays.
    private static func isOurs(hook: Any, event: String) -> Bool {
        guard let command = (hook as? [String: Any])?["command"] as? String else { return false }
        return command.contains("127.0.0.1:\(NotifyServer.port)/agent")
            || (event == noticeEvent && command.contains("127.0.0.1:\(NotifyServer.port)/notify"))
    }

    private static func isNotice(hook: Any) -> Bool {
        ((hook as? [String: Any])?["command"] as? String)?.contains("127.0.0.1:\(NotifyServer.port)/notify") == true
    }

    /// Arrays are read as `[Any]`: an entry that isn't an object (a stray string, say) is skipped when looking for
    /// Nunsseop's hooks and written back as it was, instead of making the whole array look empty.
    private static func hooks(in group: Any) -> [Any] { (group as? [String: Any])?["hooks"] as? [Any] ?? [] }

    private static func holdsOurs(_ group: Any, event: String) -> Bool {
        hooks(in: group).contains { isOurs(hook: $0, event: event) }
    }

    /// Whether any of Nunsseop's hooks is there, notice or not; what Disconnect has to clear.
    static func holdsAny(in settings: [String: Any]) -> Bool {
        (settings["hooks"] as? [String: Any] ?? [:]).contains { event, groups in
            ((groups as? [Any]) ?? []).contains { holdsOurs($0, event: event) }
        }
    }

    private static func groups(in settings: [String: Any], event: String) -> [Any] {
        (settings["hooks"] as? [String: Any])?[event] as? [Any] ?? []
    }

    /// Whether the notice hook is there, which is what makes a tool count as connected.
    static func isInstalled(in settings: [String: Any]) -> Bool {
        groups(in: settings, event: noticeEvent).contains { hooks(in: $0).contains(where: isNotice(hook:)) }
    }

    /// The settings with exactly the hooks in `table`, replacing older ones of Nunsseop's; nil when that's already so.
    static func updating(_ table: Table, in settings: [String: Any]) throws -> [String: Any]? {
        guard !isCurrent(table, in: settings) else { return nil }
        return try adding(table, to: removing(from: settings))
    }

    static func updating(_ command: String, in settings: [String: Any]) throws -> [String: Any]? {
        try updating([(noticeEvent, command)], in: settings)
    }

    /// Whether, across all events, Nunsseop's hooks are exactly the ones in `table`.
    static func isCurrent(_ table: Table, in settings: [String: Any]) -> Bool {
        let events = settings["hooks"] as? [String: Any] ?? [:]
        let ours = events.flatMap { event, groups in
            ((groups as? [Any]) ?? []).flatMap { hooks(in: $0).filter { isOurs(hook: $0, event: event) } }
                .map { "\(event)\n\(($0 as? [String: Any])?["command"] as? String ?? "")" }
        }
        return ours.sorted() == table.map { "\($0.event)\n\($0.command)" }.sorted()
    }

    static func isCurrent(_ command: String, in settings: [String: Any]) -> Bool {
        isCurrent([(noticeEvent, command)], in: settings)
    }

    /// The settings with the hooks added next to any hooks already under those events.
    static func adding(_ table: Table, to settings: [String: Any]) throws -> [String: Any] {
        var settings = settings
        guard var hooks = (settings["hooks"] ?? [String: Any]()) as? [String: Any] else {
            throw NotifyIntegration.IntegrationError.unreadableConfig
        }
        for (event, command) in table {
            guard var groups = (hooks[event] ?? [Any]()) as? [Any] else { throw NotifyIntegration.IntegrationError.unreadableConfig }
            groups.append(["hooks": [["type": "command", "command": command]]])
            hooks[event] = groups
        }
        settings["hooks"] = hooks
        return settings
    }

    static func adding(_ command: String, to settings: [String: Any]) throws -> [String: Any] {
        try adding([(noticeEvent, command)], to: settings)
    }

    /// The settings without Nunsseop's hooks, under every event. Other hooks in the same group, its matcher, and
    /// entries that aren't objects stay; a group is dropped only when nothing is left in it, and keys only when
    /// they end up empty.
    static func removing(from settings: [String: Any]) -> [String: Any] {
        var settings = settings
        guard var events = settings["hooks"] as? [String: Any], holdsAny(in: settings) else { return settings }
        for (event, value) in events {
            guard let groups = value as? [Any], groups.contains(where: { holdsOurs($0, event: event) }) else { continue }
            let kept = groups.compactMap { entry -> Any? in
                guard var group = entry as? [String: Any], holdsOurs(group, event: event) else { return entry }
                let others = hooks(in: group).filter { !isOurs(hook: $0, event: event) }
                guard !others.isEmpty else { return nil }
                group["hooks"] = others
                return group
            }
            events[event] = kept.isEmpty ? nil : kept
        }
        settings["hooks"] = events.isEmpty ? nil : events
        return settings
    }
}

/// Codex runs one `notify` command per finished turn, with the event JSON as its last argument.
/// Nunsseop puts its script in front of whatever command was there, and the script runs that command afterwards.
enum CodexNotify {
    static var scriptURL: URL {
        NotifyServer.tokenURL.deletingLastPathComponent().appendingPathComponent("codex-notify.sh")
    }

    static let script = """
        #!/bin/sh
        # Added by Nunsseop. Codex passes its event JSON as the last argument. This shows the turn in the notch,
        # then runs the notify command that was set before Nunsseop, if any, with the same arguments.
        for payload; do :; done
        token=$(cat "$HOME/Library/Application Support/Nunsseop/notify-token" 2>/dev/null)
        printf '%s' "$payload" | plutil -extract last-assistant-message raw -o - - 2>/dev/null \\
            | curl -s -m 2 -X POST http://127.0.0.1:\(NotifyServer.port)/notify -H "Authorization: Bearer $token" \\
                -H 'X-Title: Codex' -H "X-App: $__CFBundleIdentifier" --data-binary @- >/dev/null 2>&1
        [ $# -gt 1 ] && exec "$@"
        exit 0

        """

    /// The root-level `notify = [...]` line: its index among the lines and its strings.
    /// Root-level keys come before the first `[table]` header.
    static func notifyLine(in lines: [String]) throws -> (index: Int, command: [String])? {
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { return nil }
            guard trimmed.hasPrefix("notify"),
                  let equals = trimmed.firstIndex(of: "="),
                  trimmed[..<equals].trimmingCharacters(in: .whitespaces) == "notify" else { continue }
            let value = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            guard let command = parseStringArray(value) else { throw NotifyIntegration.IntegrationError.unreadableConfig }
            return (index, command)
        }
        return nil
    }

    static func isInstalled(in text: String) -> Bool {
        let lines = text.components(separatedBy: "\n")
        return ((try? notifyLine(in: lines)) ?? nil)?.command.contains(scriptURL.path) == true
    }

    static func adding(to text: String) throws -> String {
        var lines = text.components(separatedBy: "\n")
        if let found = try notifyLine(in: lines) {
            lines[found.index] = line(for: ["/bin/sh", scriptURL.path] + found.command)
        } else {
            lines.insert(line(for: ["/bin/sh", scriptURL.path]), at: 0)
        }
        return lines.joined(separator: "\n")
    }

    /// Puts back the command that was there before, or removes the line if there was none.
    static func removing(from text: String) throws -> String {
        var lines = text.components(separatedBy: "\n")
        guard let found = try notifyLine(in: lines),
              found.command.count >= 2, found.command[1] == scriptURL.path else { return text }
        let previous = Array(found.command.dropFirst(2))
        if previous.isEmpty { lines.remove(at: found.index) } else { lines[found.index] = line(for: previous) }
        return lines.joined(separator: "\n")
    }

    private static func line(for command: [String]) -> String {
        let quoted = command.map { "\"" + $0.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        return "notify = [" + quoted.joined(separator: ", ") + "]"
    }

    /// A one-line TOML array of basic ("…") or literal ('…') strings, optionally followed by a comment.
    static func parseStringArray(_ value: String) -> [String]? {
        var characters = Substring(value)
        guard characters.popFirst() == "[" else { return nil }
        var result: [String] = []
        while true {
            characters = characters.drop(while: { $0 == " " || $0 == "\t" })
            guard let first = characters.popFirst() else { return nil }
            if first == "]" { break }
            if first == ",", !result.isEmpty { continue }
            guard first == "\"" || first == "'" else { return nil }
            var string = ""
            var closed = false
            while let c = characters.popFirst() {
                if c == first { closed = true; break }
                if c == "\\", first == "\"" {
                    switch characters.popFirst() {
                    case "\\"?: string.append("\\")
                    case "\""?: string.append("\"")
                    case "n"?: string.append("\n")
                    case "t"?: string.append("\t")
                    default: return nil
                    }
                } else {
                    string.append(c)
                }
            }
            guard closed else { return nil }
            result.append(string)
        }
        let rest = characters.trimmingCharacters(in: .whitespaces)
        return rest.isEmpty || rest.hasPrefix("#") ? result : nil
    }
}
