import Foundation
import Testing
@testable import Nunsseop

struct TerminalAgentParseTests {
    @Test func jsonLinesSplitAcrossChunks() {
        var lines = JSONLines()
        #expect(lines.append(Data("{\"a\":1}\n{\"b\"".utf8)).count == 1)
        let rest = lines.append(Data(":2}\nnot json\n".utf8))
        #expect(rest.count == 1)
        #expect(rest.first?["b"] as? Int == 2)
    }

    @Test func agentNamesMapToConnectedTools() {
        #expect(NotifyIntegration.forAgent("claude") == .claudeCode)
        #expect(NotifyIntegration.forAgent("Claude Code") == .claudeCode)
        #expect(NotifyIntegration.forAgent("codex") == .codex)
        #expect(NotifyIntegration.forAgent("pi") == nil)
        #expect(NotifyIntegration.forAgent(nil) == nil)
    }

    @Test func cmuxCreatedEventAndListLookup() throws {
        let frame: [String: Any] = ["type": "event", "name": "notification.created", "category": "notification",
                                    "payload": ["notification_id": "7ED5F805-CC6F-4B06-9701-AC798F63E209", "title": NSNull()]]
        #expect(Cmux.createdID(in: frame) == "7ED5F805-CC6F-4B06-9701-AC798F63E209")
        #expect(Cmux.createdID(in: ["type": "heartbeat"]) == nil)
        #expect(Cmux.createdID(in: ["type": "event", "name": "notification.read", "payload": ["notification_id": "x"]]) == nil)

        let list = Data("""
        {"notifications":[
          {"id":"7ed5f805-cc6f-4b06-9701-ac798f63e209","title":"Codex","subtitle":"Waiting","body":"Agent needs input","is_read":false},
          {"id":"READ","title":"Old","subtitle":"","body":"","is_read":true}]}
        """.utf8)
        #expect(Cmux.notice("7ED5F805-CC6F-4B06-9701-AC798F63E209", inList: list)
                == Cmux.Notice(title: "Codex", body: "Waiting · Agent needs input", id: "7ed5f805-cc6f-4b06-9701-ac798f63e209"))
        #expect(Cmux.notice("READ", inList: list) == nil)
        #expect(Cmux.notice("missing", inList: list) == nil)
        let wrapped = Data(#"{"result":{"notifications":[{"id":"A","title":"T","subtitle":"","body":"B"}]}}"#.utf8)
        #expect(Cmux.notice("A", inList: wrapped) == Cmux.Notice(title: "T", body: "B", id: "A"))
    }

    @Test func herdrRequestsAndEvents() throws {
        let line = Herdr.subscription("sub", panes: [Herdr.Pane(id: "w1:p1", status: "idle")])
        #expect(line.last == 0x0A)
        let request = try #require(try JSONSerialization.jsonObject(with: line.dropLast()) as? [String: Any])
        #expect(request["method"] as? String == "events.subscribe")
        let subscriptions = (request["params"] as? [String: Any])?["subscriptions"] as? [[String: Any]] ?? []
        #expect(subscriptions.map { $0["type"] as? String } == ["pane.created", "pane.closed", "pane.agent_status_changed"])
        #expect(subscriptions.last?["pane_id"] as? String == "w1:p1")

        let list: [String: Any] = ["id": "list", "result": ["type": "pane_list", "panes": [
            ["pane_id": "w1:p1", "agent_status": "working"], ["pane_id": "w1:p2", "agent_status": "done"]]]]
        #expect(Herdr.panes(in: list) == [Herdr.Pane(id: "w1:p1", status: "working"), Herdr.Pane(id: "w1:p2", status: "done")])
        #expect(Herdr.panes(in: ["id": "list", "error": ["code": "x"]]) == nil)

        #expect(Herdr.event(in: ["event": "pane.closed", "data": ["pane_id": "w1:p2"]]) == .panesChanged)
        let status: [String: Any] = ["event": "pane.agent_status_changed",
                                     "data": ["pane_id": "w1:p1", "workspace_id": "w1", "agent_status": "blocked",
                                              "agent": "claude", "display_agent": "Claude", "title": "fix login"]]
        #expect(Herdr.event(in: status) == .status(pane: "w1:p1", Herdr.Notice(agent: "Claude", status: "blocked", title: "fix login", pane: "w1:p1")))
        #expect(Herdr.event(in: ["id": "sub", "result": ["type": "subscription_started"]]) == nil)
    }

    @Test func herdrFindsNamedSessions() throws {
        let config = URL(fileURLWithPath: "/tmp/nunsseop-test-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: config) }
        for name in ["work", "empty"] {
            try FileManager.default.createDirectory(at: config.appendingPathComponent("sessions/\(name)"), withIntermediateDirectories: true)
        }
        FileManager.default.createFile(atPath: config.appendingPathComponent("sessions/work/herdr.sock").path, contents: nil)
        let sockets = Herdr.sockets(in: config)
        #expect(sockets.map(\.session) == [nil, "work"])
        #expect(sockets.map(\.url.lastPathComponent) == ["herdr.sock", "herdr.sock"])
        #expect(sockets.last?.url.deletingLastPathComponent().lastPathComponent == "work")
    }

    @Test func herdrCatchesChangesBetweenSubscriptions() {
        var states = Herdr.States()
        _ = states.reconcile([Herdr.Pane(id: "a", status: "working"), Herdr.Pane(id: "b", status: "blocked")])
        let missed = states.reconcile([Herdr.Pane(id: "a", status: "done", agent: "Pi"), Herdr.Pane(id: "b", status: "blocked"),
                                       Herdr.Pane(id: "c", status: "done")])
        // "a" finished while nothing listened; "b" didn't change; "c" is new, so its state is only learned.
        #expect(missed.map(\.id) == ["a"])
    }

    @Test func herdrAnnouncesOnlyChangesIntoDoneOrBlocked() {
        var states = Herdr.States()
        #expect(states.reconcile([Herdr.Pane(id: "a", status: "done"), Herdr.Pane(id: "b", status: "working")]).isEmpty)
        let steps = [("a", "done"), ("b", "working"), ("b", "blocked"), ("b", "blocked"), ("b", "working"), ("b", "done"),
                     ("new", "done")].map { states.update(pane: $0.0, to: $0.1) }
        // "a" was already done when listed; a pane created after the list counts.
        #expect(steps == [false, false, true, false, false, true, true])
    }
}

/// The watchers against stand-ins: a herdr socket served by a small Python script, and a `cmux` script.
@MainActor
struct TerminalAgentWatcherTests {
    private func temporary(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/nunsseop-test-\(UUID().uuidString.prefix(8))-\(name)")
    }

