import Foundation
import os

/// Claude's limits straight from Anthropic, asked with the sign-in Claude Code keeps in the Keychain, so they're
/// current whatever spends them (Claude Code, apps built on the Agent SDK, claude.ai), not only while the
/// oh-my-claudecode HUD runs. Off until the user agrees. The token is only read: an expired one is skipped, never
/// refreshed, since Claude Code rotates it and a second writer could log it out; the limits then stop updating until
/// Claude Code signs in again. It goes nowhere but api.anthropic.com, and Nunsseop names itself, not Claude Code.
enum ClaudeUsageAPI {
    static let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    /// How often the limits are asked for: a client that isn't Claude Code gets about one request an hour.
    static let interval: TimeInterval = 3600
    /// After a refusal (429) at least this long passes before asking again, longer if the server says so.
    static let backoff: TimeInterval = 600

    struct Credentials: Equatable {
        let token: String
        let expiresAt: Date?
        /// The subscription, such as "Max", when the entry names one.
        var plan: String?
    }

    private struct State {
        var limits: AIUsageModel.Limits?
        /// No usable sign-in at the last attempt: none in the Keychain, expired, or refused by the server.
        var signedOut = false
        /// A request to Anthropic is on its way.
        var inFlight = false
        var nextAttempt = Date.distantPast
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    /// Follows no redirects, so the sign-in can't be carried to another host, and keeps no cache or cookies,
    /// so the request with its Authorization header is never written to disk.
    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }()

    /// Whether to ask at all (Settings › Services); read from the background, so it's stored atomically.
    private static let enabledFlag = OSAllocatedUnfairLock(initialState: true)
    static var isEnabled: Bool {
        get { enabledFlag.withLock { $0 } }
        set { enabledFlag.withLock { $0 = newValue } }
    }

    enum Status: Equatable {
        /// Not asked at all.
        case off
        /// A request is on its way and no limits are known yet.
        case waiting
        /// No limits are known and none are on their way: the last request failed, or the server put it off.
        case unavailable
        /// Claude Code's sign-in is missing or no longer works.
        case signedOut
        case ready
    }

    static var status: Status {
        guard isEnabled else { return .off }
        return state.withLock { status(signedOut: $0.signedOut, hasLimits: $0.limits != nil, inFlight: $0.inFlight) }
    }

    /// Placeholders only stand in while a request is out, so an answer that never comes doesn't leave them pulsing.
    static func status(signedOut: Bool, hasLimits: Bool, inFlight: Bool) -> Status {
        if signedOut { return .signedOut }
        if hasLimits { return .ready }
        return inFlight ? .waiting : .unavailable
    }

    // MARK: Parsing

