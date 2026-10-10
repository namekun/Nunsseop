import AppKit
import Combine
import SwiftUI

struct NowPlayingTrack: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var position: Double
    var isPlaying: Bool
    var sourceBundleID: String
    var fetchedAt: Date
    /// Playback speed while playing; kept while paused so the speed control shows it.
    var rate: Double = 1
    var canSeek = true
    var canChangeRate = false

    func position(at date: Date) -> Double {
        guard isPlaying else { return position }
        let live = position + date.timeIntervalSince(fetchedAt) * rate
        // Streams report no duration; there is no end to clamp to.
        return duration > 0 ? min(duration, live) : live
    }

    var identity: String { "\(sourceBundleID)|\(title)|\(artist)|\(album)" }
}

enum NowPlayingCommand {
    case playPause, next, previous
    case seek(Double)
    case rate(Double)
}

/// Reads playback state from apps that expose it over AppleScript. Each source
/// needs the user's Automation consent the first time it is queried.
struct ScriptSource {
    let bundleID: String
    let durationScale: Double
    let stateScript: String
    let artworkScript: String
    let artworkIsURL: Bool

    /// Nil for commands these apps have no AppleScript for.
    func command(_ command: NowPlayingCommand) -> String? {
        let verb: String
        switch command {
        case .playPause: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        case .seek(let seconds): verb = "set player position to \(max(0, seconds))"
        case .rate: return nil
        }
        return "tell application id \"\(bundleID)\" to \(verb)"
    }

    static let music = ScriptSource(
        bundleID: "com.apple.Music",
        durationScale: 1,
        stateScript: """
        tell application id "com.apple.Music"
            if player state is stopped then return {"stopped"}
            set t to current track
            return {player state as text, name of t, artist of t, album of t, duration of t, player position}
        end tell
        """,
        artworkScript: """
        tell application id "com.apple.Music" to return data of artwork 1 of current track
        """,
        artworkIsURL: false
    )

    static let spotify = ScriptSource(
        bundleID: "com.spotify.client",
        durationScale: 1.0 / 1000,
        stateScript: """
        tell application id "com.spotify.client"
            if player state is stopped then return {"stopped"}
            set t to current track
            return {player state as text, name of t, artist of t, album of t, duration of t, player position}
        end tell
        """,
        artworkScript: """
        tell application id "com.spotify.client" to return artwork url of current track
        """,
        artworkIsURL: true
    )
}

@MainActor
final class NowPlayingController: ObservableObject {
    @Published private(set) var track: NowPlayingTrack?
    @Published private(set) var artwork: NSImage? {
        didSet { tint = artwork.map(ArtworkTint.color(for:)) ?? .white }
    }
    @Published private(set) var tint: Color = .white
    @Published private(set) var needsAutomationPermission = false
    /// Bundle ID of a browser that refused to run JavaScript from Apple Events.
    @Published private(set) var browserNeedingJavaScript: String?

    private let sources: [ScriptSource] = [.music, .spotify]
    private let queue = DispatchQueue(label: "nunsseop.nowplaying")
    private var timer: Timer?
    private var artworkIdentity: String?
    /// The MediaRemote artwork bytes behind `artwork`, so unchanged artwork isn't decoded again.
    private var artworkBytes: Data?
    private var browserHit: BrowserMedia.Hit?
    private var pollInFlight = false
    private let mediaRemote = MediaRemoteBridge()
    /// True while the MediaRemote helper is delivering updates; the AppleScript
    /// and browser sources are only polled when it is not.
    private var mediaRemoteActive = false

    private struct PollResult {
        var candidates: [NowPlayingTrack] = []
        var browserHits: [String: BrowserMedia.Hit] = [:]
        var denied = false
        var javaScriptDisabledIn: String?
    }

    func start() {
        #if DEBUG
        if CommandLine.arguments.contains("--demo-track") {
            showDemoTrack()
            return
        }
        #endif
        mediaRemote.onUpdate = { [weak self] update in self?.apply(update) }
        mediaRemote.onUnavailable = { [weak self] in self?.mediaRemoteActive = false }
        mediaRemote.start()
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer?.tolerance = 0.15
    }

