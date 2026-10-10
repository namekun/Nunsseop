import AppKit

/// Reads media playing in browser tabs through each browser's AppleScript
/// JavaScript bridge. Requires Automation consent and, per browser, the
/// "Allow JavaScript from Apple Events" developer setting.
struct BrowserMedia {
    enum Dialect { case chromium, safari }

    let bundleID: String
    let dialect: Dialect

    static let all: [BrowserMedia] = [
        BrowserMedia(bundleID: "com.apple.Safari", dialect: .safari),
        BrowserMedia(bundleID: "com.google.Chrome", dialect: .chromium),
        BrowserMedia(bundleID: "com.microsoft.edgemac", dialect: .chromium),
        BrowserMedia(bundleID: "com.brave.Browser", dialect: .chromium),
        BrowserMedia(bundleID: "company.thebrowser.Browser", dialect: .chromium),
        BrowserMedia(bundleID: "company.thebrowser.dia", dialect: .chromium),
        BrowserMedia(bundleID: "at.studio.AsideBrowser", dialect: .chromium),
        BrowserMedia(bundleID: "com.naver.Whale", dialect: .chromium),
        BrowserMedia(bundleID: "com.vivaldi.Vivaldi", dialect: .chromium),
        BrowserMedia(bundleID: "com.operasoftware.Opera", dialect: .chromium),
    ]

    struct Location: Equatable {
        let window: Int
        let tab: Int
        /// The tab's URL when it was scanned; scripts only run if the tab still shows it.
        let url: String
    }

    struct Hit {
        let track: NowPlayingTrack
        let artworkURL: URL?
        let location: Location
    }

    enum Failure: Error {
        case notAuthorized
        case javaScriptDisabled
        case other
    }

    /// Tabs on these hosts are probed; probing every tab on each poll would be too slow.
    private static let mediaHosts = [
        "music.youtube.com", "youtube.com", "youtu.be", "open.spotify.com", "soundcloud.com",
        "music.apple.com", "tidal.com", "deezer.com", "bandcamp.com", "twitch.tv", "vimeo.com",
        "netflix.com", "music.amazon.com","pandora.com", "vibe.naver.com", "melon.com",
        "genie.co.kr", "music-flo.com", "music.bugs.co.kr", "chzzk.naver.com", "laftel.net",
    ]

    // JavaScript sources use single quotes only, which keeps them readable; they are escaped into AppleScript strings all the same.
    private static let stateJS = """
    (() => { const els = [...document.querySelectorAll('video,audio')]; \
    const m = els.find(e => !e.paused) || els.find(e => e.currentTime > 0); \
    const md = navigator.mediaSession && navigator.mediaSession.metadata; \
    if (!m && !md) return ''; \
    const art = md && md.artwork && md.artwork.length ? md.artwork[md.artwork.length - 1].src : ''; \
    return JSON.stringify({ title: md && md.title ? md.title : document.title, \
    artist: md ? md.artist : '', album: md ? md.album : '', art: art, \
    playing: m ? !m.paused : navigator.mediaSession.playbackState === 'playing', \
    pos: m ? m.currentTime : 0, dur: m && isFinite(m.duration) ? m.duration : 0, \
    el: !!m, rate: m ? m.playbackRate : 1 }); })()
    """

    private static func clickJS(_ selectors: [String], fallback: String) -> String {
        let list = selectors.map { "'\($0)'" }.joined(separator: ",")
        return """
        (() => { for (const q of [\(list)]) { const b = document.querySelector(q); \
        if (b) { b.click(); return; } } \(fallback) })()
        """
    }

    static func commandJS(_ command: NowPlayingCommand) -> String {
        let media = "const els = [...document.querySelectorAll('video,audio')]; " +
            "const m = els.find(e => !e.paused) || els.find(e => e.currentTime > 0);"
        switch command {
        case .playPause:
            return clickJS(["ytmusic-player-bar #play-pause-button",
                            "[data-testid=control-button-playpause]",
                            ".playControls .playControl"],
                           fallback: "\(media) if (m) { m.paused ? m.play() : m.pause(); }")
        case .next:
            return clickJS(["ytmusic-player-bar .next-button", ".ytp-next-button",
                            "[data-testid=control-button-skip-forward]", ".skipControl__next"],
                           fallback: "\(media) if (m && isFinite(m.duration)) { m.currentTime = Math.min(m.duration, m.currentTime + 10); }")
        case .seek(let seconds):
            return "(() => { \(media) if (m) { m.currentTime = \(max(0, seconds)); } })()"
        case .rate(let rate):
            return "(() => { \(media) if (m) { m.playbackRate = \(rate); } })()"
        case .previous:
            return clickJS(["ytmusic-player-bar .previous-button", ".ytp-prev-button",
                            "[data-testid=control-button-skip-back]", ".skipControl__previous"],
                           fallback: "\(media) if (m) { m.currentTime = Math.max(0, m.currentTime - 10); }")
        }
    }

