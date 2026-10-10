import Foundation
import Testing
@testable import Nunsseop

struct ClaudeUsageAPITests {
    @Test func readsClaudeCodesKeychainEntry() throws {
        let nested = Data(#"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-x","expiresAt":1791300000000,"refreshToken":"r","scopes":["user:inference"]}}"#.utf8)
        let credentials = try #require(ClaudeUsageAPI.credentials(from: nested))
        #expect(credentials.token == "sk-ant-oat01-x")
        #expect(credentials.expiresAt == Date(timeIntervalSince1970: 1_791_300_000))
        #expect(ClaudeUsageAPI.credentials(from: Data(#"{"accessToken":"flat"}"#.utf8))?.token == "flat")
        #expect(ClaudeUsageAPI.credentials(from: Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8)) == nil)
        #expect(ClaudeUsageAPI.credentials(from: Data("not json".utf8)) == nil)
    }

    @Test func readsTheUsageResponse() throws {
        // As api.anthropic.com/api/oauth/usage answers, trimmed.
        let response = Data(#"""
        {"five_hour":{"utilization":12.0,"resets_at":"2026-10-06T20:00:00.498908+00:00","limit_dollars":null},
         "seven_day":{"utilization":48.0,"resets_at":"2026-10-07T22:00:00.498933+00:00"},
         "seven_day_opus":null,"extra_usage":{"is_enabled":false}}
        """#.utf8)
        let fetched = try #require(ClaudeUsageAPI.date("2026-10-06T18:00:00Z"))
        let limits = try #require(ClaudeUsageAPI.limits(from: response, fetchedAt: fetched))
        #expect(limits.session?.percent == 12)
        #expect(limits.weekly?.percent == 48)
        #expect(limits.session?.resetsAt == ClaudeUsageAPI.date("2026-10-06T20:00:00.498Z"))
        #expect(limits.updatedAt == fetched)
        // A window whose reset has passed has started over.
        let later = try #require(ClaudeUsageAPI.date("2026-10-06T21:00:00Z"))
        #expect(ClaudeUsageAPI.limits(from: response, fetchedAt: later)?.session?.percent == 0)
        #expect(ClaudeUsageAPI.limits(from: Data(#"{"type":"error"}"#.utf8), fetchedAt: fetched) == nil)
    }

    @Test func readsEachModelsWeeklyLimit() throws {
        // As the endpoint answers, trimmed: per-model limits come only in `limits`, the "seven_day_*" keys stay null.
        let response = Data(#"""
        {"five_hour":{"utilization":8.0,"resets_at":"2026-10-08T21:40:00.502316+00:00"},
         "seven_day":{"utilization":7.0,"resets_at":"2026-10-15T08:00:00.502335+00:00"},
         "seven_day_opus":null,"seven_day_oauth_apps":null,
         "limits":[{"kind":"session","group":"session","percent":8,"resets_at":"2026-10-08T21:40:00.502316+00:00","scope":null},
                   {"kind":"weekly_all","group":"weekly","percent":7,"resets_at":"2026-10-15T08:00:00.502335+00:00","scope":null},
                   {"kind":"weekly_scoped","group":"weekly","percent":0,"resets_at":"2026-10-15T08:00:00+00:00",
                    "scope":{"model":{"id":null,"display_name":"Fable"},"surface":null}},
                   {"kind":"weekly_scoped","group":"weekly","percent":12,"resets_at":"2026-10-15T08:00:00+00:00",
                    "scope":{"model":null,"surface":"cowork"}}]}
        """#.utf8)
        let fetched = try #require(ClaudeUsageAPI.date("2026-10-08T18:00:00Z"))
        let limits = try #require(ClaudeUsageAPI.limits(from: response, fetchedAt: fetched))
        // Only limits scoped to a model; one scoped to something else has no model name to show.
        #expect(limits.models.map(\.name) == ["Fable"])
        #expect(limits.models.first?.window.percent == 0)
        #expect(limits.models.first?.window.resetsAt == ClaudeUsageAPI.date("2026-10-15T08:00:00Z"))
        #expect(limits.weekly?.percent == 7)
        // Without `limits` there are no per-model bars.
        let older = Data(#"{"five_hour":{"utilization":1.0},"seven_day":{"utilization":2.0}}"#.utf8)
        #expect(ClaudeUsageAPI.limits(from: older, fetchedAt: fetched)?.models == [])
    }

    @Test func placeholdersOnlyWhileARequestIsOut() {
        #expect(ClaudeUsageAPI.status(signedOut: false, hasLimits: false, inFlight: true) == .waiting)
        // A request that failed or was put off leaves nothing on its way, so no placeholders.
        #expect(ClaudeUsageAPI.status(signedOut: false, hasLimits: false, inFlight: false) == .unavailable)
        #expect(ClaudeUsageAPI.status(signedOut: false, hasLimits: true, inFlight: true) == .ready)
        #expect(ClaudeUsageAPI.status(signedOut: true, hasLimits: true, inFlight: false) == .signedOut)
    }

    @Test func readsThePlanFromTheKeychainEntry() {
        let entry = Data(#"{"claudeAiOauth":{"accessToken":"t","subscriptionType":"max"}}"#.utf8)
        #expect(ClaudeUsageAPI.credentials(from: entry)?.plan == "Max")
        #expect(ClaudeUsageAPI.credentials(from: Data(#"{"claudeAiOauth":{"accessToken":"t"}}"#.utf8))?.plan == nil)
    }

    @Test func readsMicrosecondTimes() {
        let expected = Date(timeIntervalSince1970: 1_791_316_800.498)   // 2026-10-06T20:00:00.498Z
        #expect(ClaudeUsageAPI.date("2026-10-06T20:00:00.498908+00:00").map { abs($0.timeIntervalSince(expected)) < 0.001 } == true)
        #expect(ClaudeUsageAPI.date("2026-10-06T20:00:00.4+00:00") != nil)
        #expect(ClaudeUsageAPI.date("2026-10-06T20:00:00Z") == Date(timeIntervalSince1970: 1_791_316_800))
        #expect(ClaudeUsageAPI.date("yesterday") == nil)
    }

    @Test func namesNunsseopNotClaudeCode() {
        #expect(ClaudeUsageAPI.userAgent.hasPrefix("Nunsseop/"))
        #expect(!ClaudeUsageAPI.userAgent.lowercased().contains("claude"))
        // Without Claude Code's bucket the endpoint allows about one request an hour.
        #expect(ClaudeUsageAPI.interval == 3600)
    }

    @Test func passedResetsShowAsStartedOverWhenReturned() throws {
        let fetched = try #require(ClaudeUsageAPI.date("2026-10-06T18:00:00Z"))
        let resets = try #require(ClaudeUsageAPI.date("2026-10-06T20:00:00Z"))
        let limits = AIUsageModel.Limits(session: AIUsageModel.Window(percent: 80, resetsAt: resets),
                                         weekly: AIUsageModel.Window(percent: 40, resetsAt: resets.addingTimeInterval(86400)),
                                         updatedAt: fetched)
        // Still before the reset: as fetched.
        #expect(ClaudeUsageAPI.fresh(limits, now: resets.addingTimeInterval(-60)) == limits)
        // Long after, with nothing fetched since (an expired sign-in, say): the 5-hour window has started over.
        let later = ClaudeUsageAPI.fresh(limits, now: resets.addingTimeInterval(3600))
        #expect(later.session?.percent == 0 && later.session?.resetsAt == nil)
        #expect(later.weekly?.percent == 40)
    }

    @Test func requestCarriesTheSignInOnlyToAnthropic() {
        let request = ClaudeUsageAPI.request(token: "tok")
        #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == ClaudeUsageAPI.userAgent)
    }

    @Test func sessionKeepsNothingOnDisk() {
        let configuration = ClaudeUsageAPI.session.configuration
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        #expect(ClaudeUsageAPI.session.delegate != nil)   // refuses redirects
    }

    /// A redirect to another server isn't followed, so the token never reaches it.
    @Test func redirectsAreNotFollowed() async throws {
        let log = "/tmp/nunsseop-test-\(UUID().uuidString.prefix(8)).log"
        let script = """
        import http.server, sys, threading
        log = sys.argv[1]
        class Other(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                open(log, "a").write("other got: " + str(self.headers.get("Authorization")) + "\\n")
                self.send_response(200); self.end_headers(); self.wfile.write(b"{}")
            def log_message(self, *a): pass
        class First(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(302); self.send_header("Location", "http://localhost:%d/steal" % other.server_port); self.end_headers()
            def log_message(self, *a): pass
        other = http.server.HTTPServer(("127.0.0.1", 0), Other)
        first = http.server.HTTPServer(("127.0.0.1", 0), First)
        threading.Thread(target=other.serve_forever, daemon=True).start()
        print(first.server_port, flush=True)
        first.serve_forever()
        """
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-c", script, log]
        let output = Pipe()
        server.standardOutput = output
        try server.run()
        defer { server.terminate(); try? FileManager.default.removeItem(atPath: log) }
        let line = String(decoding: output.fileHandleForReading.availableData, as: UTF8.self)
        let port = try #require(Int(line.trimmingCharacters(in: .whitespacesAndNewlines)))

        var request = ClaudeUsageAPI.request(token: "secret-token")
        request.url = URL(string: "http://127.0.0.1:\(port)/api/oauth/usage")
        let (_, response) = try await ClaudeUsageAPI.session.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 302)
        #expect(!FileManager.default.fileExists(atPath: log))
    }

    /// Against the real endpoint with this Mac's sign-in; opt in with NUNSSEOP_LIVE_USAGE=1.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NUNSSEOP_LIVE_USAGE"] == "1"))
    func liveLimits() async throws {
        ClaudeUsageAPI.isEnabled = true
        let limits = try #require(await ClaudeUsageAPI.current())
        print("LIVE five-hour \(limits.session?.percent ?? -1)% weekly \(limits.weekly?.percent ?? -1)% resets \(String(describing: limits.session?.resetsAt))")
        #expect(limits.session != nil || limits.weekly != nil)
    }
}

struct ClaudeUsageAPISchedulingTests {
    private let now = Date(timeIntervalSince1970: 1_791_300_000)

    @Test(arguments: [
        // A refusal waits at least 10 minutes, as long as the server asks, but never more than 4 hours.
        (429, "30" as String?, 600.0), (429, "600", 600), (429, "1800", 1800), (429, "14400", 14400), (429, "999999", 14400),
        (429, "1e3", 1000), (429, "0", 600), (429, "-5", 600),
        // Retry-after values that aren't a plain number of seconds count as none.
        (429, "abc", 600), (429, "nan", 600), (429, "inf", 600), (429, "-inf", 600), (429, "Wed, 21 Oct 2026 07:28:00 GMT", 600), (429, nil, 600),
    ])
    func aRefusalWaitsAsLongAsTheServerAsksWithinBounds(status: Int, retryAfter: String?, wait: Double) {
        let reaction = ClaudeUsageAPI.reaction(status: status, retryAfter: retryAfter, parsed: false)
        #expect(reaction.wait == wait)
        #expect(!reaction.signedOut)
    }

    @Test func backoffFollowsTheResponse() {
        // Answered with limits: the booked hour stands.
        let ok = ClaudeUsageAPI.reaction(status: 200, retryAfter: nil, parsed: true)
        #expect(ok.wait == nil && !ok.signedOut)
        // Answered with something that isn't a usage response: soon again, still signed in.
        let garbled = ClaudeUsageAPI.reaction(status: 200, retryAfter: nil, parsed: false)
        #expect(garbled.wait == 600 && !garbled.signedOut)
        // Offline or unreachable.
        let offline = ClaudeUsageAPI.reaction(status: nil, retryAfter: "9999", parsed: false)
        #expect(offline.wait == 600 && !offline.signedOut)
        // A sign-in the server no longer accepts.
        for status in [401, 403] {
            let refused = ClaudeUsageAPI.reaction(status: status, retryAfter: "9999", parsed: false)
            #expect(refused.wait == 600 && refused.signedOut)
        }
    }

    @Test func claimAttemptBooksOneInterval() {
        var state = ClaudeUsageAPI.State()
        #expect(ClaudeUsageAPI.claimAttempt(&state, now: now))
        #expect(state.inFlight)
        #expect(state.nextAttempt == now.addingTimeInterval(3600))
        state.inFlight = false
        #expect(!ClaudeUsageAPI.claimAttempt(&state, now: now))
        #expect(!ClaudeUsageAPI.claimAttempt(&state, now: now.addingTimeInterval(3599)))
        #expect(!state.inFlight)
        #expect(state.nextAttempt == now.addingTimeInterval(3600))
        #expect(ClaudeUsageAPI.claimAttempt(&state, now: now.addingTimeInterval(3600)))
        #expect(state.inFlight)
        #expect(state.nextAttempt == now.addingTimeInterval(7200))
    }

    // MARK: Keychain entries

    private func entry(_ token: String, expiresAtMilliseconds: Double? = nil) -> Data {
        let expires = expiresAtMilliseconds.map { #","expiresAt":\#(Int64($0))"# } ?? ""
        return Data(#"{"claudeAiOauth":{"accessToken":"\#(token)"\#(expires)}}"#.utf8)
    }

    private var nowMilliseconds: Double { now.timeIntervalSince1970 * 1000 }

    @Test func expiredOrCorruptEntriesAreSkipped() {
        let expired = entry("old", expiresAtMilliseconds: nowMilliseconds - 1)
        let valid = entry("live", expiresAtMilliseconds: nowMilliseconds + 60_000)
        #expect(ClaudeUsageAPI.usable([expired, valid], now: now)?.token == "live")
        // Expiring this very moment counts as expired.
        #expect(ClaudeUsageAPI.usable([entry("edge", expiresAtMilliseconds: nowMilliseconds)], now: now) == nil)
        #expect(ClaudeUsageAPI.usable([entry("edge", expiresAtMilliseconds: nowMilliseconds + 1)], now: now)?.token == "edge")
        // No expiry given: valid. Nothing readable is skipped over.
        #expect(ClaudeUsageAPI.usable([nil, Data("garbage".utf8), entry("noexpiry")], now: now)?.token == "noexpiry")
        #expect(ClaudeUsageAPI.usable([expired, expired], now: now) == nil)
        #expect(ClaudeUsageAPI.usable([Data?](), now: now) == nil)
        // The first one wins.
        #expect(ClaudeUsageAPI.usable([entry("A"), entry("B")], now: now)?.token == "A")
    }

    @Test func theSecondLookupOnlyRunsWhenTheFirstFails() {
        var looked = 0
        let lookups = [entry("A"), entry("B")].lazy.map { data -> Data? in looked += 1; return data }
        #expect(ClaudeUsageAPI.usable(lookups, now: now)?.token == "A")
        #expect(looked == 1)
    }

    // MARK: Resets

    @Test func passedResetsZeroModelAndWeeklyWindows() throws {
        let response = Data(#"""
        {"five_hour":{"utilization":50.0,"resets_at":"2026-10-06T22:00:00+00:00"},
         "seven_day":{"utilization":70.0,"resets_at":"2026-10-06T20:00:00+00:00"},
         "limits":[{"kind":"weekly_scoped","percent":95,"resets_at":"2026-10-06T20:00:00+00:00","scope":{"model":{"display_name":"Fable"}}},
                   {"kind":"weekly_scoped","percent":60,"resets_at":"2026-10-08T20:00:00+00:00","scope":{"model":{"display_name":"Opus"}}},
                   {"kind":"weekly_scoped","percent":30,"scope":{"model":{"display_name":"Sonnet"}}},
                   {"kind":"weekly_scoped","percent":10,"scope":{"model":{"display_name":""}}},
                   {"kind":"weekly_scoped","percent":"20","scope":{"model":{"display_name":"Haiku"}}},
                   {"kind":"weekly_all","percent":99,"scope":{"model":{"display_name":"Other"}}}]}
        """#.utf8)
        let fetched = try #require(ClaudeUsageAPI.date("2026-10-06T21:00:00Z"))
        let limits = try #require(ClaudeUsageAPI.limits(from: response, fetchedAt: fetched))
        #expect(limits.weekly == AIUsageModel.Window(percent: 0, resetsAt: nil))
        #expect(limits.session?.percent == 50)
        #expect(limits.models == [
            AIUsageModel.ModelWindow(name: "Fable", window: .init(percent: 0, resetsAt: nil)),
            AIUsageModel.ModelWindow(name: "Opus", window: .init(percent: 60, resetsAt: ClaudeUsageAPI.date("2026-10-08T20:00:00Z"))),
            AIUsageModel.ModelWindow(name: "Sonnet", window: .init(percent: 30, resetsAt: nil)),
        ])
        // Before the reset the percentages stand.
        let earlier = try #require(ClaudeUsageAPI.date("2026-10-06T19:00:00Z"))
        let before = try #require(ClaudeUsageAPI.limits(from: response, fetchedAt: earlier))
        #expect(before.weekly?.percent == 70)
        #expect(before.models.first == AIUsageModel.ModelWindow(name: "Fable", window: .init(percent: 95, resetsAt: ClaudeUsageAPI.date("2026-10-06T20:00:00Z"))))
    }

    @Test func rolloverZeroesTheWeeklyAndModelWindowsOfOldLimits() throws {
        let reset = try #require(ClaudeUsageAPI.date("2026-10-07T20:00:00Z"))
        let window = AIUsageModel.Window(percent: 95, resetsAt: reset)
        let limits = AIUsageModel.Limits(weekly: window, models: [AIUsageModel.ModelWindow(name: "Fable", window: window)],
                                         updatedAt: reset.addingTimeInterval(-3600))
        let after = ClaudeUsageAPI.fresh(limits, now: reset.addingTimeInterval(1))
        #expect(after.weekly == AIUsageModel.Window(percent: 0, resetsAt: nil))
        #expect(after.models == [AIUsageModel.ModelWindow(name: "Fable", window: .init(percent: 0, resetsAt: nil))])
        #expect(after.updatedAt == limits.updatedAt)
        #expect(ClaudeUsageAPI.fresh(limits, now: reset.addingTimeInterval(-1)) == limits)
        // Exactly at the reset it hasn't passed yet.
        #expect(ClaudeUsageAPI.fresh(limits, now: reset) == limits)
    }
}