    private func waitUntil(_ condition: () -> Bool) async {
        // Up to five seconds, stopping as soon as it holds.
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Serves a herdr socket at `socket` that lists one working pane and then reports it done. With `quietSubscription`,
    /// the pane is done by the time of the second list and the subscription never reports it.
    /// The stand-in server: `kill` stops it and leaves its socket file behind, as a crashed herdr does.
    struct FakeHerdr {
        let server: Process
        let files: [URL]
        func kill() { server.terminate(); server.waitUntilExit() }
        func shutDown() {
            if server.isRunning { kill() }
            files.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }

    private func fakeHerdr(at socket: URL, quietSubscription: Bool = false) async throws -> FakeHerdr {
        let script = temporary("herdr.py")
        try """
        import json, os, socket, sys, threading, time
        path = sys.argv[1]
        quiet = len(sys.argv) > 2
        lists = []
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(path); server.listen(4)
        def serve(conn):
            reader = conn.makefile("r")
            for line in reader:
                request = json.loads(line)
                def send(obj): conn.sendall((json.dumps(obj) + "\\n").encode())
                if request["method"] == "pane.list":
                    lists.append(1)
                    status = "done" if quiet and len(lists) > 1 else "working"
                    send({"id": request["id"], "result": {"type": "pane_list", "panes": [
                        {"pane_id": "w1:p1", "agent_status": status, "display_agent": "Pi", "title": "refactor"}]}})
                elif request["method"] == "events.subscribe":
                    send({"id": request["id"], "result": {"type": "subscription_started"}})
                    time.sleep(0.2)
                    if quiet:
                        time.sleep(5); continue
                    send({"event": "pane.agent_status_changed", "data": {"pane_id": "w1:p1", "workspace_id": "w1",
                          "agent_status": "done", "agent": "pi", "display_agent": "Pi", "title": "refactor"}})
                    time.sleep(5)
        while True:
            conn, _ = server.accept()
            threading.Thread(target=serve, args=(conn,), daemon=True).start()
        """.write(to: script, atomically: true, encoding: .utf8)
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = [script.path, socket.path] + (quietSubscription ? ["quiet"] : [])
        try server.run()
        await waitUntil { FileManager.default.fileExists(atPath: socket.path) }
        return FakeHerdr(server: server, files: [socket, script])
    }

    @Test func herdrWatcherListsSubscribesAndAnnounces() async throws {
        let socket = temporary("herdr.sock")
        let herdr = try await fakeHerdr(at: socket)
        defer { herdr.shutDown() }

        let watcher = HerdrWatcher(socketURL: socket)
        var received: [Herdr.Notice] = []
        watcher.onNotice = { received.append($0) }
        watcher.start()
        defer { watcher.stop() }
        await waitUntil { !received.isEmpty }
        #expect(received == [Herdr.Notice(agent: "Pi", status: "done", title: "refactor", pane: "w1:p1", socket: socket)])
    }

    @Test func herdrPaneStatesReachTheBoard() async throws {
        let config = temporary("config")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: config) }
        let socket = config.appendingPathComponent("herdr.sock")
        let herdr = try await fakeHerdr(at: socket)
        defer { herdr.shutDown() }

        let sessions = HerdrSessions(config: config)
        let board = AgentBoard()
        var seen: [[String: Herdr.PaneState]] = []
        sessions.onStates = { key, panes in
            seen.append(panes)
            board.replace(source: "herdr:\(key)", with: Herdr.boardAgents(panes))
        }
        sessions.start()
        // Listed working, then the subscription reports it done.
        await waitUntil { seen.contains { $0["w1:p1"]?.status == "done" } }
        #expect(seen.contains { $0["w1:p1"]?.status == "working" })
        #expect(board.counts == AgentBoard.Counts(working: 0, waiting: 1))
        // The time it finished is when it turned done, not when it was first listed.
        let working = try #require(seen.first { $0["w1:p1"]?.status == "working" }?["w1:p1"])
        let done = try #require(seen.first { $0["w1:p1"]?.status == "done" }?["w1:p1"])
        #expect(done.since > working.since)
        // Stopping forgets the session's panes.
        sessions.stop()
        #expect(seen.last == [:])
        board.replace(source: "herdr:\(socket.path)", with: Herdr.boardAgents(seen.last ?? [:]))
        #expect(board.counts.isEmpty)
    }

