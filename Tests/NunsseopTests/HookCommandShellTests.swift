import Foundation
import Testing
@testable import Nunsseop

/// A shell run with a stand-in `curl` that records what it was given, a stand-in `prev.sh` (the user's own notify
/// command), a scratch home holding the notify token, and a pinned `__CFBundleIdentifier`.
private struct ShellRun {
    var args: [String] = []
    var body = ""
    var curlCalls = 0
    /// The arguments `prev.sh` got, nil when it didn't run.
    var previousArgs: [String]?
    var stdout = ""
    var status: Int32 = 0
    var dir: URL

    /// - arguments: what to give `/bin/sh`, given the scratch folder.
    /// - environment: extra variables; the inherited ones are not passed on.
    static func run(_ arguments: (URL) throws -> [String], stdin: String = "", environment: [String: String] = [:],
                    curlExit: Int32 = 0) throws -> ShellRun {
        let fileManager = FileManager.default
        let dir = fileManager.temporaryDirectory.appendingPathComponent("nunsseop-test-\(UUID().uuidString.prefix(8))")
        try fileManager.createDirectory(at: dir.appendingPathComponent("bin"), withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: dir) }
        let support = dir.appendingPathComponent("Library/Application Support/Nunsseop")
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        try "tok\n".write(to: support.appendingPathComponent("notify-token"), atomically: true, encoding: .utf8)
        let curl = dir.appendingPathComponent("bin/curl")
        try """
        #!/bin/sh
        echo x >> "\(dir.path)/calls"
        for arg; do printf '%s\\n' "$arg"; done > "\(dir.path)/args"
        cat > "\(dir.path)/body"
        echo LEAK
        exit \(curlExit)
        """.write(to: curl, atomically: true, encoding: .utf8)
        let previous = dir.appendingPathComponent("prev.sh")
        try """
        #!/bin/sh
        for arg; do printf '%s\\n' "$arg"; done > "\(dir.path)/prev-args"
        """.write(to: previous, atomically: true, encoding: .utf8)
        for file in [curl, previous] { try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = try arguments(dir)
        process.currentDirectoryURL = dir
        process.environment = ["HOME": dir.path, "PATH": "\(dir.path)/bin:/usr/bin:/bin"].merging(environment) { $1 }
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        input.fileHandleForWriting.write(Data(stdin.utf8))
        try input.fileHandleForWriting.close()
        let out = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        func text(_ name: String) -> String? { try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) }
        func lines(_ name: String) -> [String]? { text(name).map { Array($0.components(separatedBy: "\n").dropLast()) } }
        var result = ShellRun(dir: dir)
        result.args = lines("args") ?? []
        result.body = text("body") ?? ""
        result.curlCalls = lines("calls")?.count ?? 0
        result.previousArgs = lines("prev-args")
        result.stdout = String(data: out, encoding: .utf8) ?? ""
        result.status = process.terminationStatus
        return result
    }
}

private func json(_ object: [String: String]) -> String {
    String(data: try! JSONSerialization.data(withJSONObject: object, options: .sortedKeys), encoding: .utf8)!
}

struct AgentHookShellTests {
    private func run(_ stdin: String, environment: [String: String] = ["__CFBundleIdentifier": "com.x"], curlExit: Int32 = 0) throws -> ShellRun {
        try ShellRun.run({ _ in ["-c", NotifyServer.agentHookCommand] }, stdin: stdin, environment: environment, curlExit: curlExit)
    }

    @Test func sendsTheEventAsHeadersOnly() throws {
        let sent = try run(json(["session_id": "abc-123", "hook_event_name": "Stop", "notification_type": "permission_prompt",
                                 "prompt": "secret prompt", "cwd": "/Users/me/secret"]))
        #expect(sent.args == [
            "-s", "-m", "1", "--connect-timeout", "1", "-X", "POST", "http://127.0.0.1:\(NotifyServer.port)/agent", "-d", "",
            "-H", "Authorization: Bearer tok", "-H", "X-Session: abc-123", "-H", "X-Event: Stop",
            "-H", "X-Type: permission_prompt", "-H", "X-Subagent: ", "-H", "X-App: com.x",
            "-H", "X-Herdr: ", "-H", "X-Background: ",
        ])
        #expect(sent.curlCalls == 1)
        #expect(sent.stdout.isEmpty)
        #expect(sent.status == 0)
    }

    @Test func herdrAndBackgroundSessionsAreFlagged() throws {
        let stdin = json(["session_id": "s", "hook_event_name": "UserPromptSubmit"])
        let herdr = try run(stdin, environment: ["__CFBundleIdentifier": "com.x", "HERDR_PANE_ID": "1"])
        #expect(herdr.args.contains("X-Herdr: 1") && herdr.args.contains("X-Background: "))
        let background = try run(stdin, environment: ["__CFBundleIdentifier": "com.x", "CLAUDE_JOB_DIR": "/tmp/job"])
        #expect(background.args.contains("X-Background: 1") && background.args.contains("X-Herdr: "))
        let unset = try run(stdin, environment: [:])
        #expect(unset.args.contains("X-App: "))
    }

    @Test func aSubagentCallCarriesItsId() throws {
        let sent = try run(json(["session_id": "s", "hook_event_name": "Stop", "agent_id": "agent-1"]))
        #expect(sent.args.contains("X-Subagent: agent-1"))
    }

    @Test func idsAreTrimmedToSafeCharactersAndNeverRun() throws {
        let sent = try run(json(["session_id": "a$(touch pwn)b;`touch pwn2`\r\nX-Evil: 1", "hook_event_name": "Stop"]))
        #expect(sent.args.contains("X-Session: atouchpwnbtouchpwn2X-Evil1"))
        #expect(!FileManager.default.fileExists(atPath: sent.dir.appendingPathComponent("pwn").path))
        #expect(!FileManager.default.fileExists(atPath: sent.dir.appendingPathComponent("pwn2").path))
        let long = try run(json(["session_id": String(repeating: "a", count: 100), "hook_event_name": "Stop"]))
        #expect(long.args.contains("X-Session: " + String(repeating: "a", count: 64)))
    }

    @Test func emptyOrBrokenInputStillCallsWithEmptyHeaders() throws {
        for stdin in ["", "not json", "[1]"] {
            let sent = try run(stdin)
            #expect(sent.curlCalls == 1, "\(stdin)")
            #expect(sent.args.contains("X-Session: ") && sent.args.contains("X-Event: ") && sent.args.contains("X-Type: "), "\(stdin)")
            #expect(sent.status == 0 && sent.stdout.isEmpty)
        }
    }

    @Test func aClosedNunsseopCostsTheSessionNothing() throws {
        let sent = try run(json(["session_id": "s", "hook_event_name": "Stop"]), curlExit: 7)
        #expect(sent.status == 0)
        #expect(sent.stdout.isEmpty)
    }
}

