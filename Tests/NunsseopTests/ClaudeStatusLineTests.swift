import Foundation
import Testing
@testable import Nunsseop

struct ClaudeStatusLineSettingsTests {
    let script = "/Users/me/Library/Application Support/Nunsseop/claude-statusline.sh"

    private func connect(_ settings: [String: Any], script: String? = nil) throws -> (settings: [String: Any], original: [String: Any]?) {
        let connected = try ClaudeStatusLine.connecting(settings, script: script ?? self.script)
        return try #require(connected)
    }

    @Test func wrapsTheStatusLineKeepingItsOtherKeys() throws {
        let original: [String: Any] = ["type": "command", "command": "~/bin/line.sh", "padding": 2, "refreshInterval": 5]
        let connected = try connect(["model": "opus", "statusLine": original])
        let line = try #require(connected.settings["statusLine"] as? [String: Any])
        #expect(line["command"] as? String == "'\(script)'")
        #expect(line["padding"] as? Int == 2)
        #expect(line["refreshInterval"] as? Int == 5)
        #expect(connected.settings["model"] as? String == "opus")
        #expect(NSDictionary(dictionary: try #require(connected.original)).isEqual(to: original))
        #expect(ClaudeStatusLine.isOurs(connected.settings, script: script))
        #expect(!ClaudeStatusLine.isOurs(["statusLine": original], script: script))
    }

    @Test func neverWrapsItself() throws {
        let connected = try connect([:])
        #expect(try ClaudeStatusLine.connecting(connected.settings, script: script) == nil)
    }

    @Test func addsAStatusLineWhenThereIsNone() throws {
        let connected = try connect(["model": "opus"])
        #expect(connected.original == nil)
        let line = try #require(connected.settings["statusLine"] as? [String: Any])
        #expect(line["type"] as? String == "command")
        #expect(try connect(["statusLine": NSNull()]).original == nil)
        let restored = try #require(ClaudeStatusLine.disconnecting(connected.settings, original: nil, script: script))
        #expect(NSDictionary(dictionary: restored).isEqual(to: ["model": "opus"]))
    }

    @Test func quotesAPathWithApostrophes() throws {
        let odd = "/Users/o'neil/Application Support/claude-statusline.sh"
        let connected = try connect([:], script: odd)
        let command = try #require((connected.settings["statusLine"] as? [String: Any])?["command"] as? String)
        #expect(command == #"'/Users/o'\''neil/Application Support/claude-statusline.sh'"#)
        #expect(ClaudeStatusLine.isOurs(connected.settings, script: odd))
    }

    @Test func restoresTheOriginalAndKeepsKeysChangedSince() throws {
        let original: [String: Any] = ["type": "command", "command": "line.sh", "padding": 0]
        let connected = try connect(["statusLine": original])
        var changed = connected.settings
        var line = try #require(changed["statusLine"] as? [String: Any])
        line["padding"] = 3
        changed["statusLine"] = line
        let restored = try #require(ClaudeStatusLine.disconnecting(changed, original: connected.original, script: script))
        let back = try #require(restored["statusLine"] as? [String: Any])
        #expect(back["command"] as? String == "line.sh")
        #expect(back["padding"] as? Int == 3)
    }

    @Test func leavesAStatusLineSomethingElseSetAlone() throws {
        let connected = try connect(["statusLine": ["type": "command", "command": "a.sh"]])
        let replaced: [String: Any] = ["statusLine": ["type": "command", "command": "b.sh"]]
        #expect(ClaudeStatusLine.disconnecting(replaced, original: connected.original, script: script) == nil)
        #expect(ClaudeStatusLine.disconnecting([:], original: nil, script: script) == nil)
        #expect(ClaudeStatusLine.state(of: replaced, hasSavedOriginal: true, script: script) == .changed)
        #expect(ClaudeStatusLine.state(of: replaced, hasSavedOriginal: false, script: script) == .notConnected)
        #expect(ClaudeStatusLine.state(of: connected.settings, hasSavedOriginal: true, script: script) == .connected)
    }

    @Test func refusesAStatusLineThatIsNotAnObject() {
        #expect(throws: NotifyIntegration.IntegrationError.self) { try ClaudeStatusLine.connecting(["statusLine": "x.sh"], script: script) }
    }
}

struct ClaudeStatusLineFilesTests {
    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nunsseop-statusline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func settings(at url: URL) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    @Test func connectsAndDisconnectsInATemporaryFolder() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ClaudeStatusLine.Paths(settings: root.appendingPathComponent("settings.json"),
                                           folder: root.appendingPathComponent("Application Support"))
        let before = #"{"hooks":{"Stop":[]},"statusLine":{"type":"command","command":"echo 'hi there'","padding":1}}"#
        try Data(before.utf8).write(to: paths.settings)
        #expect(ClaudeStatusLine.state(paths) == .notConnected)

        try ClaudeStatusLine.connect(paths)
        try ClaudeStatusLine.connect(paths)
        #expect(ClaudeStatusLine.state(paths) == .connected)
        let line = try #require(settings(at: paths.settings)["statusLine"] as? [String: Any])
        #expect(line["command"] as? String == ClaudeStatusLine.shellQuoted(paths.script.path))
        #expect(line["padding"] as? Int == 1)
        #expect(try settings(at: paths.settings)["hooks"] != nil)
        #expect(FileManager.default.isExecutableFile(atPath: paths.script.path))