    @Test func statesOfACrashedHerdrDoNotLinger() async throws {
        let socket = temporary("herdr.sock")
        let herdr = try await fakeHerdr(at: socket)
        defer { herdr.shutDown() }
        let watcher = HerdrWatcher(socketURL: socket, retryInterval: 0.2)
        var seen: [[String: Herdr.PaneState]] = []
        watcher.onStates = { seen.append($0) }
        watcher.start()
        defer { watcher.stop() }
        await waitUntil { seen.last?["w1:p1"] != nil }
        #expect(seen.last?["w1:p1"] != nil)
        // herdr dies and leaves its socket file: every reconnect now fails or waits.
        herdr.kill()
        #expect(FileManager.default.fileExists(atPath: socket.path))
        await waitUntil { seen.last == [:] }
        #expect(seen.last == [:])
    }

    @Test func herdrCatchesUpWhatChangedBeforeTheSubscriptionStarted() async throws {
        let socket = temporary("herdr.sock")
        let herdr = try await fakeHerdr(at: socket, quietSubscription: true)
        defer { herdr.shutDown() }
        let watcher = HerdrWatcher(socketURL: socket)
        var received: [Herdr.Notice] = []
        watcher.onNotice = { received.append($0) }
        watcher.start()
        defer { watcher.stop() }
        await waitUntil { !received.isEmpty }
        #expect(received == [Herdr.Notice(agent: "Pi", status: "done", title: "refactor", pane: "w1:p1", socket: socket)])
    }

    @Test func herdrSessionsTellWhichSessionANoticeCameFrom() async throws {
        let config = temporary("config")
        try FileManager.default.createDirectory(at: config.appendingPathComponent("sessions/work"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: config) }
        let herdr = try await fakeHerdr(at: config.appendingPathComponent("sessions/work/herdr.sock"))
        defer { herdr.shutDown() }

        let sessions = HerdrSessions(config: config)
        var received: [(Herdr.Notice, String?)] = []
        sessions.onNotice = { received.append(($0, $1)) }
        sessions.start()
        defer { sessions.stop() }
        await waitUntil { !received.isEmpty }
        #expect(received.map(\.0) == [Herdr.Notice(agent: "Pi", status: "done", title: "refactor", pane: "w1:p1",
                                                    socket: config.appendingPathComponent("sessions/work/herdr.sock"))])
        #expect(received.map(\.1) == ["work"])
    }

    @Test func cmuxRetriesOnceAfterBeingTurnedOffAndOnWhileMissing() async throws {
        // Against one started once, under the same load: turning it off and on must not add a second retry chain.
        let toggled = CmuxWatcher(findCLI: { nil }, retryDelay: 0.1)
        let control = CmuxWatcher(findCLI: { nil }, retryDelay: 0.1)
        toggled.start()
        toggled.stop()
        toggled.start()
        control.start()
        defer { toggled.stop(); control.stop() }
        try await Task.sleep(for: .milliseconds(1500))
        // Other tests can keep the main actor busy, so only that a retry happened is assumed.
        #expect(control.launches >= 2)
        // The toggled one has its extra first start; a second chain would roughly double it.
        #expect(toggled.launches <= control.launches + 2, "toggled \(toggled.launches), control \(control.launches)")
    }

    @Test func cmuxFoundLaterIsUsed() async throws {
        var installed: URL?
        let watcher = CmuxWatcher(findCLI: { installed }, retryDelay: 0.2)
        watcher.start()
        defer { watcher.stop() }
        let cli = temporary("cmux")
        try "#!/bin/sh\nsleep 30\n".write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        defer { try? FileManager.default.removeItem(at: cli) }
        installed = cli
        let before = watcher.launches
        try await Task.sleep(for: .milliseconds(700))
        // Found on the next retry, then running: no more attempts.
        #expect(watcher.launches == before + 1)
    }

    @Test func cmuxWatcherLooksUpCreatedNotifications() async throws {
        let cli = temporary("cmux")
        try """
        #!/bin/sh
        if [ "$1" = events ]; then
          echo '{"type":"event","name":"notification.created","category":"notification","payload":{"notification_id":"N1","title":null}}'
          sleep 30
        elif [ "$1" = rpc ]; then
          echo '{"notifications":[{"id":"N1","title":"Pi","subtitle":"","body":"Turn complete","is_read":false}]}'
        fi
        """.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        defer { try? FileManager.default.removeItem(at: cli) }

        let watcher = CmuxWatcher(cli: cli)
        var received: [Cmux.Notice] = []
        watcher.onNotice = { received.append($0) }
        watcher.start()
        defer { watcher.stop() }
        await waitUntil { !received.isEmpty }
        #expect(received == [Cmux.Notice(title: "Pi", body: "Turn complete", id: "N1")])
    }
}

struct TmuxHookTests {
    let script = URL(fileURLWithPath: "/Users/a/Library/Application Support/Nunsseop/terminal-notify.sh")
    let binary = URL(fileURLWithPath: "/opt/homebrew/bin/tmux")

    @Test func hookPassesOnlyKnownValuesAndTheWindowID() {
        #expect(Tmux.hookCommand(script: script, binary: binary)
                == #"run-shell -b "'/Users/a/Library/Application Support/Nunsseop/terminal-notify.sh' tmux-window '/opt/homebrew/bin/tmux' '' #{window_id}""#)
        #expect(Tmux.hookCommand(script: script, binary: binary, socketName: "test")?.contains("'test' #{window_id}") == true)
        // No names, and nothing tmux or sh could expand.
        #expect(Tmux.hookCommand(script: script, binary: binary)?.contains("_name") == false)
        for bad in ["/Users/o'brien/x.sh", "/Users/a/$HOME/x.sh", "/Users/a/#{x}.sh", "/Users/a/\\x.sh"] {
            #expect(Tmux.hookCommand(script: URL(fileURLWithPath: bad), binary: binary) == nil)
        }
        #expect(Tmux.hookCommand(script: script, binary: binary, socketName: "a'b") == nil)
    }

