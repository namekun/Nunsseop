import SwiftUI

/// What coding agents are doing right now, gathered from every source that can tell (herdr first; Muxy, cmux and
/// hooks to follow), so the closed notch can say how many are working and how many wait for you. A live count is
/// something only the notch can show at a glance; Notification Center keeps what happened, not what's happening.
@MainActor
final class AgentBoard: ObservableObject {
    enum State: Equatable {
        /// Running a turn.
        case working
        /// Asking for input, or finished and not yet looked at.
        case waiting
        /// Open and used recently, but neither working nor waiting. Listed in the Agents tab, never counted.
        case idle
    }

    /// How long after its last use an open session stays listed.
    nonisolated static let recentWindow: TimeInterval = 3 * 60 * 60

    struct Counts: Equatable {
        var working = 0
        var waiting = 0
        var isEmpty: Bool { working == 0 && waiting == 0 }

        init(working: Int = 0, waiting: Int = 0) {
            self.working = working
            self.waiting = waiting
        }

        init<S: Sequence>(_ states: S) where S.Element == State {
            for state in states {
                switch state {
                case .working: working += 1
                case .waiting: waiting += 1
                case .idle: break
                }
            }
        }
    }

    /// An agent's state, and when it stops counting (a finished one that nobody looked at, say). The rest is for the
    /// Agents tab, and what a source doesn't know stays nil.
    struct Agent: Equatable {
        var state: State
        var expiresAt: Date? = nil
        /// When it entered this state.
        var since: Date? = nil
        /// Waiting because its turn ended, as opposed to asking for input.
        var finished = false
        /// The tool's `AgentKind` name for the hooks, the agent's own name in a herdr pane.
        var tool: String? = nil
        /// The bundle id of the terminal app it runs in.
        var app: String? = nil
        /// A herdr pane and the socket of its session.
        var pane: String? = nil
        var socket: String? = nil
        /// Only herdr says the folder; the hooks send none.
        var cwd: String? = nil
        /// The tool's own session id, to find its transcript.
        var session: String? = nil
        /// From then on the agent is idle: a finished hand nobody looked at, a turn that sent nothing for too long.
        var idleFrom: Date? = nil
        /// Where the terminal it runs in takes input from outside, when it has an API for that.
        var input: AgentInput? = nil
        /// The tool's process, which `input` is checked against: only a session whose process is in that terminal is typed into.
        var pid: Int32? = nil
        /// Whether the hook said it runs in tmux, zellij or screen: the terminal around it isn't where its text would go.
        var inMultiplexer = false
        /// How many background tasks (subagents, shell commands) still run after the turn's own end, which keeps the agent working: "Background · 3 tasks".
        var background = 0
        /// The agent's own name for the session, when its source keeps one (Paseo's title); it comes before the transcript's.
        var title: String? = nil
        /// The model the source says it runs; the transcript's, when it has one, is more exact.
        var model: String? = nil
        /// The program that runs it for the tool, named on its row (Paseo).
        var host: String? = nil

        /// Set by `effective(at:)`: asking for input when last told, so its dialog may be open still, however long ago. Going idle
        /// by the clock doesn't close a dialog; only a later event does.
        var promptMayBeOpen = false

        /// The agent as it is at `now`: idle once `idleFrom` has passed.
        func effective(at now: Date) -> Agent {
            var agent = self
            agent.promptMayBeOpen = state == .waiting && !finished
            guard state != .idle, let idleFrom, idleFrom <= now else { return agent }
            (agent.state, agent.finished, agent.since, agent.background) = (.idle, false, idleFrom, 0)
            return agent
        }
    }

    /// A listed agent with where it came from.
    struct Entry: Equatable {
        let source: String
        let id: String
        let agent: Agent
        var key: String { "\(source)|\(id)" }
    }

