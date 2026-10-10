import Foundation
import Testing
@testable import Nunsseop

struct JSONHookTests {
    @Test func addsAndRemovesHookInEmptySettings() throws {
        let settings = try JSONHook.adding(NotifyServer.hookCommand, to: [:])
        #expect(JSONHook.isInstalled(in: settings))
        #expect(!JSONHook.isInstalled(in: [:]))
        #expect(JSONHook.removing(from: settings).isEmpty)
    }

    @Test func keepsOtherHooksAndSettings() throws {
        let other: [String: Any] = ["hooks": [["type": "command", "command": "other.sh"]]]
        let settings = try JSONHook.adding(NotifyServer.hookCommand(title: "Gemini CLI"), to: [
            "model": "opus",
            "hooks": ["Notification": [other], "Stop": [other]],
        ])
        let hooks = try #require(settings["hooks"] as? [String: Any])
        #expect(settings["model"] as? String == "opus")
        #expect((hooks["Notification"] as? [[String: Any]])?.count == 2)
        #expect(JSONHook.isInstalled(in: settings))

        let removed = JSONHook.removing(from: settings)
        let remaining = try #require(removed["hooks"] as? [String: Any])
        #expect((remaining["Notification"] as? [[String: Any]])?.count == 1)
        #expect((remaining["Stop"] as? [[String: Any]])?.count == 1)
        #expect(!JSONHook.isInstalled(in: removed))
    }

    @Test func refusesUnexpectedShapes() {
        #expect(throws: NotifyIntegration.IntegrationError.self) { try JSONHook.adding("x", to: ["hooks": "x"]) }
        #expect(throws: NotifyIntegration.IntegrationError.self) {
            try JSONHook.adding("x", to: ["hooks": ["Notification": "x"]])
        }
    }
}

struct AgentHookInstallTests {
    private let claude = NotifyIntegration.claudeCode.hooks
    private let events = ["Notification", "UserPromptSubmit", "Stop", "StopFailure", "SessionEnd"]

    private func commands(_ settings: [String: Any], _ event: String) -> [[String]] {
        (((settings["hooks"] as? [String: Any])?[event] as? [[String: Any]]) ?? []).map { group in
            ((group["hooks"] as? [[String: Any]]) ?? []).compactMap { $0["command"] as? String }
        }
    }