    @Test func recognisesItsOwnHookOnly() throws {
        let command = try #require(Tmux.hookCommand(script: script, binary: binary))
        #expect(Tmux.isHooked("alert-activity\nalert-bell[4775] \(command)\n", command: command))
        #expect(!Tmux.isHooked("alert-bell[0] run-shell 'say bell'\n", command: command))
        #expect(!Tmux.isHooked("alert-bell[12] \(command)\n", command: command))
        // A hook from an older version gets replaced.
        #expect(!Tmux.isHooked("alert-bell[4775] run-shell -b \"'\(script.path)' tmux #{q:session_name} #{q:window_name}\"\n", command: command))
    }

    @Test func idsAreAPrefixAndDigits() {
        #expect(Tmux.isID("%12", prefix: "%") && Tmux.isID("@3", prefix: "@"))
        for bad in ["%", "@", "%1a", "%١", "12", "%1 ", "@%1"] {
            #expect(!Tmux.isID(bad, prefix: "%") && !Tmux.isID(bad, prefix: "@"))
        }
    }
}

/// Against a real tmux server on a socket of its own, so the user's tmux is never touched. The server runs with a
/// HOME holding a token and a PATH whose `curl` records each request, so the shipped script runs as it would.
@MainActor
struct TmuxWatcherTests {
    private func tmux(_ socket: String, environment: [String: String]? = nil, _ arguments: String...) -> String? {
        let process = Process()
        process.executableURL = Tmux.binary
        process.arguments = ["-L", socket] + arguments
        if let environment { process.environment = environment }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test(.enabled(if: Tmux.isInstalled)) func bellsCarryNamesReadByTheScriptUnexpanded() async throws {
        let id = UUID().uuidString.prefix(8)
        let socket = "nunsseop-test-\(id)"
        let home = URL(fileURLWithPath: "/tmp/nunsseop-test-\(id)")
        let requests = home.appendingPathComponent("requests")
        defer {
            _ = tmux(socket, "kill-server")
            try? FileManager.default.removeItem(at: home)
            try? FileManager.default.removeItem(atPath: "/private/tmp/tmux-\(getuid())/\(socket)")
        }
        let support = home.appendingPathComponent("Library/Application Support/Nunsseop")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: requests, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try "token".write(to: support.appendingPathComponent("notify-token"), atomically: true, encoding: .utf8)
        let curl = home.appendingPathComponent("bin/curl")
        try """
        #!/bin/sh
        out=$(mktemp "\(requests.path)/req.XXXXXX")
        for arg; do printf '%s\\n' "$arg"; done > "$out.args"
        cat > "$out.body"
        rm "$out"
        """.write(to: curl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: curl.path)

        let environment = ["HOME": home.path, "PATH": "\(home.path)/bin:/usr/bin:/bin", "TERM": "xterm"]
        // Names a program could set: braces, commas and ~ must arrive as typed, not expanded by sh.
        let names = ["x{a,claude}", "{z,claude}", "~root", "{1..5}"]
        #expect(tmux(socket, environment: environment, "-f", "/dev/null", "new-session", "-d", "-s", "work", "-n", names[0], "sleep 60") != nil)
        for name in names.dropFirst() { _ = tmux(socket, "new-window", "-d", "-t", "work", "-n", name, "sleep 60") }
        // A split window: which pane rang isn't known, so no agent is named.
        // Windows are targeted by index: tmux reads `{…}` in a target as one of its own tokens.
        _ = tmux(socket, "split-window", "-d", "-t", "work:2", "sleep 60")

        let watcher = TmuxWatcher(socketName: socket, scriptURL: home.appendingPathComponent("terminal-notify.sh"))
        watcher.start()
        defer { watcher.stop(waiting: true) }
        let binary = try #require(Tmux.binary)
        let command = try #require(Tmux.hookCommand(script: home.appendingPathComponent("terminal-notify.sh"),
                                                     binary: binary, socketName: socket))
        await waitUntil { Tmux.isHooked(tmux(socket, "show-hooks", "-g") ?? "", command: command) }
        #expect(Tmux.isHooked(tmux(socket, "show-hooks", "-g") ?? "", command: command))

        for index in names.indices { _ = tmux(socket, "respawn-pane", "-k", "-t", "work:\(index).0", "printf '\\a'; sleep 60") }
        let bodies = { (try? FileManager.default.contentsOfDirectory(atPath: requests.path))?.filter { $0.hasSuffix(".body") } ?? [] }
        let started = Date()
        await waitUntil { bodies().count >= names.count }
        // This has failed now and then in a busy full run, always missing the first window's bell; what tmux held then
        // says why, for next time.
        let diagnostics = {
            let windows = tmux(socket, "list-windows", "-t", "work",
                               "-F", "#{window_index} #{window_id} #{window_name} bell=#{window_bell_flag} #{pane_current_command}") ?? "none"
            return "waited \(String(format: "%.1f", Date().timeIntervalSince(started))) s; hooks: \(tmux(socket, "show-hooks", "-g") ?? "none")windows:\n\(windows)"
        }

