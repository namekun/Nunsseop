import Foundation
import Testing
@testable import Nunsseop

/// The real-file side of connecting a tool, against a scratch home folder.
struct NotifyIntegrationFileTests {
    private let claude = NotifyIntegration.claudeCode
    private let fileManager = FileManager.default

    private func backup(of url: URL) -> URL { url.appendingPathExtension("nunsseop-backup") }

    private func put(_ text: String, at url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func bytes(_ url: URL) -> Data? { try? Data(contentsOf: url) }

    private func modified(_ url: URL) -> Date? {
        try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    private func text(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    private func names(in folder: URL) -> [String]? { try? fileManager.contentsOfDirectory(atPath: folder.path) }

    private func sameJSON(_ a: [String: Any], _ b: [String: Any]) -> Bool { NSDictionary(dictionary: a).isEqual(to: b) }

    private let userHooks = #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"mine.sh"}]}]},"model":"opus"}"#

    // MARK: Install

    @Test func installKeepsTheOtherSettingsAsTheyWereAndBacksUpFirst() throws {
        try withTempHome { _ in
            let seed = #"{"model":"opus","flag":true,"n":1.5,"nil":null,"path":"/a/b","name":"한글","permissions":{"allow":["Bash(ls)"]}}"#
            try put(seed, at: claude.configURL)
            try claude.installNow()

            let settings = try NotifyIntegration.loadJSON(at: claude.configURL)
            #expect(JSONHook.isCurrent(claude.hooks, in: settings))
            #expect(settings["model"] as? String == "opus")
            #expect(settings["n"] as? Double == 1.5)
            #expect(settings["nil"] is NSNull)
            #expect(settings["path"] as? String == "/a/b")
            #expect(settings["name"] as? String == "한글")
            #expect(settings["permissions"] as? [String: [String]] == ["allow": ["Bash(ls)"]])
            let written = try String(contentsOf: claude.configURL, encoding: .utf8)
            #expect(written.contains(#""flag" : true"#) && written.contains(#""n" : 1.5"#) && written.contains(#""nil" : null"#))
            #expect(written.contains(#""path" : "/a/b""#) && written.contains(#""name" : "한글""#))
            #expect(bytes(backup(of: claude.configURL)) == Data(seed.utf8))
        }
    }

    @Test func installingAgainLeavesTheFileAndItsBackupAlone() throws {
        try withTempHome { _ in
            let seed = #"{"model":"opus"}"#
            try put(seed, at: claude.configURL)
            try claude.installNow()
            let installed = bytes(claude.configURL), date = modified(claude.configURL)
            try claude.installNow()
            #expect(bytes(claude.configURL) == installed)
            #expect(modified(claude.configURL) == date)
            #expect(bytes(backup(of: claude.configURL)) == Data(seed.utf8))
        }
    }

    @Test func installCreatesTheFileAndFolderWhenThereIsNone() throws {
        try withTempHome { home in
            try claude.installNow()
            let settings = try NotifyIntegration.loadJSON(at: claude.configURL)
            #expect(JSONHook.isCurrent(claude.hooks, in: settings))
            #expect(!fileManager.fileExists(atPath: backup(of: claude.configURL).path))

            try NotifyIntegration.gemini.installNow()
            let gemini = try NotifyIntegration.loadJSON(at: home.appendingPathComponent(".gemini/settings.json"))
            #expect(JSONHook.isCurrent(NotifyIntegration.gemini.hooks, in: gemini))
            #expect(JSONHook.isInstalled(in: gemini))
        }
    }

    @Test func aConfigThatCantBeReadIsNeverOverwritten() throws {
        try withTempHome { _ in
            for seed in [#"{"hooks": "#, "[1,2]", "// c\n{}", ""] {
                try put(seed, at: claude.configURL)
                #expect(throws: (any Error).self, "\(seed)") { try claude.installNow() }
                #expect(bytes(claude.configURL) == Data(seed.utf8), "\(seed)")
                #expect(!fileManager.fileExists(atPath: backup(of: claude.configURL).path), "\(seed)")
                #expect(!claude.isInstalled)
            }
            // A hooks key of another shape is refused too.
            let odd = #"{"hooks":"nope"}"#
            try put(odd, at: claude.configURL)
            #expect(throws: NotifyIntegration.IntegrationError.self) { try claude.installNow() }
            #expect(bytes(claude.configURL) == Data(odd.utf8))
        }
    }

    // MARK: Uninstall

    @Test func uninstallLeavesOnlyTheUsersOwnHooks() throws {
        try withTempHome { _ in
            try put(userHooks, at: claude.configURL)
            let original = try NotifyIntegration.loadJSON(at: claude.configURL)
            try claude.installNow()
            #expect(claude.isInstalled)
            try claude.uninstallNow()
            #expect(!claude.isInstalled)
            #expect(sameJSON(try NotifyIntegration.loadJSON(at: claude.configURL), original))
        }
    }

    @Test func uninstallDropsTheHooksKeyWhenNothingIsLeftInIt() throws {
        try withTempHome { _ in
            try put(#"{"model":"opus"}"#, at: claude.configURL)
            try claude.installNow()
            try claude.uninstallNow()
            let settings = try NotifyIntegration.loadJSON(at: claude.configURL)
            #expect(sameJSON(settings, ["model": "opus"]))
        }
    }

    @Test func uninstallWithNoConfigChangesNothing() throws {
        try withTempHome { home in
            try claude.uninstallNow()
            try NotifyIntegration.gemini.uninstallNow()
            try NotifyIntegration.codex.uninstallNow()
            #expect(names(in: home) == [])
        }
    }

    @Test func uninstallLeavesAFileWithoutOurHooksUntouched() throws {
        try withTempHome { _ in
            try put(userHooks, at: claude.configURL)
            let date = modified(claude.configURL)
            try claude.uninstallNow()
            #expect(bytes(claude.configURL) == Data(userHooks.utf8))
            #expect(modified(claude.configURL) == date)
            #expect(!fileManager.fileExists(atPath: backup(of: claude.configURL).path))
        }
    }

    // MARK: Update at launch

    @Test func launchBringsAnOlderNoticeHookUpToDate() throws {
        try withTempHome { _ in
            let old = "plutil -extract message raw -o - - | curl -s http://127.0.0.1:\(NotifyServer.port)/notify --data-binary @-"
            let seed: [String: Any] = ["hooks": ["Notification": [["hooks": [["type": "command", "command": old]]],
                                                                 ["hooks": [["type": "command", "command": "mine.sh"]]]]]]
            try NotifyIntegration.writeJSON(seed, to: claude.configURL)
            NotifyIntegration.updateConnectedNow()

            let settings = try NotifyIntegration.loadJSON(at: claude.configURL)
            #expect(JSONHook.isCurrent(claude.hooks, in: settings))
            let groups = try #require((settings["hooks"] as? [String: Any])?["Notification"] as? [[String: Any]])
            let commands = groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
            #expect(commands.contains("mine.sh") && !commands.contains(old))
        }
    }

    @Test func launchClearsAgentHooksLeftBehindByADeletedNoticeHook() throws {
        try withTempHome { _ in
            let mine: [String: Any] = ["hooks": [["type": "command", "command": "mine.sh"]]]
            let seed = try JSONHook.adding([("Stop", NotifyServer.agentHookCommand), ("UserPromptSubmit", NotifyServer.agentHookCommand)],
                                           to: ["hooks": ["Stop": [mine]], "model": "opus"])
            try NotifyIntegration.writeJSON(seed, to: claude.configURL)
            #expect(JSONHook.holdsAny(in: seed) && !JSONHook.isInstalled(in: seed))
            NotifyIntegration.updateConnectedNow()

            let settings = try NotifyIntegration.loadJSON(at: claude.configURL)
            #expect(!JSONHook.holdsAny(in: settings))
            #expect(sameJSON(settings, ["hooks": ["Stop": [mine]], "model": "opus"]))
        }
    }

    @Test func launchLeavesWhatWasNeverConnectedAlone() throws {
        try withTempHome { home in
            try put(userHooks, at: claude.configURL)
            let date = modified(claude.configURL)
            NotifyIntegration.updateConnectedNow()
            #expect(bytes(claude.configURL) == Data(userHooks.utf8))
            #expect(modified(claude.configURL) == date)
            #expect(!fileManager.fileExists(atPath: backup(of: claude.configURL).path))
            #expect(!fileManager.fileExists(atPath: home.appendingPathComponent(".gemini").path))
        }
    }

    @Test func launchLeavesAConfigItCantReadAlone() throws {
        try withTempHome { _ in
            let seed = #"{"hooks": "#
            try put(seed, at: claude.configURL)
            NotifyIntegration.updateConnectedNow()
            #expect(bytes(claude.configURL) == Data(seed.utf8))
            #expect(!fileManager.fileExists(atPath: backup(of: claude.configURL).path))
        }
    }

    @Test func launchWithNothingInstalledCreatesNothing() throws {
        try withTempHome { home in
            NotifyIntegration.updateConnectedNow()
            #expect(names(in: home) == [])
        }
    }

    @Test func launchRewritesAnOldCodexScriptButNotTheConfig() throws {
        try withTempHome { home in
            let config = NotifyIntegration.codex.configURL
            let configText = try CodexNotify.adding(to: "model = \"o3\"\n")
            try put(configText, at: config)
            try put("#!/bin/sh\necho old\n", at: CodexNotify.scriptURL)
            try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: CodexNotify.scriptURL.path)
            NotifyIntegration.updateConnectedNow()

            #expect(CodexNotify.scriptURL.path == home.appendingPathComponent("Library/Application Support/Nunsseop/codex-notify.sh").path)
            #expect(text(CodexNotify.scriptURL) == CodexNotify.script)
            #expect((try? fileManager.attributesOfItem(atPath: CodexNotify.scriptURL.path))?[.posixPermissions] as? Int == 0o755)
            #expect(self.text(config) == configText)
            #expect(!fileManager.fileExists(atPath: backup(of: config).path))
        }
    }

    @Test func launchReplacesAnEditedOpenCodePluginAndKeepsTheEdit() throws {
        try withTempHome { _ in
            let plugin = NotifyIntegration.openCode.configURL
            try put("// my edit\n", at: plugin)
            NotifyIntegration.updateConnectedNow()
            #expect(text(plugin) == NotifyIntegration.openCodePlugin)
            #expect(plugin.lastPathComponent == "nunsseop.js")
            #expect(text(backup(of: plugin)) == "// my edit\n")
        }
    }
}