    /// Each source's agents by their id there (a herdr pane, say). A source replaces its whole list at once.
    private var bySource: [String: [String: Agent]] = [:]
    @Published private(set) var counts = Counts()
    /// Changes whenever any source's list does, for what lists the agents rather than counts them.
    @Published private(set) var revision = 0
    private var expiry: Timer?

    init() {
        #if DEBUG
        // Debug: --demo-agents fills the closed notch and the Agents tab for checking them.
        if CommandLine.arguments.contains("--demo-agents") {
            replace(source: "demo", with: Self.demoAgents())
        }
        #endif
    }

    /// The bundle id of the terminal app a session runs in, when a source that reports it knows the session.
    func app(ofSession id: String, now: Date = .now) -> String? {
        entries(now: now).first { $0.agent.session == id && $0.agent.app != nil }?.agent.app
    }

    /// Everything listed that hasn't expired, as it is at `now`.
    func entries(now: Date = .now) -> [Entry] {
        listed(at: now).map { Entry(source: $0.source, id: $0.id, agent: $0.agent.effective(at: now)) }
    }

    /// What every source lists that hasn't expired. A session Muxy lists that a hook also reports (the hook's `input` names the same
    /// Muxy session) is listed once, as the hook has it: it knows more of the session, and the provider's own events keep it current.
    /// A hook that predates the terminal variables names no terminal, so it can't be matched to a session: it takes the place of one
    /// Muxy row of the same tool, since the hook of a tool that Muxy lists is more likely in Muxy than elsewhere. At most one each.
    private func listed(at now: Date) -> [(source: String, id: String, agent: Agent)] {
        let live = withoutHookRowsOfPaseo(at: now)
        let hooked = Set(live.compactMap { entry -> String? in
            if entry.source != MuxyActivityWatcher.source, case .muxy(let session)? = entry.agent.input { session } else { nil }
        })
        var unplaced = live.filter { $0.source.hasPrefix("hooks:") && $0.agent.input == nil && ($0.agent.app == nil || $0.agent.app == Muxy.bundleID) }
            .sorted { ($0.source, $0.id) < ($1.source, $1.id) }
        var hidden = hooked
        for row in live.filter({ $0.source == MuxyActivityWatcher.source && !hooked.contains($0.id) }).sorted(by: { $0.id < $1.id }) {
            guard let tool = row.agent.tool, let index = unplaced.firstIndex(where: { $0.agent.tool == tool }) else { continue }
            unplaced.remove(at: index)
            hidden.insert(row.id)
        }
        return hidden.isEmpty ? live : live.filter { !($0.source == MuxyActivityWatcher.source && hidden.contains($0.id)) }
    }

    /// The agents that haven't expired. A session Paseo runs may report through the tools' hooks as well (a Claude Code SDK session
    /// loads the user's settings), and the hooks' row is dropped for Paseo's own, the one that can be sent to and answered. Except that
    /// a hook row that works while Paseo's row doesn't is kept: the same session resumed in a terminal (`claude --resume` keeps the
    /// id) is working there, and Paseo's idle row must not hide it.
    private func withoutHookRowsOfPaseo(at now: Date) -> [(source: String, id: String, agent: Agent)] {
        let all = bySource.flatMap { source, agents in agents.map { (source: source, id: $0.key, agent: $0.value) } }
            .filter { $0.agent.expiresAt.map { $0 > now } ?? true }
        var claimed: [String: Bool] = [:]
        for row in all where row.source == Paseo.source {
            guard let session = row.agent.session?.lowercased() else { continue }
            let agent = row.agent.effective(at: now)
            claimed[session] = claimed[session] == true || agent.state == .working || (agent.state == .waiting && !agent.finished)
        }
        guard !claimed.isEmpty else { return all }
        return all.filter { row in
            guard row.source != Paseo.source, let session = row.agent.session?.lowercased(), let paseoActive = claimed[session] else { return true }
            return !paseoActive && row.agent.effective(at: now).state == .working
        }
    }