        var sent: [String: [String]] = [:]
        for file in bodies() {
            let base = requests.appendingPathComponent(String(file.dropLast(5)))
            let body = try String(contentsOf: base.appendingPathExtension("body"), encoding: .utf8)
            sent[body] = try String(contentsOf: base.appendingPathExtension("args"), encoding: .utf8).split(separator: "\n").map(String.init)
        }
        #expect(Set(sent.keys) == Set(names.map { "work · \($0)" }), "\(diagnostics())")
        for (body, args) in sent {
            #expect(!args.contains("X-Agent: claude") && !args.contains("X-Title: claude"), "\(body): \(args)")
            #expect(args.contains { $0.hasPrefix("X-Target: tmux:@") }, "\(body): \(args)")
        }
        #expect(sent["work · ~root"]?.contains("X-Agent: ") == true)
        #expect(sent["work · x{a,claude}"]?.contains("X-Agent: ") == false)
    }
}

/// The bell script as shipped, with `curl` replaced by a stand-in that records what it was given.
struct TerminalBellScriptTests {
    private func run(_ arguments: [String]) throws -> (args: [String], body: String) {
        let dir = URL(fileURLWithPath: "/tmp/nunsseop-test-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: dir) }
        let support = dir.appendingPathComponent("Library/Application Support/Nunsseop")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try "secret-token".write(to: support.appendingPathComponent("notify-token"), atomically: true, encoding: .utf8)
        let bin = dir.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let curl = bin.appendingPathComponent("curl")
        try """
        #!/bin/sh
        for arg; do printf '%s\\n' "$arg"; done > "\(dir.path)/args"
        cat > "\(dir.path)/body"
        """.write(to: curl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: curl.path)
        let script = dir.appendingPathComponent("terminal-notify.sh")
        TerminalBell.install(at: script)

        let process = Process()
        process.executableURL = script
        process.arguments = arguments
        process.environment = ["HOME": dir.path, "PATH": "\(bin.path):/usr/bin:/bin", "__CFBundleIdentifier": "com.mitchellh.ghostty"]
        try process.run()
        process.waitUntilExit()
        let args = try String(contentsOf: dir.appendingPathComponent("args"), encoding: .utf8).split(separator: "\n").map(String.init)
        let body = try String(contentsOf: dir.appendingPathComponent("body"), encoding: .utf8)
        return (args, body)
    }

    /// The tmux-window mode with a stand-in tmux that knows no window: nothing is sent.
    @Test func goneWindowOrBadIdSendsNothing() throws {
        let dir = URL(fileURLWithPath: "/tmp/nunsseop-test-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("bin"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let curl = dir.appendingPathComponent("bin/curl"), tmux = dir.appendingPathComponent("tmux")
        try "#!/bin/sh\ntouch \(dir.path)/sent\n".write(to: curl, atomically: true, encoding: .utf8)
        try "#!/bin/sh\nexit 1\n".write(to: tmux, atomically: true, encoding: .utf8)
        for file in [curl, tmux] { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path) }
        let script = dir.appendingPathComponent("terminal-notify.sh")
        TerminalBell.install(at: script)
        for window in ["@9", "@9;x", "9", ""] {
            let process = Process()
            process.executableURL = script
            process.arguments = ["tmux-window", tmux.path, "", window]
            process.environment = ["HOME": dir.path, "PATH": "\(dir.path)/bin:/usr/bin:/bin"]
            try process.run()
            process.waitUntilExit()
        }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("sent").path))
    }

    @Test func postsTheAgentAndWhereTheBellRang() throws {
        let sent = try run(["tmux", "work", "api", "claude"])
        #expect(sent.args.contains("http://127.0.0.1:\(NotifyServer.port)/notify"))
        #expect(sent.args.contains("Authorization: Bearer secret-token"))
        #expect(sent.args.contains("X-Title: claude"))
        #expect(sent.args.contains("X-Agent: claude"))
        #expect(sent.body == "work · api")
        #expect(sent.args.contains("X-App: com.mitchellh.ghostty"))
        #expect(sent.args.contains("X-Target: "))
        let withPane = try run(["tmux", "work", "api", "claude", "%12"])
        #expect(withPane.args.contains("X-Target: tmux:%12"))
        let hostile = try run(["tmux", "work", "api", "claude", "%1; touch x\r\nX-Evil: 1"])
        #expect(hostile.args.contains("X-Target: tmux:%1touchxX-Evil1"))
    }

    @Test func fallsBackToTheTerminalAndKeepsHeadersClean() throws {
        let sent = try run(["WezTerm", "", "build\r\nX-Evil: 1", "bad name\r\nX-Agent: claude"])
        #expect(sent.args.contains("X-Title: badnameX-Agentclaude"))
        #expect(!sent.args.contains { $0.contains("\r") || $0 == "X-Evil: 1" })
        #expect(sent.body == "build\r\nX-Evil: 1")
        let empty = try run(["WezTerm", "default", "", ""])
        #expect(empty.args.contains("X-Title: WezTerm"))
        #expect(empty.body == "default")
    }
}

struct WezTermSnippetTests {
    @Test func callsTheScriptWithoutAShell() {
        let snippet = WezTerm.snippet(script: URL(fileURLWithPath: "/Users/a/Library/Application Support/Nunsseop/terminal-notify.sh"))
        #expect(snippet.contains("wezterm.on('bell', function(window, pane)"))
        #expect(snippet.contains("wezterm.background_child_process({ [==[/Users/a/Library/Application Support/Nunsseop/terminal-notify.sh]==], 'WezTerm', window:active_workspace(), pane:get_title(), process, tostring(pane:pane_id()) })"))
        #expect(!snippet.contains("os.execute") && !snippet.contains("run_child_process"))
        // A pane ringing over and over (cat of a file full of BELs) starts one script per 2 seconds, not one per bell.
        #expect(snippet.contains("if nunsseop_last_bell[id] and now - nunsseop_last_bell[id] < 3 then return end"))
    }

