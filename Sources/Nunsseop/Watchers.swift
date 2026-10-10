import AppKit
import Network

/// Adds new screenshots to the shelf as they are saved.
@MainActor
final class ScreenshotWatcher {
    var onScreenshot: ((URL) -> Void)?
    var isEnabled = true

    private var source: DispatchSourceFileSystemObject?
    private var seen: Set<String> = []
    private let startedAt = Date()

    static var directory: URL {
        let configured = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        let path = (configured.map { ($0 as NSString).expandingTildeInPath }) ?? ""
        if !path.isEmpty { return URL(fileURLWithPath: path, isDirectory: true) }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    func start() {
        let directory = Self.directory
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.scan(directory)
                // The screenshot marker can land a moment after the file appears.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.scan(directory) }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    private func scan(_ directory: URL) {
        guard isEnabled else { return }
        let keys: [URLResourceKey] = [.creationDateKey, .isRegularFileKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys,
                                                                  options: [.skipsHiddenFiles])) ?? []
        for url in files where !seen.contains(url.path) {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let created = values.creationDate, created > startedAt,
                  ["png", "jpg", "jpeg", "heic", "mov"].contains(url.pathExtension.lowercased()),
                  Self.looksLikeScreenshot(url) else { continue }
            seen.insert(url.path)
            onScreenshot?(url)
        }
    }

    /// macOS marks its screenshots with this extended attribute regardless of language.
    private static func looksLikeScreenshot(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0
    }
}

/// Shows the Caps Lock state whenever it changes.
@MainActor
final class CapsLockWatcher {
    var onChange: ((Bool) -> Void)?
    private var timer: Timer?
    private var last = NSEvent.modifierFlags.contains(.capsLock)

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func start() {
        guard timer == nil else { return }
        last = NSEvent.modifierFlags.contains(.capsLock)
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = NSEvent.modifierFlags.contains(.capsLock)
                if now != self.last {
                    self.last = now
                    self.onChange?(now)
                }
            }
        }
        timer?.tolerance = 0.025
    }
}

/// What an agent's hook said happened to one session, for the agents count.
enum AgentAction: Equatable {
    /// A turn started.
    case working
    /// Asking for permission or an answer.
    case needsInput
    /// A turn ended.
    case finished
    /// Waiting at the prompt: a turn that was cut short no longer works and nothing is being asked, but a finished hand stays.
    case idle
    /// The session is over.
    case remove
}

/// One hook call from a Claude Code session, reduced to what the count needs.
struct AgentEvent: Equatable {
    let session: String
    let action: AgentAction
    /// The bundle id of the app the session runs in.
    var app: String?
    /// Whether it runs in a herdr pane, which herdr's own count covers.
    var inHerdr = false
}

/// Claude Code's hook events as the agents count reads them.
enum AgentHook {
    /// What an event means; nil for the ones that say nothing about work (`auth_success`, `SubagentStop`).
    static func action(event: String, type: String?) -> AgentAction? {
        switch event {
        case "UserPromptSubmit": return .working
        case "Stop", "StopFailure": return .finished
        case "SessionEnd": return .remove
        case "Notification":
            switch type {
            case "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input": return .needsInput
            case "idle_prompt": return .idle
            case "elicitation_response", "elicitation_complete": return .working
            default: return nil
            }
        default: return nil
        }
    }

    /// The event a request's headers describe. The hook already trims its values; anything outside the
    /// whitelist is refused here as well. A call from a subagent (`X-Subagent`) is the main session's business.
    /// A background session (`X-Background`, from `claude --bg`) runs in Claude Code's daemon, so the app and the herdr
    /// pane it seems to be in are only the daemon's, inherited from wherever it was first started.
    static func event(headers: [String: String]) -> AgentEvent? {
        let word = { (name: String) -> String? in
            guard let value = headers[name], !value.isEmpty, value.count <= 64,
                  value.unicodeScalars.allSatisfy(CharacterSet.agentIDCharacters.contains) else { return nil }
            return value
        }
        guard headers["x-subagent"]?.isEmpty ?? true,
              let session = word("x-session"), let name = word("x-event"),
              let action = action(event: name, type: word("x-type")) else { return nil }
        let background = headers["x-background"]?.isEmpty == false
        let app = background ? nil : headers["x-app"].flatMap { value in
            !value.isEmpty && value.count <= 80 && value.unicodeScalars.allSatisfy(CharacterSet.bundleIDCharacters.contains)
                ? value : nil
        }
        return AgentEvent(session: session, action: action, app: app, inHerdr: !background && headers["x-herdr"]?.isEmpty == false)
    }
}

