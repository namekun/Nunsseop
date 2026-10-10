import Foundation
import Testing
@testable import Nunsseop

struct AgentHookEventTests {
    @Test func eventsAsTheCountReadsThem() {
        #expect(AgentHook.action(event: "UserPromptSubmit", type: nil) == .working)
        #expect(AgentHook.action(event: "Stop", type: nil) == .finished)
        #expect(AgentHook.action(event: "StopFailure", type: nil) == .finished)
        #expect(AgentHook.action(event: "SessionEnd", type: nil) == .remove)
        for type in ["permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input"] {
            #expect(AgentHook.action(event: "Notification", type: type) == .needsInput)
        }
        #expect(AgentHook.action(event: "Notification", type: "idle_prompt") == .idle)
        #expect(AgentHook.action(event: "Notification", type: "elicitation_response") == .working)
        #expect(AgentHook.action(event: "Notification", type: "elicitation_complete") == .working)
        // Everything else says nothing about work.
        for type in ["auth_success", "agent_completed", "quota_low", "", nil] {
            #expect(AgentHook.action(event: "Notification", type: type) == nil)
        }
        #expect(AgentHook.action(event: "SubagentStop", type: nil) == nil)
        #expect(AgentHook.action(event: "PostToolUse", type: nil) == nil)
        // A type means something only on a Notification.
        #expect(AgentHook.action(event: "Stop", type: "idle_prompt") == .finished)
    }

    @Test func headersBecomeAnEvent() {
        let headers = ["x-session": "3f2a-B_9", "x-event": "Notification", "x-type": "permission_prompt",
                       "x-app": "com.apple.Terminal", "x-herdr": "1"]
        #expect(AgentHook.event(headers: headers)
                == AgentEvent(session: "3f2a-B_9", action: .needsInput, app: "com.apple.Terminal", inHerdr: true))
        let plain = AgentHook.event(headers: ["x-session": "s", "x-event": "Stop"])
        #expect(plain == AgentEvent(session: "s", action: .finished, app: nil, inHerdr: false))
        // The hook sends empty values for what it doesn't have.
        #expect(AgentHook.event(headers: ["x-session": "s", "x-event": "Stop", "x-app": "", "x-herdr": ""])?.app == nil)
    }

    @Test func headersOutsideTheWhitelistAreRefused() {
        let ok = ["x-session": "s", "x-event": "Stop"]
        #expect(AgentHook.event(headers: ok) != nil)
        #expect(AgentHook.event(headers: ["x-event": "Stop"]) == nil)
        #expect(AgentHook.event(headers: ["x-session": "", "x-event": "Stop"]) == nil)
        #expect(AgentHook.event(headers: ["x-session": "a\nb", "x-event": "Stop"]) == nil)
        #expect(AgentHook.event(headers: ["x-session": "a.b", "x-event": "Stop"]) == nil)
        #expect(AgentHook.event(headers: ["x-session": String(repeating: "a", count: 64), "x-event": "Stop"]) != nil)
        #expect(AgentHook.event(headers: ["x-session": String(repeating: "a", count: 65), "x-event": "Stop"]) == nil)
        #expect(AgentHook.event(headers: ["x-session": "s", "x-event": "Stop\n"]) == nil)
        #expect(AgentHook.event(headers: ok.merging(["x-app": "com.x\nevil"]) { $1 })?.app == nil)
        #expect(AgentHook.event(headers: ["x-session": "s", "x-event": "Nope"]) == nil)
    }

    @Test func aBackgroundSessionIsNeitherInHerdrNorInAnApp() {
        let headers = ["x-session": "s", "x-event": "UserPromptSubmit", "x-app": "com.apple.Terminal", "x-herdr": "1"]
        #expect(AgentHook.event(headers: headers.merging(["x-background": "1"]) { $1 })
                == AgentEvent(session: "s", action: .working, app: nil, inHerdr: false))
        #expect(AgentHook.event(headers: headers.merging(["x-background": ""]) { $1 })
                == AgentEvent(session: "s", action: .working, app: "com.apple.Terminal", inHerdr: true))
        #expect(NotifyServer.agentHookCommand.contains("X-Background: ${CLAUDE_JOB_DIR:+1}"))
    }

    @Test func subagentCallsAreDropped() {
        #expect(AgentHook.event(headers: ["x-session": "s", "x-event": "Stop", "x-subagent": "agent-1"]) == nil)
        #expect(AgentHook.event(headers: ["x-session": "s", "x-event": "Stop", "x-subagent": ""]) != nil)
    }

    @Test func hookCommandSendsOnlyIdsAndNames() {
        let command = NotifyServer.agentHookCommand
        #expect(command.contains("127.0.0.1:\(NotifyServer.port)/agent"))
        #expect(command.contains("-m 1") && command.contains("--connect-timeout 1"))
        #expect(command.contains(">/dev/null 2>&1 || true"))
        for field in ["session_id", "hook_event_name", "notification_type", "agent_id"] { #expect(command.contains(field)) }
        for private_ in ["prompt", "last_assistant_message", "cwd", "transcript_path", "--data-binary"] {
            #expect(!command.contains(private_))
        }
    }
}