    @Test func focusDoesNotStartAMuxServer() throws {
        let dir = URL(fileURLWithPath: "/tmp/nunsseop-test-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cli = dir.appendingPathComponent("wezterm")
        try "#!/bin/sh\nprintf '%s ' \"$@\" >> \(dir.path)/args\n".write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        WezTerm.focus(pane: "١٢", cli: cli)   // not ASCII digits: ignored
        WezTerm.focus(pane: "7", cli: cli)
        let args = dir.appendingPathComponent("args")
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: args.path) { usleep(20_000) }
        #expect((try? String(contentsOf: args, encoding: .utf8)) == "cli --no-auto-start activate-pane --pane-id 7 ")
    }
}


struct HookUpdateTests {
    @Test func olderHookCommandsAreReplacedOnce() throws {
        let current = NotifyServer.hookCommand(title: "Claude Code")
        let old = "plutil -extract message raw -o - - | curl -s http://127.0.0.1:\(NotifyServer.port)/notify --data-binary @-"
        let other: [String: Any] = ["hooks": [["type": "command", "command": "muxy-hook notification"]]]
        let settings: [String: Any] = ["model": "opus", "hooks": ["Notification": [other, ["hooks": [["type": "command", "command": old]]]]]]
        let updated = try #require(try JSONHook.updating(current, in: settings))
        #expect(JSONHook.isCurrent(current, in: updated))
        #expect(updated["model"] as? String == "opus")
        let groups = ((updated["hooks"] as? [String: Any])?["Notification"] as? [[String: Any]]) ?? []
        #expect(groups.count == 2)
        #expect(groups.first.flatMap { ($0["hooks"] as? [[String: Any]])?.first?["command"] as? String } == "muxy-hook notification")
        #expect(try JSONHook.updating(current, in: updated) == nil)
        #expect(current.contains("X-App: $__CFBundleIdentifier"))
    }

    private func commands(_ settings: [String: Any]) -> [[String]] {
        (((settings["hooks"] as? [String: Any])?["Notification"] as? [[String: Any]]) ?? []).map { group in
            ((group["hooks"] as? [[String: Any]]) ?? []).compactMap { $0["command"] as? String }
        }
    }

    @Test func currentHookSharingAGroupIsLeftAlone() throws {
        let current = NotifyServer.hookCommand(title: "Claude Code")
        let settings: [String: Any] = ["hooks": ["Notification": [
            ["hooks": [["type": "command", "command": "say mine"], ["type": "command", "command": current]]],
        ]]]
        #expect(JSONHook.isCurrent(current, in: settings))
        #expect(try JSONHook.updating(current, in: settings) == nil)
    }

    @Test func oldHookSharingAGroupIsReplacedAndTheRestKept() throws {
        let current = NotifyServer.hookCommand(title: "Claude Code")
        let old = "curl -s http://127.0.0.1:\(NotifyServer.port)/notify --data-binary @-"
        let settings: [String: Any] = ["hooks": ["Notification": [
            ["matcher": "", "hooks": [["type": "command", "command": "say mine"], ["type": "command", "command": old]]],
        ]]]
        let updated = try #require(try JSONHook.updating(current, in: settings))
        let groups = ((updated["hooks"] as? [String: Any])?["Notification"] as? [[String: Any]]) ?? []
        #expect(groups.first?["matcher"] as? String == "")
        #expect(commands(updated) == [["say mine"], [current]])
        #expect(JSONHook.isCurrent(current, in: updated))
    }

    @Test func removingTakesOnlyNunsseopsHooks() {
        let ours = NotifyServer.hookCommand(title: "Gemini CLI")
        let settings: [String: Any] = ["hooks": ["Notification": [
            ["matcher": "x", "hooks": [["type": "command", "command": "say mine"], ["type": "command", "command": ours]]],
            ["hooks": [["type": "command", "command": ours]]],
        ], "Stop": [["hooks": [["type": "command", "command": "stop.sh"]]]]]]
        let removed = JSONHook.removing(from: settings)
        #expect(commands(removed) == [["say mine"]])
        #expect(((removed["hooks"] as? [String: Any])?["Notification"] as? [[String: Any]])?.first?["matcher"] as? String == "x")
        #expect((removed["hooks"] as? [String: Any])?["Stop"] != nil)
    }

    @Test func entriesThatArentObjectsDontHideNunsseopsHook() throws {
        let current = NotifyServer.hookCommand(title: "Claude Code")
        let old = "curl -s http://127.0.0.1:\(NotifyServer.port)/notify OLD"
        let settings: [String: Any] = ["hooks": ["Notification": [
            ["hooks": [["type": "command", "command": old], "junk"]],
            "stray group",
        ]]]
        // The old hook is seen, so it's replaced rather than joined by a second one.
        #expect(JSONHook.isInstalled(in: settings))
        #expect(!JSONHook.isCurrent(current, in: settings))
        let updated = try #require(try JSONHook.updating(current, in: settings))
        let groups = ((updated["hooks"] as? [String: Any])?["Notification"] as? [Any]) ?? []
        #expect(groups.count == 3)
        #expect((groups[0] as? [String: Any])?["hooks"] as? [String] == ["junk"])
        #expect(groups[1] as? String == "stray group")
        #expect(JSONHook.isCurrent(current, in: updated))
        #expect(try JSONHook.updating(current, in: updated) == nil)

        // Disconnecting takes the hook out and leaves the rest as it was.
        let removed = JSONHook.removing(from: updated)
        let left = ((removed["hooks"] as? [String: Any])?["Notification"] as? [Any]) ?? []
        #expect(left.count == 2)
        #expect(!JSONHook.isInstalled(in: removed))
    }