    private func execute(_ js: String, window: String, tab: String) -> String {
        switch dialect {
        case .chromium:
            return "execute tab \(tab) of window \(window) javascript \(Self.appleScriptLiteral(js))"
        case .safari:
            return "do JavaScript \(Self.appleScriptLiteral(js)) in tab \(tab) of window \(window)"
        }
    }

    /// Private (incognito) windows report no tabs, so their titles never reach the notch.
    private var tabURLsScript: String {
        let privateCheck = dialect == .chromium
            ? "try\n                if mode of window w is \"incognito\" then set isPrivate to true\n            end try"
            : ""
        return """
        tell application id "\(bundleID)"
            set out to {}
            repeat with w from 1 to count of windows
                set isPrivate to false
                \(privateCheck)
                if isPrivate then
                    set end of out to {}
                else
                    set end of out to URL of every tab of window w
                end if
            end repeat
            return out
        end tell
        """
    }

    struct Tab {
        let url: String
        let title: String
        /// The tab in front of its window.
        let isActive: Bool
    }

    /// URL and title of every tab in non-private windows, and each window's front tab, for finding call tabs.
    private var tabsScript: String {
        """
        tell application id "\(bundleID)"
            set out to {}
            repeat with w from 1 to count of windows
                set isPrivate to false
                try
                    if mode of window w is "incognito" then set isPrivate to true
                end try
                if not isPrivate then
                    set activeURL to ""
                    try
                        set activeURL to URL of active tab of window w
                    end try
                    set end of out to {URL of every tab of window w, title of every tab of window w, activeURL}
                end if
            end repeat
            return out
        end tell
        """
    }

    /// Chromium browsers only; nil when the browser can't be asked.
    func tabs() -> [Tab]? {
        guard dialect == .chromium, case .success(let windows) = Self.run(tabsScript) else { return nil }
        var result: [Tab] = []
        for w in 0..<max(0, windows.numberOfItems) {
            guard let window = windows.atIndex(w + 1), let urls = window.atIndex(1), let titles = window.atIndex(2) else { continue }
            let active = window.atIndex(3)?.stringValue ?? ""
            for t in 0..<max(0, urls.numberOfItems) {
                guard let url = urls.atIndex(t + 1)?.stringValue else { continue }
                result.append(Tab(url: url, title: titles.atIndex(t + 1)?.stringValue ?? "", isActive: url == active))
            }
        }
        return result
    }

    /// Runs `js` in each non-private tab on `host` until one returns a non-empty string, without
    /// bringing the browser forward. Chromium browsers only; nil when none answered.
    func runInTabs(onHost host: String, _ js: String) -> String? {
        guard dialect == .chromium else { return nil }
        let script = """
        tell application id "\(bundleID)"
            repeat with w in windows
                set isPrivate to false
                try
                    if mode of w is "incognito" then set isPrivate to true
                end try
                if not isPrivate then
                    repeat with t in tabs of w
                        if URL of t starts with \(Self.appleScriptLiteral("https://" + host + "/")) then
                            set r to execute t javascript \(Self.appleScriptLiteral(js))
                            if r is not missing value and r is not "" then return r
                        end if
                    end repeat
                end if
            end repeat
            return ""
        end tell
        """
        guard case .success(let result) = Self.run(script), let value = result.stringValue, !value.isEmpty else { return nil }
        return value
    }

    static func appleScriptLiteral(_ string: String) -> String {
        "\"" + string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Runs `js` only if the tab at `location` still shows the URL it had when scanned.
    func guardedScript(_ js: String, at location: Location) -> String {
        let w = "\(location.window)", t = "\(location.tab)"
        return """
        tell application id "\(bundleID)"
            if (count of windows) < \(w) then return ""
            if (count of tabs of window \(w)) < \(t) then return ""
            if URL of tab \(t) of window \(w) is not \(Self.appleScriptLiteral(location.url)) then return ""
            return \(execute(js, window: w, tab: t))
        end tell
        """
    }

    static func isMediaSite(_ string: String) -> Bool {
        guard let url = URL(string: string), url.scheme == "https",
              let host = url.host?.lowercased() else { return false }
        return mediaHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Now Playing and calls both ask browsers from their own queues; their scripts run one at a time here.
    private static let scriptQueue = DispatchQueue(label: "nunsseop.browser-scripts")

    private static func run(_ source: String) -> Result<NSAppleEventDescriptor, Failure> {
        scriptQueue.sync { runNow(source) }
    }

    private static func runNow(_ source: String) -> Result<NSAppleEventDescriptor, Failure> {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return .failure(.other) }
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? ""
            return .failure(failure(code: code, message: message))
        }
        return .success(result)
    }