@MainActor
struct AgentHooksTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func make(on: Bool = true, herdr: Bool = false, frontmost: String? = nil)
        -> (hooks: AgentHooks, board: AgentBoard) {
        let board = AgentBoard()
        return (AgentHooks(board: board, isOn: { on }, watchesHerdr: { herdr }, frontmostApp: { frontmost }), board)
    }

    private func event(_ session: String, _ action: AgentAction, app: String? = nil, inHerdr: Bool = false) -> AgentEvent {
        AgentEvent(session: session, action: action, app: app, inHerdr: inHerdr)
    }

    @Test func workingExpiresAndEveryEventRefreshesIt() {
        let (hooks, board) = make()
        hooks.apply(event("a", .working), now: start)
        #expect(board.counts == AgentBoard.Counts(working: 1))
        board.recount(now: start.addingTimeInterval(19 * 60))
        #expect(board.counts == AgentBoard.Counts(working: 1))
        board.recount(now: start.addingTimeInterval(20 * 60 + 1))
        #expect(board.counts.isEmpty)

        hooks.apply(event("a", .working), now: start)
        hooks.apply(event("a", .working), now: start.addingTimeInterval(15 * 60))
        board.recount(now: start.addingTimeInterval(30 * 60))
        #expect(board.counts == AgentBoard.Counts(working: 1))
        board.recount(now: start.addingTimeInterval(36 * 60))
        #expect(board.counts.isEmpty)
    }

    @Test func needingInputWaits() {
        let (hooks, board) = make()
        hooks.apply(event("a", .working), now: start)
        hooks.apply(event("a", .needsInput), now: start.addingTimeInterval(5))
        #expect(board.counts == AgentBoard.Counts(waiting: 1))
        board.recount(now: start.addingTimeInterval(21 * 60))
        #expect(board.counts.isEmpty)
        // Answered: the next event of the turn works again.
        hooks.apply(event("a", .needsInput), now: start)
        hooks.apply(event("a", .working), now: start.addingTimeInterval(5))
        #expect(board.counts == AgentBoard.Counts(working: 1))
    }

    @Test func finishedWaitsForTenMinutes() {
        let (hooks, board) = make()
        hooks.apply(event("a", .working), now: start)
        hooks.apply(event("a", .finished, app: "com.apple.Terminal"), now: start.addingTimeInterval(30))
        #expect(board.counts == AgentBoard.Counts(waiting: 1))
        board.recount(now: start.addingTimeInterval(30 + 9 * 60))
        #expect(board.counts == AgentBoard.Counts(waiting: 1))
        board.recount(now: start.addingTimeInterval(30 + 10 * 60 + 1))
        #expect(board.counts.isEmpty)
        // The next prompt takes the hand away.
        hooks.apply(event("a", .finished), now: start)
        hooks.apply(event("a", .working), now: start.addingTimeInterval(60))
        #expect(board.counts == AgentBoard.Counts(working: 1))
    }

    @Test func finishedInTheFrontAppIsAlreadySeen() {
        let (hooks, board) = make(frontmost: "com.apple.Terminal")
        hooks.apply(event("a", .working, app: "com.apple.Terminal"), now: start)
        hooks.apply(event("a", .finished, app: "com.apple.Terminal"), now: start)
        #expect(board.counts.isEmpty)
        hooks.apply(event("b", .finished, app: "com.mitchellh.ghostty"), now: start)
        #expect(board.counts == AgentBoard.Counts(waiting: 1))
        // No app known: can't tell, so it waits.
        hooks.apply(event("c", .finished), now: start)
        #expect(board.counts == AgentBoard.Counts(waiting: 2))
    }

    @Test func idleClearsEverythingButAFinishedHand() {
        let (hooks, board) = make()
        hooks.apply(event("a", .working), now: start)
        hooks.apply(event("a", .idle), now: start)
        #expect(board.counts.isEmpty)
        hooks.apply(event("a", .finished), now: start)
        hooks.apply(event("a", .idle), now: start)
        #expect(board.counts == AgentBoard.Counts(waiting: 1))
        // Esc or a rejected permission sends no Stop, but the idle prompt means nothing is asked any more.
        hooks.apply(event("b", .needsInput), now: start)
        #expect(board.counts == AgentBoard.Counts(waiting: 2))
        hooks.apply(event("b", .idle), now: start)
        #expect(board.counts == AgentBoard.Counts(waiting: 1))
        // An idle prompt for a session never heard of adds nothing.
        hooks.apply(event("c", .idle), now: start)
        #expect(board.counts == AgentBoard.Counts(waiting: 1))
    }

    @Test func endedSessionsGoAndEachCountsOnce() {
        let (hooks, board) = make()
        hooks.apply(event("a", .working), now: start)
        hooks.apply(event("b", .working), now: start)
        hooks.apply(event("b", .working), now: start)
        hooks.apply(event("c", .needsInput), now: start)
        #expect(board.counts == AgentBoard.Counts(working: 2, waiting: 1))
        hooks.apply(event("a", .remove), now: start)
        #expect(board.counts == AgentBoard.Counts(working: 1, waiting: 1))
        hooks.apply(event("zzz", .remove), now: start)
        #expect(board.counts == AgentBoard.Counts(working: 1, waiting: 1))
    }

    @Test func herdrPanesAreLeftToHerdr() {
        let (watching, watchingBoard) = make(herdr: true)
        watching.apply(event("a", .working, inHerdr: true), now: start)
        #expect(watchingBoard.counts.isEmpty)
        watching.apply(event("b", .working), now: start)
        #expect(watchingBoard.counts == AgentBoard.Counts(working: 1))

        let (alone, aloneBoard) = make(herdr: false)
        alone.apply(event("a", .working, inHerdr: true), now: start)
        #expect(aloneBoard.counts == AgentBoard.Counts(working: 1))
    }

    @Test func nothingCountsWhileTheCountIsHidden() {
        let (hooks, board) = make(on: false)
        hooks.apply(event("a", .working), now: start)
        #expect(board.counts.isEmpty)
    }

    @Test func resetForgetsEverySession() {
        let (hooks, board) = make()
        hooks.apply(event("a", .working), now: start)
        hooks.reset()
        #expect(board.counts.isEmpty)
        // Not a stale entry coming back with the next event.
        hooks.apply(event("b", .working), now: start)
        #expect(board.counts == AgentBoard.Counts(working: 1))
    }

    @Test func hooksAreASourceOfTheirOwn() {
        let (hooks, board) = make()
        board.replace(source: "herdr:a", with: ["p": .working])
        hooks.apply(event("a", .working), now: start)
        #expect(board.counts == AgentBoard.Counts(working: 2))
        hooks.reset()
        #expect(board.counts == AgentBoard.Counts(working: 1))
    }
}
