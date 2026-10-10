import AppKit
import CoreAudio
import UniformTypeIdentifiers

/// Notices calls: an app known for calls, or a browser with a meeting tab open, is
/// taking microphone input. Reads CoreAudio's process objects, which exist from
/// macOS 14.2; on older systems it stays inactive.
@MainActor
final class CallMonitor: ObservableObject {
    struct Call: Equatable {
        let appName: String
        /// The app, or the browser for a call in a tab.
        let bundleID: String
        let icon: NSImage
        let startedAt: Date
        /// The meeting's name, for Google Meet in a browser.
        let title: String?
    }

    @Published private(set) var call: Call?

    struct AudioProcess {
        let pid: pid_t
        let bundleID: String
        let isRunningInput: Bool
        let isRunningOutput: Bool
        /// The CoreAudio process object, which a process tap is made from.
        var objectID: AudioObjectID = 0
    }

    /// Keeps a call alive through short gaps in input, such as Zoom briefly releasing the mic.
    struct Tracker {
        static let grace: TimeInterval = 5
        static let confirmation: TimeInterval = 10
        private(set) var key: String?
        private(set) var startedAt: Date?
        private var lastSeen: Date?

        /// `keys` are the calls with input right now, in order of preference; `alive` are
        /// the call apps playing or recording audio.
        mutating func update(active keys: [String], alive: Set<String> = [], at now: Date) {
            if let key, let startedAt, let lastSeen {
                // After 10 s a call stays while its app still plays audio: muted calls may release the mic but not the speaker.
                if keys.contains(key) || (now.timeIntervalSince(startedAt) >= Self.confirmation && alive.contains(key)) {
                    self.lastSeen = now
                    return
                }
                if now.timeIntervalSince(lastSeen) < Self.grace { return }
                self.key = nil
                self.startedAt = nil
                self.lastSeen = nil
            }
            if let first = keys.first {
                key = first
                startedAt = now
                lastSeen = now
            }
        }
    }

    private enum TabCheck: Equatable {
        case pending, none
        case found(service: String, title: String?)

        var isFound: Bool { if case .found = self { return true } else { return false } }
    }

    private var timer: Timer?
    private var polling = false
    private var tracker = Tracker()
    /// Meeting tabs found in each browser since its microphone input started.
    private var tabChecks: [String: TabCheck] = [:]
    /// When a browser that could not be asked for its tabs is asked again.
    private var tabRetry: [String: Date] = [:]
    private let queue = DispatchQueue(label: "nunsseop.calls")