    @Test func duplicateHooksBecomeOne() throws {
        let current = NotifyServer.hookCommand(title: "Gemini CLI")
        let group: [String: Any] = ["hooks": [["type": "command", "command": current]]]
        let settings: [String: Any] = ["hooks": ["Notification": [group, group]]]
        #expect(!JSONHook.isCurrent(current, in: settings))
        let updated = try #require(try JSONHook.updating(current, in: settings))
        #expect(((updated["hooks"] as? [String: Any])?["Notification"] as? [[String: Any]])?.count == 1)
    }
}

struct NoticeClickTests {
    @Test func muxyGoesToTheNotificationsTab() throws {
        let entry: [[String: Any]] = [["id": "N", "title": "Pi", "body": "done", "isRead": false, "source": ["aiProvider": ["_0": "pi"]],
                                       "projectID": "AA2932BC-99A4-4172-845B-99E03F715C77",
                                       "worktreeID": "E8EE3F1F-3D0F-404B-83B7-8E89D7A0B59E",
                                       "tabID": "129BB77D-F173-4DB8-B231-6C7FF885213D"]]
        let notice = try #require(MuxyNotice.parse(JSONSerialization.data(withJSONObject: entry))?.first)
        #expect(notice.focusCommands == [
            "switch-project|AA2932BC-99A4-4172-845B-99E03F715C77",
            "switch-worktree|E8EE3F1F-3D0F-404B-83B7-8E89D7A0B59E|AA2932BC-99A4-4172-845B-99E03F715C77",
            "switch-tab|129BB77D-F173-4DB8-B231-6C7FF885213D",
        ])
    }

    @Test func muxyIdsThatCouldAddCommandsAreRefused() {
        let hostile = MuxyNotice(id: "N", title: "", body: "", isRead: false, provider: nil,
                                 projectID: "AA|close-pane", worktreeID: nil, tabID: "12\nkill-session")
        #expect(hostile.focusCommands.isEmpty)
        let partly = MuxyNotice(id: "N", title: "", body: "", isRead: false, provider: nil,
                                projectID: "AA2932BC", worktreeID: "x|y", tabID: nil)
        #expect(partly.focusCommands == ["switch-project|AA2932BC"])
        #expect(MuxyNotice(id: "N", title: "", body: "", isRead: false, provider: nil).focusCommands.isEmpty)
    }

    @Test func localNoticesLeadToTheirPaneOrApp() {
        #expect(TerminalFocus.action(app: nil, target: "tmux:%3") != nil)
        #expect(TerminalFocus.action(app: nil, target: "WezTerm:7") != nil)
        #expect(TerminalFocus.action(app: nil, target: nil) == nil)
        #expect(TerminalFocus.action(app: nil, target: "other:1") == nil)
        // Apps that aren't running aren't launched for a notice.
        #expect(TerminalFocus.action(app: "com.example.not-running", target: nil) == nil)
        #expect(TerminalFocus.action(app: "com.apple.finder", target: nil) != nil)
    }

    @Test func parentProcess() {
        #expect(TerminalFocus.parentPID(of: getpid()) == getppid())
        #expect(TerminalFocus.parentPID(of: -1) == nil)
    }

    @Test func socketClientReadsOneReplyPerLine() throws {
        let path = "/tmp/nunsseop-test-\(UUID().uuidString.prefix(8)).sock"
        let script = """
        import socket, sys
        s = socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); s.listen(1)
        c, _ = s.accept(); f = c.makefile("rwb")
        for line in f:
            f.write(b"ok:" + line); f.flush()
        """
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-c", script, path]
        try server.run()
        defer { server.terminate(); try? FileManager.default.removeItem(atPath: path) }
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: path) { usleep(20_000) }
        #expect(TerminalFocus.send(["switch-project|A", "switch-tab|B"], toSocket: path) == ["ok:switch-project|A", "ok:switch-tab|B"])
        #expect(TerminalFocus.send(["x"], toSocket: "/tmp/nunsseop-missing.sock").isEmpty)
    }

    @Test func muxyCommandsGetAConnectionEach() throws {
        // Like Muxy: one reply, then the connection closes.
        let path = "/tmp/nunsseop-test-\(UUID().uuidString.prefix(8)).sock"
        let script = """
        import socket, sys
        s = socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); s.listen(4)
        while True:
            c, _ = s.accept(); line = c.makefile("rb").readline()
            c.sendall(b"ok " + line); c.close()
        """
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-c", script, path]
        try server.run()
        defer { server.terminate(); try? FileManager.default.removeItem(atPath: path) }
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: path) { usleep(20_000) }
        let commands = ["switch-project|A", "switch-worktree|B|A", "switch-tab|C"]
        #expect(MuxyNotice.send(commands, toSocket: path) == commands.map { "ok \($0)" })
        // On one connection only the first would get through.
        #expect(TerminalFocus.send(commands, toSocket: path).count == 1)
    }

    @MainActor @Test func clickingANoticeRunsItsActionInsteadOfOpening() {
        let hud = HUDCenter(settings: AppSettings.shared)
        var went = 0
        hud.show(.notice(symbol: "terminal", title: "Pi", detail: nil), duration: 6, action: { went += 1 })
        #expect(hud.action != nil)
        #expect(hud.performAction())
        #expect(went == 1)
        #expect(hud.event == nil && hud.action == nil)
        hud.show(.notice(symbol: "timer", title: "Done", detail: nil), duration: 6)
        #expect(!hud.performAction())
        #expect(hud.event != nil)
        // A notice that replaces a clickable one doesn't keep its action.
        hud.show(.notice(symbol: "terminal", title: "Pi", detail: nil), duration: 6, action: { went += 1 })
        hud.show(.volume(0.5, muted: false))
        #expect(hud.action == nil)
    }
}

