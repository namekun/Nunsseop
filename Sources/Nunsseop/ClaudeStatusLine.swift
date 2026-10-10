import Foundation

/// Claude Code passes JSON, with the rate limits in it, to its status line command. Nunsseop puts a script in front of
/// that command: the script keeps a copy of the JSON for the AI usage tab and runs the command that was there before.
enum ClaudeStatusLine {
    enum State { case notConnected, connected, changed }

    /// Where the settings file and Nunsseop's files are, so tests can use a temporary folder.
    struct Paths {
        let settings: URL
        let folder: URL

        var script: URL { folder.appendingPathComponent("claude-statusline.sh") }
        /// The `statusLine` object that was set before Nunsseop, saved to put back.
        var original: URL { folder.appendingPathComponent("claude-statusline-original.json") }
        var snapshot: URL { folder.appendingPathComponent("claude-rate-limits.json") }

        static var live: Paths {
            Paths(settings: NotifyIntegration.claudeCode.configURL, folder: NotifyServer.tokenURL.deletingLastPathComponent())
        }
    }

    // MARK: Settings

    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func isOurs(_ settings: [String: Any], script: String) -> Bool {
        guard let command = (settings["statusLine"] as? [String: Any])?["command"] as? String else { return false }
        return [script, shellQuoted(script)].contains(command.trimmingCharacters(in: .whitespaces))
    }

    static func state(of settings: [String: Any], hasSavedOriginal: Bool, script: String) -> State {
        isOurs(settings, script: script) ? .connected : hasSavedOriginal ? .changed : .notConnected
    }

    /// The settings with `statusLine.command` running the script, other `statusLine` keys kept, and the `statusLine`
    /// object it replaces; nil when the script is already there, so it never wraps itself.
    static func connecting(_ settings: [String: Any], script: String) throws -> (settings: [String: Any], original: [String: Any]?)? {
        guard !isOurs(settings, script: script) else { return nil }
        var settings = settings
        var line: [String: Any] = [:]
        var original: [String: Any]?
        if let existing = settings["statusLine"], !(existing is NSNull) {
            guard let object = existing as? [String: Any] else { throw NotifyIntegration.IntegrationError.unreadableConfig }
            line = object
            original = object
        }
        line["type"] = "command"
        line["command"] = shellQuoted(script)
        settings["statusLine"] = line
        return (settings, original)
    }

    /// The settings with the original command back, or without `statusLine` if there was none. Keys changed in
    /// `statusLine` since stay. Nil when something else has replaced the command: that is left alone.
    static func disconnecting(_ settings: [String: Any], original: [String: Any]?, script: String) -> [String: Any]? {
        guard isOurs(settings, script: script), var line = settings["statusLine"] as? [String: Any] else { return nil }
        var settings = settings
        if let original {
            line["command"] = original["command"]
            settings["statusLine"] = line
        } else {
            settings["statusLine"] = nil
        }
        return settings
    }

    // MARK: Script

    static func script(original: [String: Any]?, snapshotName: String) -> String {
        let command = (original?["command"] as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let run = command.map { "printf '%s' \"$input\" 2>/dev/null | /bin/sh -c \(shellQuoted($0))" } ?? "exit 0"
        return """
            #!/bin/sh
            # Added by Nunsseop. Claude Code passes its status line JSON on stdin. This keeps a copy of it that holds the
            # rate limits, next to this script, then runs the status line command that was set before Nunsseop, if any,
            # with the same input. Nothing here may change what the status line prints.
            input=$(cat; echo x); input=${input%x}
            case $input in *'"rate_limits"'*)
                tmp="${0%/*}/.\(snapshotName).$$"
                { printf '%s' "$input" > "$tmp" && mv -f "$tmp" "${0%/*}/\(snapshotName)"; } 2>/dev/null || rm -f "$tmp" 2>/dev/null ;;
            esac
            \(run)

            """
    }

    // MARK: Files

    static func state(_ paths: Paths = .live) -> State {
        let settings = (try? NotifyIntegration.loadJSON(at: paths.settings)) ?? [:]
        return state(of: settings, hasSavedOriginal: FileManager.default.fileExists(atPath: paths.original.path),
                     script: paths.script.path)
    }

    static func connect(_ paths: Paths = .live) throws {
        try NotifyIntegration.queue.sync {
            let settings = try NotifyIntegration.loadJSON(at: paths.settings)
            guard let connected = try connecting(settings, script: paths.script.path) else { return }
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: paths.folder, withIntermediateDirectories: true)
            let saved = try JSONSerialization.data(withJSONObject: connected.original.map { ["statusLine": $0] } ?? [:],
                                                   options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try saved.write(to: paths.original, options: .atomic)
            do {
                let script = script(original: connected.original, snapshotName: paths.snapshot.lastPathComponent)
                try Data(script.utf8).write(to: paths.script, options: .atomic)
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: paths.script.path)
                try NotifyIntegration.writeJSON(connected.settings, to: paths.settings)
            } catch {
                removeFiles(paths)
                throw error
            }
        }
    }

    static func disconnect(_ paths: Paths = .live) throws {
        try NotifyIntegration.queue.sync {
            let settings = try NotifyIntegration.loadJSON(at: paths.settings)
            let original = (try? Data(contentsOf: paths.original))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["statusLine"] as? [String: Any]
            if let restored = disconnecting(settings, original: original, script: paths.script.path) {
                try NotifyIntegration.writeJSON(restored, to: paths.settings)
            }
            removeFiles(paths)
        }
    }

    private static func removeFiles(_ paths: Paths) {
        for url in [paths.script, paths.original, paths.snapshot] { try? FileManager.default.removeItem(at: url) }
    }
}