    func start() {
        guard timer == nil else { return }
        #if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "--demo-call"), i + 1 < CommandLine.arguments.count {
            let id = CommandLine.arguments[i + 1]
            let app = Self.appInfo(pid: nil, fallback: Self.appBundleID(for: id) ?? id)
            let browser = Self.browser(for: id) != nil
            call = Call(appName: browser ? "Google Meet" : app.name, bundleID: id, icon: app.icon,
                        startedAt: Date().addingTimeInterval(-83), title: browser ? "Weekly sync" : nil)
            return
        }
        #endif
        // Process objects arrived in macOS 14.2; before that there is nothing to watch.
        guard #available(macOS 14.2, *) else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer?.tolerance = 0.2
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        tracker = Tracker()
        tabChecks = [:]
        tabRetry = [:]
        call = nil
    }

    private func poll() {
        guard !polling else { return }
        polling = true
        let inCall = tracker.key != nil
        queue.async { [weak self] in
            // No call can start while no microphone runs, so the per-process scan is skipped then.
            let processes = inCall || PrivacyMonitor.anyMicRunning() ? Self.audioProcesses() : []
            DispatchQueue.main.async {
                guard let self else { return }
                self.polling = false
                // A failed read is retried on the next poll.
                if let processes, self.timer != nil { self.apply(processes) }
            }
        }
    }

    private func apply(_ processes: [AudioProcess]) {
        let now = Date()
        let (apps, browsers, alive) = Self.classify(processes, own: getpid())
        // A browser is asked for its tabs once each time its input starts; a call found stays until it ends.
        tabChecks = tabChecks.filter { browsers.contains($0.key) || ($0.value.isFound && $0.key == tracker.key) }
        tabRetry = tabRetry.filter { browsers.contains($0.key) }
        for id in browsers where tabChecks[id] == nil && tabRetry[id].map({ $0 <= now }) ?? true {
            if let browser = BrowserMedia.all.first(where: { $0.bundleID == id }) { checkTabs(of: browser) }
        }
        let tabCalls = browsers.sorted().filter { tabChecks[$0]?.isFound == true }
        tracker.update(active: apps.keys.sorted() + tabCalls, alive: alive, at: now)

        guard let key = tracker.key, let startedAt = tracker.startedAt else {
            call = nil
            return
        }
        var title: String?
        if case .found(_, let found) = tabChecks[key] { title = found }
        if let call, call.bundleID == key, call.startedAt == startedAt, call.title == title || title == nil { return }
        if case .found(let service, _) = tabChecks[key] {
            let browser = Self.appInfo(pid: nil, fallback: key)
            call = Call(appName: service, bundleID: key, icon: browser.icon, startedAt: startedAt, title: title)
        } else {
            let app = Self.appInfo(pid: apps[key], fallback: key)
            call = Call(appName: app.name, bundleID: key, icon: app.icon, startedAt: startedAt, title: nil)
        }
    }

    /// Call apps with a microphone-using process, browsers with one, and every app or browser still producing audio.
    nonisolated static func classify(_ processes: [AudioProcess], own: pid_t)
        -> (apps: [String: pid_t], browsers: Set<String>, alive: Set<String>) {
        var apps: [String: pid_t] = [:]
        var browsers: Set<String> = []
        var alive: Set<String> = []
        for process in processes where process.pid != own {
            let key: String
            if let app = appBundleID(for: process.bundleID) {
                key = app
                if process.isRunningInput { apps[app] = apps[app] ?? process.pid }
            } else if let browser = browser(for: process.bundleID) {
                key = browser.bundleID
                if process.isRunningInput { browsers.insert(key) }
            } else {
                continue
            }
            if process.isRunningInput || process.isRunningOutput { alive.insert(key) }
        }
        return (apps, browsers, alive)
    }

    private func checkTabs(of browser: BrowserMedia) {
        let id = browser.bundleID
        tabChecks[id] = .pending
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let tabs = browser.tabs()
            DispatchQueue.main.async {
                guard let self, self.tabChecks[id] == .pending else { return }
                guard let tabs else {
                    // Not allowed, or busy with a consent prompt: ask again in a while.
                    self.tabChecks[id] = nil
                    self.tabRetry[id] = Date().addingTimeInterval(10)
                    return
                }
                self.tabChecks[id] = Self.bestCall(in: tabs).map { TabCheck.found(service: $0.service, title: $0.title) } ?? TabCheck.none
                self.poll()
            }
        }
    }

    // MARK: - Detection

    /// Process bundle-ID prefixes, lowercased, and the app each belongs to. Helpers and
    /// system daemons that carry a call's audio map to the app the user knows.
    private nonisolated static let callApps: [(prefix: String, app: String)] = [
        ("us.zoom.", "us.zoom.xos"),
        ("com.microsoft.teams2", "com.microsoft.teams2"),
        ("com.microsoft.teams", "com.microsoft.teams"),
        ("com.microsoft.vcxpc", "com.microsoft.teams2"),
        ("com.tinyspeck.slackmacgap", "com.tinyspeck.slackmacgap"),
        ("com.hnc.discord", "com.hnc.Discord"),
        ("net.whatsapp.whatsapp", "net.whatsapp.WhatsApp"),
        ("desktop.whatsapp", "desktop.WhatsApp"),
        ("com.apple.facetime", "com.apple.FaceTime"),
        ("com.apple.telephonyutilities", "com.apple.FaceTime"),
        ("com.apple.avconferenced", "com.apple.FaceTime"),
        ("com.webex.meetingmanager", "com.webex.meetingmanager"),
        ("cisco-systems.spark", "Cisco-Systems.Spark"),
        ("com.skype.skype", "com.skype.skype"),
    ]

    nonisolated static func appBundleID(for processBundleID: String) -> String? {
        let id = processBundleID.lowercased()
        return callApps.first { id.hasPrefix($0.prefix) }?.app
    }

    /// The Chromium browser a helper process belongs to. Safari's audio runs in shared
    /// WebKit processes that can't be tied to a browser, so Safari is not considered.
    nonisolated static func browser(for processBundleID: String) -> BrowserMedia? {
        let id = processBundleID.lowercased()
        return BrowserMedia.all.first { $0.dialect == .chromium && id.hasPrefix($0.bundleID.lowercased()) }
    }

    /// Most specific first: a meeting link means a call more surely than an open chat app.
    private nonisolated static let services = ["Google Meet", "Zoom", "Microsoft Teams", "Slack", "Discord"]

    /// The service a browser tab is in a call on.
    nonisolated static func service(for tab: BrowserMedia.Tab) -> String? {
        guard let url = URL(string: tab.url), url.scheme == "https", let host = url.host?.lowercased() else { return nil }
        let path = url.path
        func on(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        if host == "meet.google.com", path.range(of: "^/[a-z]{3}-[a-z]{4}-[a-z]{3}", options: .regularExpression) != nil {
            return "Google Meet"
        }
        if on("zoom.us"), path.hasPrefix("/wc/") { return "Zoom" }
        if host == "app.slack.com", path.contains("/huddle") { return "Slack" }
        // These stay open all day, so only the tab in front of its window counts.
        guard tab.isActive else { return nil }
        if host == "teams.microsoft.com" || host == "teams.live.com" || host == "teams.cloud.microsoft" { return "Microsoft Teams" }
        if host == "app.slack.com" { return "Slack" }
        if on("discord.com"), path.hasPrefix("/channels/") { return "Discord" }
        return nil
    }

    nonisolated static func bestCall(in tabs: [BrowserMedia.Tab]) -> (service: String, title: String?)? {
        tabs.compactMap { tab in service(for: tab).map { (service: $0, title: meetingTitle(tab.title, service: $0)) } }
            .min { services.firstIndex(of: $0.service) ?? 0 < services.firstIndex(of: $1.service) ?? 0 }
    }

    /// Meet tabs are titled "Meet - <name>" or "<name> - Google Meet"; other services' titles don't name the call.
    nonisolated static func meetingTitle(_ tabTitle: String, service: String) -> String? {
        guard service == "Google Meet" else { return nil }
        let title = tabTitle
            .replacingOccurrences(of: "^Meet\\s*[-–—]\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s*[-–—]\\s*(Google )?Meet$", with: "", options: .regularExpression)
        // A bare meeting code names nothing.
        guard !title.isEmpty, title != "Meet", title != "Google Meet",
              title.range(of: "^[a-z]{3}-[a-z]{4}-[a-z]{3}$", options: .regularExpression) == nil else { return nil }
        return title
    }

    /// Every process connected to CoreAudio; nil when the list can't be read.
    nonisolated static func audioProcesses() -> [AudioProcess]? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return nil }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return nil }
        // The list can shrink between the two calls.
        ids = Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
        return ids.compactMap { id in
            func property(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
                AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            }
            func flag(_ selector: AudioObjectPropertySelector) -> Bool {
                var address = property(selector)
                var value: UInt32 = 0
                var size = UInt32(MemoryLayout<UInt32>.size)
                return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr && value != 0
            }
            var pidAddress = property(kAudioProcessPropertyPID)
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(id, &pidAddress, 0, nil, &pidSize, &pid) == noErr else { return nil }
            var bundleAddress = property(kAudioProcessPropertyBundleID)
            var bundleID: Unmanaged<CFString>?
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &bundleAddress, 0, nil, &bundleSize, &bundleID) == noErr,
                  let bundleID = bundleID?.takeRetainedValue() as String?, !bundleID.isEmpty else { return nil }
            return AudioProcess(pid: pid, bundleID: bundleID, isRunningInput: flag(kAudioProcessPropertyIsRunningInput),
                                isRunningOutput: flag(kAudioProcessPropertyIsRunningOutput), objectID: id)
        }
    }

    /// Name and icon of the app a process belongs to. Helpers live inside their app,
    /// so the outermost .app is used; daemons fall back to the given app's bundle ID.
    private static func appInfo(pid: pid_t?, fallback bundleID: String) -> (name: String, icon: NSImage) {
        var url: URL?
        if let pid, let path = NSRunningApplication(processIdentifier: pid)?.bundleURL.map({ $0.path + "/" }),
           let range = path.range(of: ".app/") {
            url = URL(fileURLWithPath: String(path[..<range.upperBound].dropLast()))
        }
        if url == nil { url = InstalledApps.url(for: bundleID) }
        guard let url else { return (bundleID, NSWorkspace.shared.icon(for: .application)) }
        return (InstalledApps.name(at: url), InstalledApps.icon(at: url))
    }
}