/// Accepts notifications from local tools such as Claude Code hooks:
/// `POST http://127.0.0.1:47750/notify` with `Authorization: Bearer <token>` and a JSON body
/// `{"title": "...", "message": "..."}`. The token lives in Application Support/Nunsseop/notify-token.
/// `POST /agent` takes Claude Code's session events for the agents count, as headers only (see `agentHookCommand`).
final class NotifyServer: @unchecked Sendable {
    static let port: UInt16 = 47750
    /// A notification a local tool sent, with where it came from when the tool said so.
    struct Notice {
        let title: String
        let message: String?
        /// The bundle id of the app the tool ran in (its terminal), from macOS's `__CFBundleIdentifier`.
        var app: String?
        /// A pane in a terminal, as `tmux:%12` or `WezTerm:7`.
        var target: String?
    }

    var onNotify: (@MainActor (Notice) -> Void)?
    var onAgent: (@MainActor (AgentEvent) -> Void)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "nunsseop.notify")
    /// Touched only on `queue`.
    private var openConnections = 0
    private static let maxConnections = 8
    static let maxRequestBytes = 65_536
    let token: String

    /// A shell command for Claude Code's Notification hook. Claude Code passes the event as
    /// JSON on stdin; its `message` field is sent as the notification text.
    static var hookCommand: String { hookCommand(title: "Claude Code") }

    /// The same command for any tool that passes JSON with a `message` field on stdin, such as Gemini CLI.
    static func hookCommand(title: String) -> String {
        "plutil -extract message raw -o - - 2>/dev/null | curl -s -m 2 -X POST http://127.0.0.1:\(port)/notify "
            + "-H \"Authorization: Bearer $(cat \"$HOME/Library/Application Support/Nunsseop/notify-token\")\" "
            + "-H 'X-Title: \(title)' -H \"X-App: $__CFBundleIdentifier\" --data-binary @- >/dev/null || true"
    }

    /// Claude Code's hook for the agents count, the same for every event. Claude Code passes the event as JSON on
    /// stdin; only the ids and names below leave it, as headers (no prompt, reply, folder or transcript), trimmed to
    /// safe characters so a stray newline can't break one. Nothing may reach stdout, which `UserPromptSubmit` adds to
    /// Claude's context, and a closed or stuck Nunsseop costs a session at most a second.
    static var agentHookCommand: String {
        "in=$(cat); k() { printf '%s' \"$in\" | plutil -extract \"$1\" raw -o - - 2>/dev/null | tr -cd 'A-Za-z0-9_.-' | cut -c1-64; }; "
            + "curl -s -m 1 --connect-timeout 1 -X POST http://127.0.0.1:\(port)/agent -d '' "
            + "-H \"Authorization: Bearer $(cat \"$HOME/Library/Application Support/Nunsseop/notify-token\")\" "
            + "-H \"X-Session: $(k session_id)\" -H \"X-Event: $(k hook_event_name)\" -H \"X-Type: $(k notification_type)\" "
            + "-H \"X-Subagent: $(k agent_id)\" -H \"X-App: $__CFBundleIdentifier\" -H \"X-Herdr: ${HERDR_PANE_ID:+1}\" "
            + "-H \"X-Background: ${CLAUDE_JOB_DIR:+1}\" "
            + ">/dev/null 2>&1 || true"
    }

    /// A command for scripts: the text after `--data-binary` becomes the notification.
    static var scriptCommand: String {
        "curl -s -m 2 -X POST http://127.0.0.1:\(port)/notify "
            + "-H \"Authorization: Bearer $(cat \"$HOME/Library/Application Support/Nunsseop/notify-token\")\" "
            + "-H 'X-Title: Script' --data-binary 'Done'"
    }

    static var tokenURL: URL {
        (NotifyIntegration.homeOverride?.appendingPathComponent("Library/Application Support")
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
            .appendingPathComponent("Nunsseop/notify-token")
    }

    init() {
        let url = Self.tokenURL
        if let existing = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           existing.count >= 32 {
            token = existing
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } else {
            token = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data(token.utf8), attributes: [.posixPermissions: 0o600])
        }
    }

    func start() {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: Self.port)!)
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters) else { return }
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        guard openConnections < Self.maxConnections else {
            connection.cancel()
            return
        }
        openConnections += 1
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed: self?.openConnections -= 1
            default: break
            }
        }
        connection.start(queue: queue)
        // Drop clients that connect and then stall.
        queue.asyncAfter(deadline: .now() + 5) { connection.cancel() }
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Self.parse(buffer) {
                self.respond(to: request, on: connection)
            } else if isComplete || error != nil || buffer.count > Self.maxRequestBytes {
                self.reply(connection, status: "400 Bad Request")
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    static func parse(_ data: Data) -> Request? {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<separator.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard let length = Int(headers["content-length"] ?? "0"), (0...maxRequestBytes).contains(length) else { return nil }
        let body = data[separator.upperBound...]
        guard body.count >= length else { return nil }
        return Request(method: String(parts[0]), path: String(parts[1]), headers: headers, body: Data(body.prefix(length)))
    }

    /// What a request asks the app to do, once it is answered.
    enum Effect {
        case none
        case notice(Notice)
        case agent(AgentEvent)
    }

    private func respond(to request: Request, on connection: NWConnection) {
        let (status, effect) = route(request)
        switch effect {
        case .none: break
        case .agent(let event):
            let handler = onAgent
            DispatchQueue.main.async { MainActor.assumeIsolated { handler?(event) } }
        case .notice(let notice):
            let handler = onNotify
            DispatchQueue.main.async { MainActor.assumeIsolated { handler?(notice) } }
        }
        reply(connection, status: status)
    }

    func route(_ request: Request) -> (status: String, effect: Effect) {
        guard request.method == "POST", request.path == "/notify" || request.path == "/agent" else {
            return ("404 Not Found", .none)
        }
        guard Self.constantTimeEqual(request.headers["authorization"] ?? "", "Bearer \(token)") else {
            return ("401 Unauthorized", .none)
        }
        if request.path == "/agent" {
            return ("204 No Content", AgentHook.event(headers: request.headers).map(Effect.agent) ?? .none)
        }
        // The body is either JSON {"title", "message"} or plain text with the title in X-Title.
        let json = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
        // Sent by tools that relay several agents (tmux): one whose own hook is connected already notifies.
        if let agent = json?["agent"] as? String ?? request.headers["x-agent"],
           NotifyIntegration.forAgent(agent)?.isInstalled == true {
            return ("204 No Content", .none)
        }
        let text = json == nil ? String(data: request.body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let title = String((json?["title"] as? String ?? request.headers["x-title"] ?? "Notification").prefix(80))
        let message = (json?["message"] as? String ?? text).flatMap { $0.isEmpty ? nil : String($0.prefix(200)) }
        let clean = { (value: String?, allowed: CharacterSet) -> String? in
            guard let value, !value.isEmpty, value.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
            return String(value.prefix(80))
        }
        let notice = Notice(title: title, message: message,
                            app: clean(json?["app"] as? String ?? request.headers["x-app"], .bundleIDCharacters),
                            target: clean(json?["target"] as? String ?? request.headers["x-target"], .targetCharacters))
        return ("204 No Content", .notice(notice))
    }

    static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        var difference = UInt8(x.count == y.count ? 0 : 1)
        for i in 0..<max(x.count, y.count) {
            difference |= (i < x.count ? x[i] : 0) ^ (i < y.count ? y[i] : 0)
        }
        return difference == 0
    }

    private func reply(_ connection: NWConnection, status: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}

private extension CharacterSet {
    static let agentIDCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
    static let bundleIDCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
    static let targetCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_:%")
}