    /// Everything one source knows now; agents it no longer lists are gone.
    func replace(source: String, with agents: [String: Agent], now: Date = .now) {
        bySource[source] = agents.isEmpty ? nil : agents
        recount(now: now)
    }

    func replace(source: String, with states: [String: State]) {
        replace(source: source, with: states.mapValues { Agent(state: $0) })
    }

    func clear(source: String) { replace(source: source, with: [String: Agent]()) }

    /// Counts the agents that haven't expired, and wakes up when the next one expires or turns idle.
    func recount(now: Date = .now) {
        let live = listed(at: now).map(\.agent)
        let new = Counts(live.map { $0.effective(at: now).state })
        if new != counts { counts = new }
        revision &+= 1
        expiry?.invalidate()
        expiry = nil
        guard let next = live.flatMap({ [$0.expiresAt, $0.idleFrom] }).compactMap({ $0 }).filter({ $0 > now }).min() else { return }
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.recount() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        expiry = timer
    }
}

extension Herdr {
    /// How long a finished pane nobody looked at in herdr keeps counting as waiting; past it the hand goes down even
    /// for someone who never opens herdr.
    static let doneWindow: TimeInterval = 10 * 60

    /// A pane's state and since when it has been in it, with what herdr says of the agent in it.
    struct PaneState: Equatable {
        let status: String
        let since: Date
        var agent: String? = nil
        var cwd: String? = nil
        var session: String? = nil
    }

    /// The board's agents for a session's panes (`socket` is that session's). A `done` pane waits for you until
    /// `doneWindow` after it finished, then sits idle, as an idle pane with an agent in it does; both stay listed for
    /// `AgentBoard.recentWindow`.
    static func boardAgents(_ panes: [String: PaneState], socket: String? = nil) -> [String: AgentBoard.Agent] {
        var agents: [String: AgentBoard.Agent] = [:]
        for (id, pane) in panes {
            let done = pane.status == "done"
            let state: AgentBoard.State
            if let counted = boardState(pane.status) {
                state = counted
            } else if pane.status == "idle", pane.agent?.isEmpty == false {
                state = .idle
            } else {
                continue
            }
            let listed = done || state == .idle
            agents[id] = AgentBoard.Agent(
                state: state, expiresAt: listed ? pane.since.addingTimeInterval(AgentBoard.recentWindow) : nil,
                since: pane.since, finished: done, tool: pane.agent, pane: id, socket: socket, cwd: pane.cwd,
                session: pane.session, idleFrom: done ? pane.since.addingTimeInterval(doneWindow) : nil,
                input: socket.map { .herdr(pane: id, socket: $0) })
        }
        return agents
    }

    /// herdr's pane states as the board counts them. `done` is finished but not yet seen in herdr, so it waits for
    /// the user like `blocked` (for a while: see `doneWindow`); idle and unknown panes aren't agents at work, and an
    /// idle one is only listed (see `boardAgents`).
    static func boardState(_ status: String) -> AgentBoard.State? {
        switch status {
        case "working": .working
        case "blocked", "done": .waiting
        default: nil
        }
    }

    static func boardStates(_ panes: [String: String]) -> [String: AgentBoard.State] {
        panes.compactMapValues(boardState)
    }
}

#if DEBUG
extension AgentBoard {
    /// Two Claude Code sessions working, one asking for input, one idle and a Codex session working. "a" and "c" are in (made-up) Muxy
    /// sessions the demo's fakes vouch for (see `demoTargets`), so the Message button can be seen working ("a") and refused ("c": a
    /// prompt is open); the others have no terminal, so it refuses with its other reasons.
    static func demoAgents(now: Date = .now) -> [String: Agent] {
        [
            "a": Agent(state: .working, since: now.addingTimeInterval(-190), tool: "claude", cwd: "/Users/demo/Projects/nunsseop", input: .muxy("demo-a"), pid: 9_101),
            "b": Agent(state: .working, since: now.addingTimeInterval(-45), tool: "claude", cwd: "/Users/demo/Projects/site"),
            "c": Agent(state: .waiting, since: now.addingTimeInterval(-720), tool: "claude", cwd: "/Users/demo/Projects/api-server", input: .muxy("demo-c"), pid: 9_201),
            "d": Agent(state: .working, since: now.addingTimeInterval(-3_900), tool: "codex", cwd: "/Users/demo/Projects/ios-app"),
            "e": Agent(state: .idle, since: now.addingTimeInterval(-2_400), tool: "claude", cwd: "/Users/demo/Projects/docs"),
        ]
    }