    func send(_ command: NowPlayingCommand) {
        if case .seek(let seconds) = command, !seconds.isFinite { return }
        if case .seek(let seconds) = command, var current = track {
            current.position = seconds
            current.fetchedAt = Date()
            track = current
        }
        if case .rate(let rate) = command, var current = track {
            current.position = current.position(at: Date())
            current.fetchedAt = Date()
            current.rate = rate
            track = current
        }
        if mediaRemoteActive {
            mediaRemote.send(command)
            return
        }
        guard let bundleID = track?.sourceBundleID else { return }
        let work: () -> Void
        if let source = sources.first(where: { $0.bundleID == bundleID }) {
            guard let script = source.command(command) else { return }
            work = { _ = Self.run(script) }
        } else if let hit = browserHit, hit.track.sourceBundleID == bundleID,
                  let browser = BrowserMedia.all.first(where: { $0.bundleID == bundleID }) {
            work = { browser.send(command, at: hit.location) }
        } else {
            return
        }
        queue.async { [weak self] in
            work()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.poll()
            }
        }
    }

    /// Jumps by `seconds` from the current position, within the track.
    func skip(by seconds: Double) {
        guard let track, track.canSeek, track.duration > 0 else { return }
        // Stop just short of the end so players don't jump to the next track.
        send(.seek(Self.skipTarget(position: track.position(at: Date()), duration: track.duration, by: seconds)))
    }

    nonisolated static func skipTarget(position: Double, duration: Double, by seconds: Double) -> Double {
        min(max(0, duration - 1), max(0, position + seconds))
    }

    /// Steps through 1×, 1.25×, 1.5× and 2×, then back to 1×.
    func cycleRate() {
        guard let track, track.canChangeRate else { return }
        send(.rate(Self.nextRate(after: track.rate)))
    }

    nonisolated static func nextRate(after rate: Double) -> Double {
        let rates: [Double] = [1, 1.25, 1.5, 2]
        return rates.first { $0 > rate + 0.01 } ?? 1
    }

    private func poll() {
        guard !mediaRemoteActive, !pollInFlight else { return }
        pollInFlight = true
        let isRunning = { (id: String) in !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty }
        let apps = sources.filter { isRunning($0.bundleID) }
        let browsers = BrowserMedia.all.filter { isRunning($0.bundleID) }
        queue.async { [weak self] in
            var result = PollResult()
            for source in apps {
                switch Self.run(source.stateScript) {
                case .success(let descriptor):
                    if let track = Self.parse(descriptor, source: source) { result.candidates.append(track) }
                case .failure(let error):
                    if error.code == -1743 { result.denied = true }
                }
            }
            for browser in browsers {
                switch browser.scan() {
                case .success(let hit?):
                    result.candidates.append(hit.track)
                    result.browserHits[browser.bundleID] = hit
                case .success(nil):
                    break
                case .failure(.notAuthorized):
                    result.denied = true
                case .failure(.javaScriptDisabled):
                    result.javaScriptDisabledIn = browser.bundleID
                case .failure(.other):
                    break
                }
            }
            DispatchQueue.main.async {
                self?.pollInFlight = false
                self?.apply(result)
            }
        }
    }

    private func apply(_ update: MediaRemoteUpdate) {
        // A restarted helper sends its artwork again, and the other sources may have replaced it meanwhile.
        if !mediaRemoteActive { artworkBytes = nil }
        mediaRemoteActive = true
        browserHit = nil
        needsAutomationPermission = false
        browserNeedingJavaScript = nil
        var newTrack = update.track
        if let current = track, var paused = newTrack, !paused.isPlaying, current.identity == paused.identity {
            paused.rate = current.rate
            newTrack = paused
        }
        if track != newTrack { track = newTrack }
        guard let newTrack else {
            artwork = nil
            artworkIdentity = nil
            artworkBytes = nil
            return
        }
        // Same artwork as before, also on the next track of the same album.
        if update.artworkUnchanged {
            artworkIdentity = newTrack.identity
            // Out of step with the helper: there is nothing to keep.
            if artworkBytes == nil { mediaRemote.resendArtwork() }
            return
        }
        if newTrack.identity != artworkIdentity {
            artworkIdentity = newTrack.identity
            artwork = nil
            artworkBytes = nil
        }
        if let data = update.artwork, data != artworkBytes, let image = NSImage(data: data) {
            artwork = image
            artworkBytes = data
        }
    }

    private func apply(_ result: PollResult) {
        guard !mediaRemoteActive else { return }
        let newTrack = result.candidates.first(where: \.isPlaying) ?? result.candidates.first
        browserHit = newTrack.flatMap { result.browserHits[$0.sourceBundleID] }
        needsAutomationPermission = result.denied && newTrack == nil
        browserNeedingJavaScript = newTrack == nil ? result.javaScriptDisabledIn : nil
        if track != newTrack { track = newTrack }
        guard let newTrack else {
            artwork = nil
            artworkIdentity = nil
            return
        }
        if newTrack.identity != artworkIdentity {
            artworkIdentity = newTrack.identity
            artwork = nil
            loadArtwork(for: newTrack)
        }
    }

    private func loadArtwork(for track: NowPlayingTrack) {
        let identity = track.identity
        if let hit = browserHit {
            guard let url = hit.artworkURL, Self.isAllowedArtworkURL(url) else { return }
            Self.artworkSession.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, data.count <= Self.maxArtworkBytes, let image = NSImage(data: data) else { return }
                DispatchQueue.main.async { self?.setArtwork(image, for: identity) }
            }.resume()
            return
        }
        guard let source = sources.first(where: { $0.bundleID == track.sourceBundleID }) else { return }
        queue.async { [weak self] in
            guard case .success(let result) = Self.run(source.artworkScript) else { return }
            if source.artworkIsURL {
                guard let string = result.stringValue, let url = URL(string: string),
                      Self.isAllowedArtworkURL(url) else { return }
                Self.artworkSession.dataTask(with: url) { data, _, _ in
                    guard let data, data.count <= Self.maxArtworkBytes, let image = NSImage(data: data) else { return }
                    DispatchQueue.main.async { self?.setArtwork(image, for: identity) }
                }.resume()
            } else if let image = NSImage(data: result.data) {
                DispatchQueue.main.async { self?.setArtwork(image, for: identity) }
            }
        }
    }

    nonisolated private static let maxArtworkBytes = 5_000_000

    nonisolated private static let artworkSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        return URLSession(configuration: configuration)
    }()

    /// Image hosts of the services the fallback sources read. Artwork URLs can come
    /// from web pages, so nothing else is fetched.
    nonisolated private static let artworkHosts = [
        "ytimg.com", "ggpht.com", "googleusercontent.com", "scdn.co", "spotifycdn.com",
        "sndcdn.com", "mzstatic.com", "tidal.com", "dzcdn.net", "bcbits.com", "jtvnw.net",
        "vimeocdn.com", "nflxext.com", "nflximg.net", "media-amazon.com", "ssl-images-amazon.com",
        "pandora.com", "pstatic.net", "melon.co.kr", "genie.co.kr", "music-flo.com", "bugs.co.kr",
    ]

    nonisolated static func isAllowedArtworkURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return artworkHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// For the AppleScript and browser sources; a late fetch must not replace MediaRemote's artwork.
    private func setArtwork(_ image: NSImage, for identity: String) {
        if !mediaRemoteActive && identity == artworkIdentity { artwork = image }
    }

    /// Fixed track with generated artwork, for checking the layout without a player.
    private func showDemoTrack() {
        // --demo-long-track shows a podcast-length track, which adds the skip and speed controls.
        let long = CommandLine.arguments.contains("--demo-long-track")
        track = NowPlayingTrack(title: long ? "Episode 112: Long Conversations" : "Midnight Drive",
                                artist: "The Demo Band", album: "Night Roads",
                                duration: long ? 3_720 : 214, position: long ? 1_250 : 71, isPlaying: true,
                                sourceBundleID: "com.apple.Music", fetchedAt: Date(),
                                rate: long ? 1.5 : 1, canChangeRate: long)
        artwork = Self.demoArtwork
    }

    /// A night road under a moon, in flat colors, so screenshots don't lean on a stock gradient.
    private static let demoArtwork = NSImage(size: NSSize(width: 300, height: 300), flipped: false) { rect in
        NSColor(srgbRed: 0.08, green: 0.10, blue: 0.13, alpha: 1).setFill()
        rect.fill()
        NSColor(srgbRed: 0.91, green: 0.90, blue: 0.86, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 196, y: 206, width: 40, height: 40)).fill()
        let horizon: CGFloat = 132
        NSColor(srgbRed: 0.16, green: 0.19, blue: 0.24, alpha: 1).setFill()
        let road = NSBezierPath()
        road.move(to: NSPoint(x: 0, y: 0))
        road.line(to: NSPoint(x: 300, y: 0))
        road.line(to: NSPoint(x: 156, y: horizon))
        road.line(to: NSPoint(x: 144, y: horizon))
        road.close()
        road.fill()
        // Dashes shrink toward the horizon.
        NSColor(srgbRed: 0.95, green: 0.66, blue: 0.23, alpha: 1).setFill()
        for (bottom, top) in [(8.0, 46.0), (62.0, 86.0), (98.0, 112.0), (120.0, 127.0)] as [(CGFloat, CGFloat)] {
            let half = { (y: CGFloat) in 7 * (1 - y / horizon) + 0.5 }
            let dash = NSBezierPath()
            dash.move(to: NSPoint(x: 150 - half(bottom), y: bottom))
            dash.line(to: NSPoint(x: 150 + half(bottom), y: bottom))
            dash.line(to: NSPoint(x: 150 + half(top), y: top))
            dash.line(to: NSPoint(x: 150 - half(top), y: top))
            dash.close()
            dash.fill()
        }
        return true
    }

    private struct ScriptError: Error { let code: Int }

    nonisolated private static func run(_ source: String) -> Result<NSAppleEventDescriptor, ScriptError> {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return .failure(ScriptError(code: 0)) }
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            return .failure(ScriptError(code: errorInfo[NSAppleScript.errorNumber] as? Int ?? 0))
        }
        return .success(result)
    }

    nonisolated static func parse(_ d: NSAppleEventDescriptor, source: ScriptSource) -> NowPlayingTrack? {
        guard d.numberOfItems >= 6, let state = d.atIndex(1)?.stringValue, state != "stopped" else { return nil }
        return NowPlayingTrack(
            title: d.atIndex(2)?.stringValue ?? "",
            artist: d.atIndex(3)?.stringValue ?? "",
            album: d.atIndex(4)?.stringValue ?? "",
            duration: (d.atIndex(5)?.doubleValue ?? 0) * source.durationScale,
            position: d.atIndex(6)?.doubleValue ?? 0,
            isPlaying: state == "playing",
            sourceBundleID: source.bundleID,
            fetchedAt: Date()
        )
    }
}