    /// Claude Code's Keychain entry: `{"claudeAiOauth": {"accessToken", "expiresAt" (ms), "subscriptionType"}}`.
    static func credentials(from data: Data) -> Credentials? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let oauth = json["claudeAiOauth"] as? [String: Any] ?? json
        guard let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        let expires = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        let plan = (oauth["subscriptionType"] as? String).flatMap { $0.isEmpty ? nil : $0.capitalized }
        return Credentials(token: token, expiresAt: expires, plan: plan)
    }

    /// The 5-hour and 7-day windows of a usage response.
    static func limits(from data: Data, fetchedAt: Date) -> AIUsageModel.Limits? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func window(_ key: String) -> AIUsageModel.Window? {
            guard let entry = json[key] as? [String: Any], let percent = entry["utilization"] as? Double else { return nil }
            let resets = (entry["resets_at"] as? String).flatMap(date)
            if let resets, resets < fetchedAt { return AIUsageModel.Window(percent: 0, resetsAt: nil) }
            return AIUsageModel.Window(percent: percent, resetsAt: resets)
        }
        let session = window("five_hour"), weekly = window("seven_day")
        guard session != nil || weekly != nil else { return nil }
        // A model with a weekly limit of its own is a "weekly_scoped" entry of `limits`, named by its scope.
        let models = (json["limits"] as? [[String: Any]] ?? []).compactMap { entry -> AIUsageModel.ModelWindow? in
            guard entry["kind"] as? String == "weekly_scoped",
                  let model = (entry["scope"] as? [String: Any])?["model"] as? [String: Any],
                  let name = model["display_name"] as? String, !name.isEmpty,
                  let percent = (entry["percent"] as? NSNumber)?.doubleValue else { return nil }
            let resets = (entry["resets_at"] as? String).flatMap(date)
            let window = resets.map { $0 < fetchedAt } == true
                ? AIUsageModel.Window(percent: 0, resetsAt: nil) : AIUsageModel.Window(percent: percent, resetsAt: resets)
            return AIUsageModel.ModelWindow(name: name, window: window)
        }
        return AIUsageModel.Limits(session: session, weekly: weekly, models: models, updatedAt: fetchedAt)
    }

    /// ISO 8601 times with up to microseconds (`2026-10-06T20:00:00.498908+00:00`), which ISO8601DateFormatter
    /// doesn't read beyond milliseconds, so the fraction is cut to three digits first.
    static func date(_ text: String) -> Date? {
        var text = text
        if let dot = text.firstIndex(of: "."),
           let end = text[dot...].firstIndex(where: { !$0.isNumber && $0 != "." }) {
            let digits = text[text.index(after: dot)..<end]
            text.replaceSubrange(dot..<end, with: "." + digits.prefix(3).padding(toLength: 3, withPad: "0", startingAt: 0))
        }
        let fractional = ISO8601DateFormatter(), whole = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? whole.date(from: text)
    }

    /// Nunsseop and its version, rather than borrowing Claude Code's name.
    static var userAgent: String {
        "Nunsseop/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")"
    }

    static func request(token: String) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Windows whose reset time has passed have started over, however long ago the limits were fetched
    /// (an expired sign-in or a run of refusals can keep them from being fetched again).
    static func fresh(_ limits: AIUsageModel.Limits, now: Date) -> AIUsageModel.Limits {
        func reset(_ window: AIUsageModel.Window?) -> AIUsageModel.Window? {
            guard let window, let resets = window.resetsAt, resets < now else { return window }
            return AIUsageModel.Window(percent: 0, resetsAt: nil)
        }
        var limits = limits
        limits.session = reset(limits.session)
        limits.weekly = reset(limits.weekly)
        limits.models = limits.models.compactMap { model in reset(model.window).map { AIUsageModel.ModelWindow(name: model.name, window: $0) } }
        return limits
    }

    // MARK: Asking

    /// The last limits, asking Anthropic again when they're due.
    static func current(now: Date = .now) async -> AIUsageModel.Limits? {
        guard isEnabled else { return nil }
        if claimAttempt(now: now) { await fetch(now: now) }
        return state.withLock { $0.limits }.map { fresh($0, now: now) }
    }

    /// The last limits without waiting for Anthropic, so what's known shows at once: a request that is due starts
    /// in the background, and `answered` runs once it is done.
    static func latest(now: Date = .now, answered: @escaping @Sendable () -> Void) -> AIUsageModel.Limits? {
        guard isEnabled else { return nil }
        if claimAttempt(now: now) {
            Task.detached(priority: .utility) {
                await fetch(now: now)
                answered()
            }
        }
        return state.withLock { $0.limits }.map { fresh($0, now: now) }
    }

    /// Whether a request is due, booking the next one if so.
    private static func claimAttempt(now: Date) -> Bool {
        state.withLock { state -> Bool in
            guard now >= state.nextAttempt else { return false }
            state.nextAttempt = now.addingTimeInterval(interval)
            state.inFlight = true
            return true
        }
    }

    private static func fetch(now: Date) async {
        defer { state.withLock { $0.inFlight = false } }
        guard let credentials = keychainCredentials(now: now) else {
            // Not signed in, or the sign-in expired: asked again later, not on every refresh.
            state.withLock { $0.nextAttempt = now.addingTimeInterval(backoff); $0.signedOut = true }
            return
        }
        // A sign-in is there again, so the warning goes even if this request then fails.
        state.withLock { $0.signedOut = false }
        guard let (data, response) = try? await session.data(for: request(token: credentials.token)),
              let response = response as? HTTPURLResponse else {
            // Offline or unreachable: soon again, not after the full interval.
            state.withLock { $0.nextAttempt = now.addingTimeInterval(backoff) }
            return
        }
        switch response.statusCode {
        case 200:
            if var fetched = limits(from: data, fetchedAt: .now) {
                fetched.plan = credentials.plan
                let limits = fetched
                state.withLock { $0.limits = limits }
            } else {
                state.withLock { $0.nextAttempt = now.addingTimeInterval(backoff) }
            }
        case 429:
            // Capped, so an odd retry-after can't switch this off until relaunch.
            let asked = response.value(forHTTPHeaderField: "retry-after").flatMap(Double.init) ?? 0
            let wait = min(max(backoff, asked.isFinite ? asked : 0), interval * 4)
            state.withLock { $0.nextAttempt = now.addingTimeInterval(wait) }
        default:
            // 401/403: a token that stopped working; Claude Code will sign in again, and it's asked later.
            state.withLock { $0.nextAttempt = now.addingTimeInterval(backoff); $0.signedOut = true }
        }
    }

    /// The user's own entry first: an older one under the account "Claude Code" can linger, long expired.
    private static func keychainCredentials(now: Date) -> Credentials? {
        for account in [NSUserName(), nil] {
            var arguments = ["find-generic-password", "-s", "Claude Code-credentials"]
            if let account { arguments += ["-a", account] }
            guard let output = run("/usr/bin/security", arguments + ["-w"]),
                  let credentials = credentials(from: Data(output.utf8)) else { continue }
            if let expires = credentials.expiresAt, expires <= now { continue }
            return credentials
        }
        return nil
    }

    private static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        // A child that ignores SIGTERM gets SIGKILL, so a hung `security` can't stall every refresh.
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            guard process.isRunning else { return }
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