    /// The demo's process tree: each of the two Muxy sessions has the shell and Muxy's server above it.
    static let demoTargets = AgentTargetCheck(
        processes: ProcessTable { pid in
            switch pid {
            case 9_101, 9_201: ProcessRecord(parent: pid + 1, executable: "/usr/local/bin/claude", hasTTY: true)
            case 9_102, 9_202: ProcessRecord(parent: pid + 1, executable: "/bin/zsh", hasTTY: true)
            case 9_103, 9_203: ProcessRecord(parent: pid + 1, executable: "/Applications/Muxy.app/Contents/MacOS/muxy-server", hasTTY: false)
            case 9_104, 9_204: ProcessRecord(parent: 1, executable: "/Applications/Muxy.app/Contents/MacOS/muxy-app", hasTTY: false)
            default: nil
            }
        },
        muxyList: { _ in "demo-a\ta\tLive\ttrue\t/tmp\ndemo-c\tc\tLive\ttrue\t/tmp\n" })
    /// The demo never types into a real terminal.
    static let demoSender = AgentSender { _ in .sent }
    static let demoCLIs = TerminalCLIs(muxy: URL(fileURLWithPath: "/demo/muxy"))

    /// What their transcripts would say, by `Entry.key`.
    static let demoEdit = AgentActivity.Edit(path: "Sources/Login.swift", old: """
        func signIn(_ user: User) async throws {
            let token = try await api.login(user.name, user.password)
            store.save(token)
            session.begin(with: token)
        }
        """, new: """
        func signIn(_ user: User) async throws {
            let token = try await api.login(user.credentials)
            guard token.isValid else { throw AuthError.expired }
            try keychain.save(token, for: user.id)
            session.begin(with: token)
        }
        """)

    static let demoTranscripts: [String: AgentTranscript] = [
        "demo|a": AgentTranscript(model: "claude-opus-5-5", tokens: 84_300, name: "Agents tab",
                                  activity: AgentActivity(verb: .edit, subject: "Sources/Login.swift", edit: demoEdit), edits: [demoEdit]),
        "demo|b": AgentTranscript(model: "claude-sonnet-5-5", tokens: 31_900, mode: .plan),
        "demo|c": AgentTranscript(model: "claude-opus-5-5", tokens: 142_000),
        "demo|d": AgentTranscript(model: "gpt-5.6", tokens: 19_500, activity: AgentActivity(verb: .run, subject: "swift test --filter Auth")),
        "demo|e": AgentTranscript(model: "claude-sonnet-5-5", tokens: 12_400),
    ]

    /// A named Claude Code conversation and a Codex one that is only known by its folder.
    static func demoRecent(now: Date = .now) -> [RecentConversation] {
        [
            RecentConversation(kind: .claude, session: "5f0c2d1e-0000-4000-8000-000000000001", cwd: "/Users/demo/Projects/nunsseop",
                               modified: now.addingTimeInterval(-3 * 3_600), name: "Resume list"),
            RecentConversation(kind: .codex, session: "01a130c4-3953-7f71-bc99-b8a6d37a5338", cwd: "/Users/demo/Projects/ios-app",
                               modified: now.addingTimeInterval(-27 * 3_600)),
        ]
    }
}
#endif