/// tmux's focus against a real server on a socket of its own.
@MainActor
struct TmuxFocusTests {
    private func tmux(_ socket: String, _ arguments: String...) -> String? {
        TerminalFocus.run(Tmux.binary!, ["-L", socket] + arguments)
    }

    @Test(.enabled(if: Tmux.isInstalled)) func focusSelectsThePanesWindowAndPane() async throws {
        let socket = "nunsseop-test-\(UUID().uuidString.prefix(8))"
        defer {
            _ = tmux(socket, "kill-server")
            try? FileManager.default.removeItem(atPath: "/private/tmp/tmux-\(getuid())/\(socket)")
        }
        _ = tmux(socket, "-f", "/dev/null", "new-session", "-d", "-s", "work", "-n", "one", "sleep 60")
        _ = tmux(socket, "new-window", "-d", "-t", "work", "-n", "two", "sleep 60")
        _ = tmux(socket, "split-window", "-d", "-t", "work:two", "sleep 60")
        let panes = (tmux(socket, "list-panes", "-t", "work:two", "-F", "#{pane_id}") ?? "").split(separator: "\n").map(String.init)
        let target = try #require(panes.last)
        #expect(tmux(socket, "display-message", "-p", "#{window_name}")?.trimmingCharacters(in: .whitespacesAndNewlines) == "one")

        Tmux.focus(pane: target, socketName: socket)
        var active = ""
        for _ in 0..<100 {
            active = tmux(socket, "display-message", "-p", "#{window_name} #{pane_id}")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if active == "two \(target)" { break }
            try? await Task.sleep(for: .milliseconds(30))
        }
        #expect(active == "two \(target)")
        // Pane ids are numbers after %; anything else is ignored.
        Tmux.focus(pane: "%1; kill-server", socketName: socket)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(tmux(socket, "display-message", "-p", "#{window_name}") != nil)
    }
}


/// Nunsseop's tmux slot against a real server: someone else's hook stays, a leftover one of ours goes,
/// and the hook as tmux prints it back matches, so it isn't set again every 10 s.
@MainActor
struct TmuxSlotTests {
    private func tmux(_ socket: String, _ arguments: String...) -> String? {
        TerminalFocus.run(Tmux.binary!, ["-L", socket] + arguments)
    }

    private func withServer(_ body: (String) async throws -> Void) async throws {
        let socket = "nunsseop-test-\(UUID().uuidString.prefix(8))"
        defer {
            _ = tmux(socket, "kill-server")
            try? FileManager.default.removeItem(atPath: "/private/tmp/tmux-\(getuid())/\(socket)")
        }
        _ = tmux(socket, "-f", "/dev/null", "new-session", "-d", "-s", "w", "sleep 60")
        try await body(socket)
    }

    private func slot(_ socket: String) -> String? { Tmux.slot(in: tmux(socket, "show-hooks", "-g") ?? "") }

    @Test(.enabled(if: Tmux.isInstalled)) func someoneElsesHookInTheSlotStays() async throws {
        try await withServer { socket in
            _ = tmux(socket, "set-hook", "-g", Tmux.hook, "run-shell 'say mine'")
            let script = URL(fileURLWithPath: "/tmp/nunsseop-test slot/terminal-notify.sh")
            let watcher = TmuxWatcher(socketName: socket, scriptURL: script)
            watcher.start()
            try await Task.sleep(for: .milliseconds(400))
            #expect(slot(socket) == "alert-bell[4775] run-shell \"say mine\"")
            watcher.stop(waiting: true)
            #expect(slot(socket) == "alert-bell[4775] run-shell \"say mine\"")
            try? FileManager.default.removeItem(at: script.deletingLastPathComponent())
        }
    }

    @Test(.enabled(if: Tmux.isInstalled)) func leftoverHookComesOffWhileTheFeatureIsOff() async throws {
        try await withServer { socket in
            _ = tmux(socket, "set-hook", "-g", Tmux.hook,
                     "run-shell -b \"'/Users/a/Library/Application Support/Nunsseop/tmux-notify.sh' tmux #{q:session_name}\"")
            let watcher = TmuxWatcher(socketName: socket)
            watcher.clearLeftover()
            for _ in 0..<50 { if slot(socket) == nil { break }; try await Task.sleep(for: .milliseconds(20)) }
            #expect(slot(socket) == nil)
            // Someone else's is kept.
            _ = tmux(socket, "set-hook", "-g", Tmux.hook, "run-shell 'say mine'")
            watcher.clearLeftover()
            try await Task.sleep(for: .milliseconds(300))
            #expect(slot(socket) != nil)
        }
    }

    @Test(.enabled(if: Tmux.isInstalled)) func hookAsTmuxPrintsItMatches() async throws {
        try await withServer { socket in
            // Spaces, as in "Application Support", and a socket name.
            let dir = URL(fileURLWithPath: "/tmp/nunsseop-test \(UUID().uuidString.prefix(4))/Application Support")
            defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
            let script = dir.appendingPathComponent("terminal-notify.sh")
            let watcher = TmuxWatcher(socketName: socket, scriptURL: script)
            watcher.start()
            defer { watcher.stop(waiting: true) }
            let command = try #require(Tmux.hookCommand(script: script, binary: Tmux.binary!, socketName: socket))
            for _ in 0..<50 { if slot(socket) != nil { break }; try await Task.sleep(for: .milliseconds(20)) }
            let printed = try #require(tmux(socket, "show-hooks", "-g"))
            #expect(Tmux.isHooked(printed, command: command), "\(printed)")
        }
    }
}