struct NoticeHookShellTests {
    private func run(_ environment: [String: String] = [:], curlExit: Int32 = 0) throws -> ShellRun {
        try ShellRun.run({ _ in ["-c", NotifyServer.hookCommand(title: "Claude Code")] },
                         stdin: json(["message": "Claude needs your permission"]),
                         environment: ["__CFBundleIdentifier": "com.apple.Terminal"].merging(environment) { $1 }, curlExit: curlExit)
    }

    @Test func sendsTheMessageAsTheBody() throws {
        let sent = try run()
        #expect(sent.args == [
            "-s", "-m", "2", "-X", "POST", "http://127.0.0.1:\(NotifyServer.port)/notify",
            "-H", "Authorization: Bearer tok", "-H", "X-Title: Claude Code", "-H", "X-App: com.apple.Terminal", "--data-binary", "@-",
        ])
        #expect(sent.body == "Claude needs your permission\n")
        #expect(sent.stdout.isEmpty)
        #expect(sent.status == 0)
    }

    @Test func aFailingCurlDoesNotFailTheHook() throws {
        let sent = try run(curlExit: 7)
        #expect(sent.status == 0 && sent.stdout.isEmpty)
    }

    @Test func geminiGetsItsOwnTitle() throws {
        let sent = try ShellRun.run({ _ in ["-c", NotifyServer.hookCommand(title: "Gemini CLI")] },
                                    stdin: json(["message": "m"]), environment: ["__CFBundleIdentifier": "com.x"])
        #expect(sent.args.contains("X-Title: Gemini CLI"))
    }
}

struct CodexNotifyScriptTests {
    private let payload = #"{"type":"agent-turn-complete","last-assistant-message":"All done"}"#

    /// Runs the shipped wrapper; `PREVIOUS` in `arguments` stands for the user's own notify command.
    private func run(_ arguments: [String], curlExit: Int32 = 0) throws -> ShellRun {
        try ShellRun.run({ dir in
            let script = dir.appendingPathComponent("codex-notify.sh")
            try CodexNotify.script.write(to: script, atomically: true, encoding: .utf8)
            return [script.path] + arguments.map { $0 == "PREVIOUS" ? dir.appendingPathComponent("prev.sh").path : $0 }
        }, environment: ["__CFBundleIdentifier": "com.x"], curlExit: curlExit)
    }

    @Test func showsTheTurnAndThenRunsTheCommandThatWasThereBefore() throws {
        let sent = try run(["PREVIOUS", "--flag", payload])
        #expect(sent.args == [
            "-s", "-m", "2", "-X", "POST", "http://127.0.0.1:\(NotifyServer.port)/notify",
            "-H", "Authorization: Bearer tok", "-H", "X-Title: Codex", "-H", "X-App: com.x", "--data-binary", "@-",
        ])
        #expect(sent.body == "All done\n")
        #expect(sent.previousArgs == ["--flag", payload])
        #expect(sent.status == 0 && sent.stdout.isEmpty)
    }

    @Test func withNothingBeforeItOnlyShowsTheTurn() throws {
        let sent = try run([payload])
        #expect(sent.curlCalls == 1 && sent.body == "All done\n")
        #expect(sent.previousArgs == nil)
        #expect(sent.status == 0)
    }

    @Test func aPayloadWithoutAMessageStillRunsTheCommandBefore() throws {
        for odd in [#"{"type":"agent-turn-complete"}"#, "not json", ""] {
            let sent = try run(["PREVIOUS", odd])
            #expect(sent.curlCalls == 1 && sent.body.isEmpty, "\(odd)")
            #expect(sent.previousArgs == [odd], "\(odd)")
            #expect(sent.status == 0)
        }
    }

    @Test func aFailingCurlDoesNotStopTheCommandBefore() throws {
        let sent = try run(["PREVIOUS", "--flag", payload], curlExit: 7)
        #expect(sent.previousArgs == ["--flag", payload])
        #expect(sent.status == 0)
        let alone = try run([payload], curlExit: 7)
        #expect(alone.status == 0)
    }
}
