import Foundation
import Testing
@testable import Nunsseop

/// Runs `body` with a scratch folder standing in for the home folder: the tools' config files and
/// Application Support (and so the notify token) are inside it, and it is removed afterwards.
func withTempHome<T>(_ body: (URL) throws -> T) throws -> T {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("nunsseop-test-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    return try NotifyIntegration.$homeOverride.withValue(home) { try body(home) }
}

struct NotifyServerParseTests {
    private func parse(_ text: String) -> NotifyServer.Request? { NotifyServer.parse(Data(text.utf8)) }

    @Test func readsMethodPathAndLowercasedTrimmedHeaders() throws {
        let request = try #require(parse("POST /agent HTTP/1.1\r\nAuthorization:  Bearer t \r\nX-Session: s\r\nContent-Length: 0\r\n\r\n"))
        #expect(request.method == "POST" && request.path == "/agent")
        #expect(request.headers == ["authorization": "Bearer t", "x-session": "s", "content-length": "0"])
        #expect(request.body.isEmpty)
    }

    @Test func waitsForTheWholeBody() throws {
        #expect(parse("POST /notify HTTP/1.1\r\nContent-Length: 5\r\n\r\nabc") == nil)
        let full = try #require(parse("POST /notify HTTP/1.1\r\nContent-Length: 5\r\n\r\nabcde"))
        #expect(String(data: full.body, encoding: .utf8) == "abcde")
        // Bytes past the declared length are not part of the body.
        let extra = try #require(parse("POST /notify HTTP/1.1\r\nContent-Length: 2\r\n\r\nabcde"))
        #expect(String(data: extra.body, encoding: .utf8) == "ab")
    }

    @Test func waitsForTheEndOfTheHeaders() {
        #expect(parse("POST /notify HTTP/1.1\r\nContent-Length: 0\r\n") == nil)
        #expect(parse("") == nil)
    }

    @Test func refusesABadContentLength() {
        let limit = 65_536
        #expect(parse("POST /notify HTTP/1.1\r\nContent-Length: \(limit + 1)\r\n\r\n") == nil)
        #expect(parse("POST /notify HTTP/1.1\r\nContent-Length: -1\r\n\r\n") == nil)
        #expect(parse("POST /notify HTTP/1.1\r\nContent-Length: abc\r\n\r\n") == nil)
        #expect(parse("POST /notify HTTP/1.1\r\nContent-Length: 70000\r\n\r\n") == nil)
        // A request without the header has no body; the limit itself is allowed (the body is still to come).
        #expect(parse("POST /notify HTTP/1.1\r\nX-A: b\r\n\r\n")?.body.isEmpty == true)
        #expect(parse("POST /notify HTTP/1.1\r\nContent-Length: \(limit)\r\n\r\n") == nil)
        #expect(parse("POST /notify HTTP/1.1\r\nContent-Length: \(limit)\r\n\r\n" + String(repeating: "a", count: limit))?.body.count == limit)
    }

    @Test func refusesARequestLineWithoutAPath() {
        #expect(parse("POST\r\nContent-Length: 0\r\n\r\n") == nil)
        #expect(parse("\r\n\r\n") == nil)
    }

    @Test func comparesTokensWholeAndWithoutShortcuts() {
        #expect(NotifyServer.constantTimeEqual("Bearer a", "Bearer a"))
        #expect(NotifyServer.constantTimeEqual("", ""))
        #expect(!NotifyServer.constantTimeEqual("Bearer a", "Bearer ab"))
        #expect(!NotifyServer.constantTimeEqual("Bearer ab", "Bearer a"))
        #expect(!NotifyServer.constantTimeEqual("Bearer a", "Bearer b"))
        #expect(!NotifyServer.constantTimeEqual("", "x"))
        // A trailing NUL byte is a difference, not padding.
        #expect(!NotifyServer.constantTimeEqual("a", "a\0"))
    }
}

struct NotifyServerRoutingTests {
    private func request(_ path: String, method: String = "POST", headers: [String: String] = [:], body: String = "")
        -> NotifyServer.Request {
        NotifyServer.Request(method: method, path: path, headers: headers, body: Data(body.utf8))
    }

    private func authorized(_ server: NotifyServer, _ headers: [String: String] = [:]) -> [String: String] {
        headers.merging(["authorization": "Bearer \(server.token)"]) { $1 }
    }

    private func noticeOf(_ outcome: (status: String, effect: NotifyServer.Effect)) -> NotifyServer.Notice? {
        if case .notice(let notice) = outcome.effect { return notice }
        return nil
    }

    private func agentOf(_ outcome: (status: String, effect: NotifyServer.Effect)) -> AgentEvent? {
        if case .agent(let event) = outcome.effect { return event }
        return nil
    }

    private func isNone(_ outcome: (status: String, effect: NotifyServer.Effect)) -> Bool {
        if case .none = outcome.effect { return true }
        return false
    }

    @Test func onlyPostToNotifyOrAgentIsServed() throws {
        try withTempHome { _ in
            let server = NotifyServer()
            for outcome in [server.route(request("/notify", method: "GET", headers: authorized(server))),
                            server.route(request("/other", method: "POST", headers: authorized(server))),
                            server.route(request("/notify/", method: "POST", headers: authorized(server))),
                            server.route(request("/agent", method: "PUT", headers: authorized(server)))] {
                #expect(outcome.status == "404 Not Found")
                #expect(isNone(outcome))
            }
            // Routing comes before the token check, so an unknown path never says whether a token was right.
            #expect(server.route(request("/notify", method: "GET")).status == "404 Not Found")
        }
    }

    @Test func aMissingOrWrongTokenIsRefused() throws {
        try withTempHome { _ in
            let server = NotifyServer()
            let token = server.token
            let wrong = String(token.dropLast()) + (token.last == "0" ? "1" : "0")
            let attempts: [[String: String]] = [
                [:],
                ["authorization": ""],
                ["authorization": token],
                ["authorization": "Bearer \(wrong)"],
                ["authorization": "Bearer \(token.dropLast())"],
                ["authorization": "Bearer \(token)0"],
                ["authorization": "bearer \(token)"],
            ]
            for path in ["/notify", "/agent"] {
                for headers in attempts {
                    let outcome = server.route(request(path, headers: headers.merging(["x-session": "s", "x-event": "Stop"]) { $1 },
                                                       body: #"{"title":"T"}"#))
                    #expect(outcome.status == "401 Unauthorized", "\(path) \(headers)")
                    #expect(isNone(outcome))
                }
            }
        }
    }

    @Test func anAgentEventReachesTheCountOnceAndAGarbageOneDoesNot() throws {
        try withTempHome { _ in
            let server = NotifyServer()
            let good = server.route(request("/agent", headers: authorized(server, ["x-session": "s-1", "x-event": "Stop", "x-app": "com.apple.Terminal"])))
            #expect(good.status == "204 No Content")
            #expect(agentOf(good) == AgentEvent(session: "s-1", action: .finished, app: "com.apple.Terminal", inHerdr: false))

            let garbage = server.route(request("/agent", headers: authorized(server, ["x-session": "s-1", "x-event": "Nope"])))
            #expect(garbage.status == "204 No Content")
            #expect(isNone(garbage))
            let noSession = server.route(request("/agent", headers: authorized(server, ["x-event": "Stop"])))
            #expect(noSession.status == "204 No Content")
            #expect(isNone(noSession))
        }
    }

    @Test func aJSONNoticeIsCutToTheHUD() throws {
        try withTempHome { _ in
            let server = NotifyServer()
            let body = #"{"title":"\#(String(repeating: "t", count: 200))","message":"\#(String(repeating: "m", count: 500))"}"#
            let outcome = server.route(request("/notify", headers: authorized(server), body: body))
            #expect(outcome.status == "204 No Content")
            let notice = try #require(noticeOf(outcome))
            #expect(notice.title == String(repeating: "t", count: 80))
            #expect(notice.message == String(repeating: "m", count: 200))
            #expect(notice.app == nil && notice.target == nil)
        }
    }

    @Test func aPlainTextNoticeTakesTheTitleFromTheHeader() throws {
        try withTempHome { _ in
            let server = NotifyServer()
            let outcome = server.route(request("/notify", headers: authorized(server, ["x-title": "T"]), body: "  build done \n"))
            let notice = try #require(noticeOf(outcome))
            #expect(notice.title == "T")
            #expect(notice.message == "build done")

            let long = try #require(noticeOf(server.route(request("/notify", headers: authorized(server, ["x-title": String(repeating: "x", count: 120)]), body: "m"))))
            #expect(long.title == String(repeating: "x", count: 80))

            let bare = try #require(noticeOf(server.route(request("/notify", headers: authorized(server), body: "\n"))))
            #expect(bare.title == "Notification")
            #expect(bare.message == nil)
        }
    }

    @Test func aNoticeKeepsOnlySafeAppAndTargetValues() throws {
        try withTempHome { _ in
            let server = NotifyServer()
            func sent(app: String? = nil, target: String? = nil) -> NotifyServer.Notice? {
                var headers = authorized(server, ["x-title": "T"])
                if let app { headers["x-app"] = app }
                if let target { headers["x-target"] = target }
                return noticeOf(server.route(request("/notify", headers: headers, body: "m")))
            }
            #expect(sent(app: "bad app!") != nil && sent(target: "tmux:%1;rm") != nil)
            #expect(sent(app: "com.mitchellh.ghostty", target: "tmux:%12")?.app == "com.mitchellh.ghostty")
            #expect(sent(app: "com.mitchellh.ghostty", target: "tmux:%12")?.target == "tmux:%12")
            #expect(sent(app: "com.x\nevil")?.app == nil)
            #expect(sent(app: "bad app!")?.app == nil)
            #expect(sent(app: "")?.app == nil)
            #expect(sent(target: "tmux:%1;rm")?.target == nil)
            #expect(sent(target: "WezTerm:7")?.target == "WezTerm:7")
            #expect(sent(app: String(repeating: "a", count: 100))?.app == String(repeating: "a", count: 80))

            let json = server.route(request("/notify", headers: authorized(server),
                                            body: #"{"title":"OpenCode","message":"Finished","app":"bad app!","target":"tmux:%3"}"#))
            let fromJSON = try #require(noticeOf(json))
            #expect(fromJSON.title == "OpenCode" && fromJSON.message == "Finished")
            #expect(fromJSON.app == nil && fromJSON.target == "tmux:%3")
        }
    }

    @Test func aRelayedAgentWhoseOwnHookIsConnectedDoesNotNotifyTwice() throws {
        try withTempHome { home in
            let server = NotifyServer()
            let relayed = { (agent: String?) in
                server.route(request("/notify", headers: authorized(server, agent.map { ["x-agent": $0] } ?? [:]), body: "work · api"))
            }
            // Nothing connected: every relayed agent is shown.
            for name in ["claude", "Claude Code", "codex", "unknown"] {
                #expect(relayed(name).status == "204 No Content" && noticeOf(relayed(name)) != nil, "\(name)")
            }

            try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
            try NotifyIntegration.claudeCode.installNow()
            for name in ["claude", "Claude Code", "CLAUDE"] {
                let outcome = relayed(name)
                #expect(outcome.status == "204 No Content" && isNone(outcome), "\(name)")
            }
            #expect(noticeOf(relayed("codex")) != nil)
            #expect(noticeOf(relayed("unknown")) != nil)
            #expect(noticeOf(relayed(nil)) != nil)

            // The same name inside a JSON body counts too.
            let json = server.route(request("/notify", headers: authorized(server), body: #"{"title":"claude","message":"m","agent":"claude"}"#))
            #expect(json.status == "204 No Content" && isNone(json))
        }
    }
}

struct NotifyServerTokenTests {
    private func tokenFile(_ home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Nunsseop/notify-token")
    }

    private func permissions(_ url: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
    }

    @Test func aFreshTokenIsRandomHexKeptPrivate() throws {
        try withTempHome { home in
            let server = NotifyServer()
            #expect(server.token.count == 64)
            #expect(server.token.allSatisfy { "0123456789abcdef".contains($0) })
            let stored = try String(contentsOf: tokenFile(home), encoding: .utf8)
            let mode = try permissions(tokenFile(home))
            #expect(stored == server.token)
            #expect(mode == 0o600)
            // The next launch reads the same token.
            #expect(NotifyServer().token == server.token)
        }
    }

    @Test func aShortTokenIsReplaced() throws {
        try withTempHome { home in
            try FileManager.default.createDirectory(at: tokenFile(home).deletingLastPathComponent(), withIntermediateDirectories: true)
            let short = String(repeating: "a", count: 31)
            try short.write(to: tokenFile(home), atomically: true, encoding: .utf8)
            let server = NotifyServer()
            #expect(server.token != short && server.token.count == 64)
            let stored = try String(contentsOf: tokenFile(home), encoding: .utf8)
            #expect(stored == server.token)
        }
    }

    @Test func anExistingTokenIsKeptTrimmedAndMadePrivate() throws {
        try withTempHome { home in
            try FileManager.default.createDirectory(at: tokenFile(home).deletingLastPathComponent(), withIntermediateDirectories: true)
            let existing = String(repeating: "b", count: 32)
            try (existing + "\n").write(to: tokenFile(home), atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: tokenFile(home).path)
            #expect(NotifyServer().token == existing)
            let mode = try permissions(tokenFile(home))
            #expect(mode == 0o600)
        }
    }
}