        try ClaudeStatusLine.disconnect(paths)
        #expect(ClaudeStatusLine.state(paths) == .notConnected)
        let restored = try #require(settings(at: paths.settings)["statusLine"] as? [String: Any])
        #expect(restored["command"] as? String == "echo 'hi there'")
        #expect(restored["padding"] as? Int == 1)
        for url in [paths.script, paths.original, paths.snapshot] {
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func disconnectWithNoOriginalRemovesTheStatusLine() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ClaudeStatusLine.Paths(settings: root.appendingPathComponent("settings.json"), folder: root)
        try Data(#"{"model":"opus"}"#.utf8).write(to: paths.settings)
        try ClaudeStatusLine.connect(paths)
        try ClaudeStatusLine.disconnect(paths)
        let after = try settings(at: paths.settings)
        #expect(after["statusLine"] == nil)
        #expect(after["model"] as? String == "opus")
    }

    @Test func disconnectLeavesAReplacedStatusLineButRemovesOurFiles() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ClaudeStatusLine.Paths(settings: root.appendingPathComponent("settings.json"), folder: root)
        try Data(#"{"statusLine":{"type":"command","command":"a.sh"}}"#.utf8).write(to: paths.settings)
        try ClaudeStatusLine.connect(paths)
        try Data(#"{"statusLine":{"type":"command","command":"b.sh"}}"#.utf8).write(to: paths.settings)
        #expect(ClaudeStatusLine.state(paths) == .changed)
        try ClaudeStatusLine.disconnect(paths)
        let line = try #require(settings(at: paths.settings)["statusLine"] as? [String: Any])
        #expect(line["command"] as? String == "b.sh")
        #expect(!FileManager.default.fileExists(atPath: paths.script.path))
        #expect(ClaudeStatusLine.state(paths) == .notConnected)
    }
}

struct ClaudeStatusLineScriptTests {
    private struct Run { let output: String; let status: Int32 }

    private let withLimits = #"{"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600}}}"#

    /// Writes the script for `original` into a folder with a space in its name and runs it with `input` on stdin.
    private func run(original: [String: Any]?, input: String, in folder: URL) throws -> Run {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let script = folder.appendingPathComponent("claude-statusline.sh")
        try Data(ClaudeStatusLine.script(original: original, snapshotName: "claude-rate-limits.json").utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let process = Process()
        process.executableURL = script
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        try stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Run(output: String(decoding: output, as: UTF8.self), status: process.terminationStatus)
    }

    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("nunsseop-wrapper-\(UUID().uuidString)/Application Support")
    }

    @Test func passesStdoutAndStatusOfTheOriginalThrough() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        // Quotes and spaces in the command, the input on its stdin, and a status that isn't 0.
        let original = ["command": #"printf "it's [%s]\n" "$(cat)"; echo "two  words" 'and $HOME'; exit 7"#]
        let result = try run(original: original, input: withLimits, in: folder)
        #expect(result.output == "it's [\(withLimits)]\ntwo  words and $HOME\n")
        #expect(result.status == 7)
        let snapshot = try String(contentsOf: folder.appendingPathComponent("claude-rate-limits.json"), encoding: .utf8)
        #expect(snapshot == withLimits)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(leftovers.sorted() == ["claude-rate-limits.json", "claude-statusline.sh"])
    }

    @Test func onlyWritesTheSnapshotWhenItHasRateLimits() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let original = ["command": "cat"]
        _ = try run(original: original, input: withLimits, in: folder)
        let without = #"{"model":{"id":"x"}}"#
        let result = try run(original: original, input: without + "\n\n", in: folder)
        // The input reaches the original exactly, trailing newlines included, and the older snapshot stays.
        #expect(result.output == without + "\n\n")
        #expect(result.status == 0)
        #expect(try String(contentsOf: folder.appendingPathComponent("claude-rate-limits.json"), encoding: .utf8) == withLimits)
    }

    @Test func printsNothingWithoutAnOriginalAndStillKeepsTheSnapshot() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let result = try run(original: nil, input: withLimits, in: folder)
        #expect(result.output.isEmpty)
        #expect(result.status == 0)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("claude-rate-limits.json").path))
    }

    @Test func aSnapshotThatCannotBeWrittenChangesNothing() throws {
        let folder = temporaryFolder()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
            try? FileManager.default.removeItem(at: folder.deletingLastPathComponent())
        }
        let original = ["command": "echo ok; cat >/dev/null; exit 4"]
        _ = try run(original: original, input: "{}", in: folder)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        let script = folder.appendingPathComponent("claude-statusline.sh")
        let process = Process()
        process.executableURL = script
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        try stdin.fileHandleForWriting.write(contentsOf: Data(withLimits.utf8))
        try stdin.fileHandleForWriting.close()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(String(decoding: output, as: UTF8.self) == "ok\n")
        #expect(process.terminationStatus == 4)
        #expect(stderr.fileHandleForReading.readDataToEndOfFile().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("claude-rate-limits.json").path))
    }
}