    static func failure(code: Int, message: String) -> Failure {
        if code == -1743 { return .notAuthorized }
        if message.localizedCaseInsensitiveContains("javascript") { return .javaScriptDisabled }
        return .other
    }

    func scan() -> Result<Hit?, Failure> {
        let windows: NSAppleEventDescriptor
        switch Self.run(tabURLsScript) {
        case .success(let d): windows = d
        case .failure(let f): return .failure(f)
        }
        var locations: [Location] = []
        for w in 0..<max(0, windows.numberOfItems) {
            guard let tabs = windows.atIndex(w + 1) else { continue }
            for t in 0..<max(0, tabs.numberOfItems) {
                if let url = tabs.atIndex(t + 1)?.stringValue, Self.isMediaSite(url) {
                    locations.append(Location(window: w + 1, tab: t + 1, url: url))
                }
            }
        }
        for location in locations {
            switch Self.run(guardedScript(Self.stateJS, at: location)) {
            case .success(let d):
                if let hit = makeHit(d.stringValue, location: location) { return .success(hit) }
            case .failure(.other):
                continue
            case .failure(let f):
                return .failure(f)
            }
        }
        return .success(nil)
    }

    func makeHit(_ jsonString: String?, location: Location) -> Hit? {
        guard let json = jsonString?.data(using: .utf8),
              let info = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }

        let hasElement = info["el"] as? Bool ?? false
        let track = NowPlayingTrack(
            title: info["title"] as? String ?? "",
            artist: info["artist"] as? String ?? "",
            album: info["album"] as? String ?? "",
            duration: info["dur"] as? Double ?? 0,
            position: info["pos"] as? Double ?? 0,
            isPlaying: info["playing"] as? Bool ?? false,
            sourceBundleID: bundleID,
            fetchedAt: Date(),
            rate: info["rate"] as? Double ?? 1,
            canSeek: hasElement,
            canChangeRate: hasElement
        )
        let artworkURL = (info["art"] as? String).flatMap(URL.init(string:))
        return Hit(track: track, artworkURL: artworkURL, location: location)
    }

    static let diaBundleID = "company.thebrowser.dia"
    static let diaJavaScriptFlag = "--enable-applescript-javascript"

    static func displayName(of bundleID: String) -> String {
        InstalledApps.url(for: bundleID).map(InstalledApps.name(at:)) ?? bundleID
    }

    /// Where the user turns on JavaScript from Apple Events in each browser.
    static func enableHint(for bundleID: String) -> String {
        switch bundleID {
        case "com.apple.Safari":
            return String(localized: "In Safari › Settings › Advanced, turn on “Show features for web developers”, then turn on “Allow JavaScript from Apple Events” in the Developer tab")
        case diaBundleID:
            return String(localized: "Dia has no menu for this; it must be relaunched with its JavaScript option")
        default:
            return String(localized: "In \(displayName(of: bundleID)), turn on View › Developer › Allow JavaScript from Apple Events")
        }
    }

    /// Dia only allows AppleScript JavaScript when launched with a flag, so quit
    /// it and open it again with that flag. Dia restores its tabs on launch.
    @MainActor
    static func relaunchDiaWithJavaScript() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: diaBundleID).first,
              let url = app.bundleURL else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Relaunch Dia?")
        alert.informativeText = String(localized: "Dia will quit and reopen with JavaScript from AppleScript allowed. Downloads, uploads or unsent forms in Dia may be lost. While it runs this way, any app you have allowed to control Dia can run JavaScript in its tabs.")
        alert.addButton(withTitle: String(localized: "Relaunch"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        app.terminate()
        func reopen(attempt: Int) {
            if !app.isTerminated && attempt < 50 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { reopen(attempt: attempt + 1) }
                return
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = [diaJavaScriptFlag]
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
        reopen(attempt: 0)
    }

    func send(_ command: NowPlayingCommand, at location: Location) {
        _ = Self.run(guardedScript(Self.commandJS(command), at: location))
    }
}