    @Test func claudeCodeGetsTheNoticeHookAndTheAgentHooks() throws {
        let notice = NotifyServer.hookCommand(title: "Claude Code"), agent = NotifyServer.agentHookCommand
        // The notice hook, then the agent hook under Notification and the four events.
        #expect(claude.count == 6)
        let settings = try JSONHook.adding(claude, to: [:])
        #expect(JSONHook.isInstalled(in: settings))
        #expect(JSONHook.isCurrent(claude, in: settings))
        #expect(commands(settings, "Notification") == [[notice], [agent]])
        for event in events.dropFirst() { #expect(commands(settings, event) == [[agent]]) }
        #expect(JSONHook.removing(from: settings).isEmpty)
    }

    @Test func geminiKeepsTheNoticeHookOnly() {
        let gemini = NotifyIntegration.gemini.hooks
        #expect(gemini.count == 1)
        #expect(gemini[0].event == "Notification" && gemini[0].command == NotifyServer.hookCommand(title: "Gemini CLI"))
    }

    @Test func aNoticeOnlyInstallGainsTheAgentHooksOnce() throws {
        let old = try JSONHook.adding(NotifyServer.hookCommand(title: "Claude Code"), to: ["model": "opus"])
        #expect(JSONHook.isInstalled(in: old))
        #expect(!JSONHook.isCurrent(claude, in: old))
        let updated = try #require(try JSONHook.updating(claude, in: old))
        #expect(JSONHook.isCurrent(claude, in: updated))
        #expect(updated["model"] as? String == "opus")
        #expect(commands(updated, "Notification").count == 2)
        #expect(try JSONHook.updating(claude, in: updated) == nil)
    }

    @Test func aMissingEventIsAddedBack() throws {
        var settings = try JSONHook.adding(claude, to: [:])
        var events = try #require(settings["hooks"] as? [String: Any])
        events["Stop"] = nil
        settings["hooks"] = events
        #expect(!JSONHook.isCurrent(claude, in: settings))
        let updated = try #require(try JSONHook.updating(claude, in: settings))
        #expect(commands(updated, "Stop") == [[NotifyServer.agentHookCommand]])
        #expect(commands(updated, "Notification").count == 2)
    }

    @Test func theUsersOwnHooksSurviveUpdatingAndRemoving() throws {
        let mine: [String: Any] = ["matcher": "x", "hooks": [["type": "command", "command": "mine.sh"],
                                                             ["type": "command", "command": NotifyServer.agentHookCommand]]]
        let own: [String: Any] = ["hooks": [["type": "command", "command": "own.sh"]]]
        let settings: [String: Any] = ["hooks": ["Stop": [mine], "UserPromptSubmit": [own], "PreToolUse": [own]]]
        let updated = try #require(try JSONHook.updating(claude, in: settings))
        #expect(JSONHook.isCurrent(claude, in: updated))
        #expect(commands(updated, "Stop") == [["mine.sh"], [NotifyServer.agentHookCommand]])
        #expect(commands(updated, "UserPromptSubmit") == [["own.sh"], [NotifyServer.agentHookCommand]])
        let removed = JSONHook.removing(from: updated)
        #expect(commands(removed, "Stop") == [["mine.sh"]])
        #expect(commands(removed, "UserPromptSubmit") == [["own.sh"]])
        #expect(commands(removed, "PreToolUse") == [["own.sh"]])
        #expect((removed["hooks"] as? [String: Any])?["Notification"] == nil)
        #expect((removed["hooks"] as? [String: Any])?["SessionEnd"] == nil)
        #expect(!JSONHook.isInstalled(in: removed))
    }

    @Test func removingLeavesSettingsWithoutOurHooksAsTheyWere() {
        let settings: [String: Any] = ["hooks": [String: Any](), "model": "opus"]
        #expect((JSONHook.removing(from: settings)["hooks"] as? [String: Any])?.isEmpty == true)
    }

    @Test func onlyTheNoticeHookMakesAToolConnected() throws {
        let agentOnly = try JSONHook.adding([("Stop", NotifyServer.agentHookCommand), ("Notification", NotifyServer.agentHookCommand)], to: [:])
        #expect(!JSONHook.isInstalled(in: agentOnly))
        // Still ours, so that Disconnect and the launch-time update can clear what a deleted notice hook left.
        #expect(JSONHook.holdsAny(in: agentOnly))
        #expect(JSONHook.removing(from: agentOnly).isEmpty)
        #expect(!JSONHook.holdsAny(in: JSONHook.removing(from: agentOnly)))
        #expect(!JSONHook.holdsAny(in: ["hooks": ["Stop": [["hooks": [["type": "command", "command": "mine.sh"]]]]]]))
    }

    @Test func aPastedScriptCommandOutsideNotificationIsNotOurs() throws {
        let pasted: [String: Any] = ["hooks": [["type": "command", "command": NotifyServer.scriptCommand]]]
        let settings: [String: Any] = ["hooks": ["Stop": [pasted], "PostToolUse": [pasted]]]
        #expect(!JSONHook.holdsAny(in: settings))
        let updated = try #require(try JSONHook.updating(claude, in: settings))
        #expect(JSONHook.isCurrent(claude, in: updated))
        #expect(commands(updated, "Stop") == [[NotifyServer.scriptCommand], [NotifyServer.agentHookCommand]])
        #expect(commands(updated, "PostToolUse") == [[NotifyServer.scriptCommand]])
        let removed = JSONHook.removing(from: updated)
        #expect(commands(removed, "Stop") == [[NotifyServer.scriptCommand]])
        #expect(commands(removed, "PostToolUse") == [[NotifyServer.scriptCommand]])
        // Under Notification the notice command is ours, as it always was.
        let notice = try JSONHook.adding(NotifyServer.hookCommand(title: "Claude Code"), to: [:])
        #expect(JSONHook.removing(from: notice).isEmpty)
    }
}

struct CodexNotifyTests {
    let script = CodexNotify.scriptURL.path

    @Test func parsesStringArrays() {
        #expect(CodexNotify.parseStringArray(#"["a", 'b c', "d\"e"]"#) == ["a", "b c", "d\"e"])
        #expect(CodexNotify.parseStringArray(#"["a",] # note"#) == ["a"])
        #expect(CodexNotify.parseStringArray("[]") == [])
        #expect(CodexNotify.parseStringArray(#"["a""#) == nil)
        #expect(CodexNotify.parseStringArray(#"["a"] x"#) == nil)
    }

    @Test func wrapsExistingCommandAndRestoresIt() throws {
        let text = "model = \"o3\"\nnotify = [\"/usr/bin/foo\", \"--bar\"]\n\n[tui]\nnotify = true\n"
        let added = try CodexNotify.adding(to: text)
        #expect(added.contains("notify = [\"/bin/sh\", \"\(script)\", \"/usr/bin/foo\", \"--bar\"]"))
        #expect(added.contains("[tui]\nnotify = true"))
        #expect(CodexNotify.isInstalled(in: added))
        #expect(!CodexNotify.isInstalled(in: text))
        #expect(try CodexNotify.removing(from: added) == text)
    }

    @Test func addsLineWhenThereIsNoneAndRemovesIt() throws {
        let text = "model = \"o3\"\n[tui]\nnotify = true\n"
        let added = try CodexNotify.adding(to: text)
        #expect(added.hasPrefix("notify = [\"/bin/sh\", \"\(script)\"]\n"))
        #expect(try CodexNotify.removing(from: added) == text)
    }

    @Test func refusesMultilineArray() {
        #expect(throws: NotifyIntegration.IntegrationError.self) {
            try CodexNotify.adding(to: "notify = [\n  \"foo\",\n]\n")
        }
    }
}
