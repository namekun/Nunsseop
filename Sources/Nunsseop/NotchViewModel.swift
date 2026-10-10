import AppKit
import Combine

/// Which Claude or Codex limit an idle ear shows as "left".
enum AIWindow: String, CaseIterable, Identifiable {
    case tighter, session, weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tighter: return String(localized: "Whichever is tighter")
        case .session: return String(localized: "5-hour")
        case .weekly: return String(localized: "Weekly")
        }
    }
}

/// What each side of the collapsed notch shows while nothing is playing or running.
enum IdleItem: String, CaseIterable, Identifiable {
    case none, claude, codex, battery, weather, date, agents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return String(localized: "Nothing")
        case .claude: return String(localized: "Claude Code left")
        case .codex: return String(localized: "Codex left")
        case .battery: return String(localized: "Battery")
        case .weather: return String(localized: "Weather")
        case .date: return String(localized: "Date")
        case .agents: return String(localized: "Agents at work")
        }
    }

    var usesAIUsage: Bool { self == .claude || self == .codex }
}

enum NotchTab: String, CaseIterable, Identifiable {
    case home, shelf, timer, clipboard, notes, tools, system, apps, search, emoji, ai, notices, mirror

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .shelf: return "tray.fill"
        case .timer: return "timer"
        case .clipboard: return "doc.on.clipboard"
        case .notes: return "note.text"
        case .tools: return "switch.2"
        case .system: return "cpu"
        case .apps: return "square.grid.3x3.fill"
        case .search: return "magnifyingglass"
        case .emoji: return "face.smiling"
        case .ai: return "sparkles"
        case .notices: return "bell.fill"
        case .mirror: return "camera.fill"
        }
    }

    var title: String {
        switch self {
        case .home: return String(localized: "Home")
        case .shelf: return String(localized: "Shelf")
        case .timer: return String(localized: "Timer")
        case .clipboard: return String(localized: "Clipboard")
        case .notes: return String(localized: "Notes")
        case .tools: return String(localized: "Tools")
        case .system: return String(localized: "System")
        case .apps: return String(localized: "Apps")
        case .search: return String(localized: "Search")
        case .emoji: return String(localized: "Emoji")
        case .ai: return String(localized: "AI usage")
        case .notices: return String(localized: "Notifications")
        case .mirror: return String(localized: "Mirror")
        }
    }
}

@MainActor
final class NotchViewModel: ObservableObject {
    @Published var geometry: NotchGeometry
    @Published private(set) var isExpanded = false
    @Published var tab: NotchTab = .home
    @Published private(set) var showsLiveActivity = false
    @Published private(set) var sneakPeekPending = false
    /// Set briefly when a call with a meeting name starts.
    @Published private(set) var callPeekPending = false

    let settings: AppSettings
    let nowPlaying = NowPlayingController()
    let shelf = ShelfStore()
    let hud: HUDCenter
    let calendar = CalendarModel()
    let mirror = MirrorModel()
    let timer = TimerModel()
    let clipboard = ClipboardHistory()
    let notes = NotesModel()
    let tools = ToolsModel()
    let appVolume = AppVolumeModel()
    let screenshots = ScreenshotWatcher()
    let capsLock = CapsLockWatcher()
    let notifyServer = NotifyServer()
    let muxy = MuxyWatcher()
    let notices = NoticeLog()
    let cmux = CmuxWatcher()
    let herdr = HerdrSessions()
    let agents = AgentBoard()
    let tmux = TmuxWatcher()
    let stats = SystemStats()
    let launcher = AppLauncher()
    let lyrics = LyricsModel()
    let weather = WeatherModel()
    let downloads = DownloadWatcher()
    let peripherals = PeripheralMonitor()
    let privacy = PrivacyMonitor()
    let calls = CallMonitor()
    let callControls = CallControlsModel()
    let appMenus = AppMenuWatcher()
    let emoji = EmojiModel()
    let aiUsage = AIUsageModel()
    lazy var search = QuickSearchModel(clipboard: clipboard, emoji: emoji, tools: tools)
    let recorder = ScreenRecorder()
    /// Set when opened by the hotkey; the notch then stays open until the pointer visits it or Escape is pressed.
    @Published var pinned = false
    /// The pointer is over the collapsed shape; the eyebrow on displays without a notch lifts.
    @Published var pointerOverCollapsed = false {
        didSet { if pointerOverCollapsed != oldValue { resetBrowHide() } }
    }
    /// The eyebrow is raised: at once on hover, but only after a short dwell when it had faded out, as the cue that it opens.
    @Published var browLifted = false
    /// How long the pointer rests on a faded eyebrow before it raises and opens.
    static let browRevealDwell: TimeInterval = 0.5
    /// The eyebrow had faded out when the pointer arrived.
    var browRevealing = false
    /// The eyebrow has faded out after sitting unused.
    @Published private(set) var browHidden = false
    private var browHideWork: DispatchWorkItem?

    /// Whether the eyebrow is faded out right now: hidden, and no HUD, live activity or sneak peek showing. Idle ears do not keep it up.
    var browFaded: Bool {
        browHidden && !isExpanded && hud.event == nil && !showsLiveActivity && !showsSneakPeek
    }
    private var cancellables: Set<AnyCancellable> = []
    private var sneakPeekWork: DispatchWorkItem?
    private var peekFilter = SneakPeekFilter(launchedAt: .now)
    private var callPeekWork: DispatchWorkItem?

    static let sneakPeekHeight: CGFloat = 24

    init(geometry: NotchGeometry, settings: AppSettings) {
        self.geometry = geometry
        self.settings = settings
        self.hud = HUDCenter(settings: settings)
        Publishers.CombineLatest4(nowPlaying.$track.map { $0?.isPlaying == true }, timer.$anchor.map { $0 != nil },
                                  settings.$collapsedMusic, settings.$collapsedTimer)
            .map { music, timer, showMusic, showTimer in (music && showMusic) || (timer && showTimer) }
            .combineLatest(recorder.$startedAt.map { $0 != nil },
                           privacy.$cameraInUse.combineLatest(privacy.$micInUse, settings.$privacyIndicator).map { ($0 || $1) && $2 })
            .map { $0 || $1 || $2 }
            .combineLatest(calls.$call.map { $0 != nil })
            .map { $0 || $1 }
            .combineLatest(downloads.$status.map { $0 != nil }.combineLatest(settings.$collapsedDownloads).map { $0 && $1 })
            .map { $0 || $1 }
            .removeDuplicates()
            .sink { [weak self] in self?.showsLiveActivity = $0 }
            .store(in: &cancellables)
        nowPlaying.$track
            .sink { [weak self] in self?.lyrics.update(for: $0) }
            .store(in: &cancellables)
        lyrics.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        recorder.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // The ears widen for a download's percent even when another live activity already shows.
        downloads.$status.map { $0 != nil }.removeDuplicates()
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        privacy.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        timer.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        calls.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        settings.$noticesTab
            .sink { [weak self] in self?.notices.isEnabled = $0 }
            .store(in: &cancellables)
        // Agents working or waiting, for the closed notch; each herdr session is a source of its own.
        herdr.onStates = { [weak self] socket, panes in
            self?.agents.replace(source: "herdr:\(socket)", with: Herdr.boardAgents(panes))
        }
        agents.$counts
            .removeDuplicates()
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // The tab's badge counts unseen notices.
        notices.$unseen
            .removeDuplicates()
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        calls.$call
            .sink { [weak self] in self?.callControls.follow($0) }
            .store(in: &cancellables)
        callControls.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // A meeting's name shows under the notch when the call starts.
        calls.$call
            .compactMap { call in call.flatMap { call in call.title.map { "\(call.startedAt)|\($0)" } } }
            .removeDuplicates()
            .sink { [weak self] _ in self?.triggerCallPeek() }
            .store(in: &cancellables)
        nowPlaying.$track
            .compactMap { $0.map { "\($0.identity)|\($0.isPlaying)" } }
            .filter { [weak self] in self?.peekFilter.shouldPeek($0, at: .now) ?? false }
            .sink { [weak self] _ in self?.triggerSneakPeek() }
            .store(in: &cancellables)
        hud.$event
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        appMenus.$frames
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // The idle ears show these. AI limits refresh every 20 s, so only a limit becoming known or unknown,
        // which resizes the notch, reaches the whole view; IdleEars watches the values itself.
        hud.$power.map { _ in () }
            .merge(with: weather.$current.map { _ in () },
                   aiUsage.$providers.combineLatest(settings.$idleAIWindow)
                       .map { providers, window in [IdleItem.claude, .codex].map { Self.aiLeft($0, in: providers, window: window) != nil } }
                       .removeDuplicates().map { _ in () })
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.leaveHiddenTab() }
            .store(in: &cancellables)
        settings.$hiddenCalendarIDs
            .sink { [weak self] in self?.calendar.hiddenCalendarIDs = Set($0) }
            .store(in: &cancellables)
        calendar.onUpcoming = { [weak self] item in
            // With a video-call link, clicking the notice joins the meeting; otherwise it opens the notch as before.
            let join = item.joinURL.map { url in { _ = NSWorkspace.shared.open(url) } }
            let shown = self?.hud.showLasting(duration: CalendarModel.alertSpacing, action: join) { [weak self] in
                // When it comes back after another HUD: only if alerts are still on, the event is still there
                // and not well under way.
                guard let self, self.calendar.stillAlerts(item) else { return nil }
                return .notice(symbol: item.joinURL == nil ? "calendar" : "video.fill", title: item.title,
                               detail: Self.upcomingDetail(item))
            }
            // Kept only when it actually showed; coming back after another HUD doesn't add it again.
            if shown == true {
                self?.notices.add(symbol: item.joinURL == nil ? "calendar" : "video.fill", title: item.title,
                                  detail: Self.upcomingDetail(item), action: join)
            }
        }
        settings.$eventAlerts.combineLatest(settings.$calendarEnabled)
            .map { $0 && $1 }
            .sink { [weak self] in self?.calendar.alertsEnabled = $0 }
            .store(in: &cancellables)
        settings.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// "in 5 minutes", and "in 5 minutes · Click to join" when the event has a meeting link.
    static func upcomingDetail(_ item: CalendarItem) -> String {
        let when = item.start.formatted(.relative(presentation: .named))
        return item.joinURL == nil ? when : "\(when) · \(String(localized: "Click to join"))"
    }

    var expandedSize: CGSize {
        var width = settings.expandedWidth
        if settings.widenForTabs { width = max(width, min(widthFittingTabs, geometry.maxExpandedWidth)) }
        return CGSize(width: width, height: settings.expandedHeight)
    }

    nonisolated static let tabSlot: CGFloat = 36
    /// Horizontal inset of the expanded content from the shape's edge.
    static let headerInset: CGFloat = 18 + 14

    /// Battery, weather, Settings and Quit at the right end of the header.
    var headerStatusWidth: CGFloat {
        var width: CGFloat = 2 * (26 + 6)
        if settings.batteryInHeader && hud.power != nil { width += 66 }
        if settings.headerWeather && weather.current != nil { width += 50 }
        return width
    }

    /// The width of a row of `count` tab buttons.
    nonisolated static func stripWidth(_ count: Int) -> CGFloat {
        count > 0 ? CGFloat(count) * tabSlot - 6 : 0
    }

    /// On notched displays the tabs sit on both sides of the camera: the first `left` on the left, the rest on the right
    /// ahead of the status icons. Picks the split that keeps the wider side narrowest; `side` is that side's width.
    /// A tab strip's frame is 2 points wider than its buttons.
    nonisolated static func tabSplit(count: Int, status: CGFloat) -> (left: Int, side: CGFloat) {
        var best = (left: count, side: CGFloat.infinity)
        // From the left so a tie keeps more tabs on the left.
        for left in stride(from: count, through: 0, by: -1) {
            let right = count - left
            let side = max(stripWidth(left) + 2, right > 0 ? stripWidth(right) + 2 + status : status)
            if side < best.side { best = (left, side) }
        }
        return best
    }

    /// The width that shows every tab without scrolling: split around the camera on notched displays, otherwise in one row.
    private var widthFittingTabs: CGFloat {
        let count = settings.visibleTabs.count
        let content: CGFloat
        if geometry.hasNotch {
            let side = Self.tabSplit(count: count, status: headerStatusWidth).side
            content = 2 * side + geometry.collapsedSize.width + 8 + 12
        } else {
            content = Self.stripWidth(count) + 12 + headerStatusWidth
        }
        return content + 2 * Self.headerInset
    }

    /// The meeting name the sneak peek shows instead of the track while a call starts.
    var sneakPeekCallTitle: String? {
        callPeekPending ? calls.call?.title : nil
    }

    var showsSneakPeek: Bool {
        guard settings.sneakPeekEnabled else { return false }
        if sneakPeekCallTitle != nil { return true }
        guard let track = nowPlaying.track else { return false }
        let lyricsLive = settings.lyricsEnabled && settings.lyricsUnderNotch && track.isPlaying && !lyrics.lines.isEmpty
        return settings.sneakPeekAlways || sneakPeekPending || lyricsLive
    }

    /// While music plays, the collapsed notch grows an "ear" on each side
    /// for the artwork and a playback indicator, plus a text line underneath
    /// while the sneak peek shows.
    static let hudEarWidth: CGFloat = 102
    /// Room for a short value such as "73%" or "16°" on each side while idle.
    static let idleEarWidth: CGFloat = 70

    /// On a display without a notch nothing hides in the middle, so a notice or headphone battery is one line.
    var hudLine: String? {
        guard !geometry.hasNotch, let event = hud.event else { return nil }
        return HUDContent.line(for: event)
    }

    /// On a display without a notch the sneak peek or lyric sits between the artwork and the visualizer, not in a row below.
    var sneakPeekInline: Bool { !geometry.hasNotch && showsSneakPeek }
    /// The line's room when it sits inline; fixed, so the shape doesn't resize with every lyric.
    static let inlinePeekWidth: CGFloat = 300

    /// On a display without a notch every HUD is one line: the symbol beside its text, level bar or percent.
    var hudSingleRow: Bool {
        guard !geometry.hasNotch, let event = hud.event else { return false }
        return HUDContent.line(for: event) != nil || HUDContent.compactValueWidth(for: event) != nil
    }

    var collapsedSize: CGSize {
        var size = geometry.collapsedSize
        if !geometry.hasNotch, let event = hud.event, let value = HUDContent.compactValueWidth(for: event) {
            size.width = max(size.width, 2 * 18 + HUDContent.lineSymbolWidth + HUDContent.lineGap + value)
            return size
        }
        if let line = hudLine {
            // The symbol, the gap after it and the side padding, then the text; long lines truncate at a third of the screen.
            let text = ceil((line as NSString).size(withAttributes: [.font: HUDContent.lineFont]).width)
            let content = HUDContent.lineSymbolWidth + HUDContent.lineGap + text
            size.width = min(max(size.width, 2 * 18 + content), max(size.width, geometry.screenFrame.width / 3))
            return size
        }
        if let event = hud.event {
            size.width += 2 * Self.hudEarWidth
            switch event {
            case .headphones, .notice: size.height += Self.sneakPeekHeight
            default: break
            }
            return size
        }
        if showsLiveActivity {
            size.width += 2 * earWidth
        } else if showsIdleEars {
            size.width += (idleOneSide == nil ? 2 : 1) * Self.idleEarWidth
        }
        if sneakPeekInline {
            size.width = max(size.width, (showsLiveActivity ? 2 * earWidth : 0) + Self.inlinePeekWidth + 2 * 13)
        } else if showsSneakPeek {
            size.width = max(size.width, 300)
            size.height += Self.sneakPeekHeight
        }
        return size
    }

    #if DEBUG
    /// `--hide-left-ear` acts as if the app's menus always reached the left ear.
    private static let forcesLeftEarHidden = CommandLine.arguments.contains("--hide-left-ear")
    #endif

    /// True when the collapsed notch's left side would cover the frontmost app's menus. It then grows to the right only,
    /// and what the left side showed moves to the right of the camera. Left as is when the menus reach the right side too.
    var hidesLeftEar: Bool {
        let notch = geometry.collapsedSize.width
        let width = collapsedSize.width
        guard width > notch else { return false }
        #if DEBUG
        if Self.forcesLeftEarHidden { return true }
        #endif
        let screen = geometry.screenFrame
        let menus = appMenus.frames.filter { screen.contains(CGPoint(x: $0.midX, y: $0.midY)) }
        let left = screen.midX - notch / 2, right = screen.midX + notch / 2, ear = (width - notch) / 2
        let covers = { (from: CGFloat, to: CGFloat) in menus.contains { $0.maxX > from && $0.minX < to } }
        return covers(left - ear, left) && !covers(right, right + 2 * ear)
    }

    /// On a display without a notch, a single idle side grows the shape on that side only: -1 left, 1 right.
    private var idleOneSide: Int? {
        guard !geometry.hasNotch, hud.event == nil, !showsLiveActivity, !showsSneakPeek, showsIdleEars else { return nil }
        let left = idleValue(settings.idleLeft) != nil, right = idleValue(settings.idleRight) != nil
        return left == right ? nil : (left ? -1 : 1)
    }

    /// How far right the collapsed shape moves so its left edge stays at the camera's.
    var collapsedShift: CGFloat {
        if let side = idleOneSide { return CGFloat(side) * Self.idleEarWidth / 2 }
        return hidesLeftEar ? (collapsedSize.width - geometry.collapsedSize.width) / 2 : 0
    }

    /// The collapsed shape on screen.
    var collapsedRect: NSRect {
        var rect = geometry.shapeRect(size: collapsedSize).offsetBy(dx: collapsedShift, dy: 0)
        // The gap above a floating eyebrow still counts, so flicking the pointer to the screen edge finds it.
        rect.size.height += geometry.topInset
        // The bare eyebrow is small, so the pointer may be a little off to the side.
        if !geometry.hasNotch && collapsedSize.width == geometry.collapsedSize.width { rect = rect.insetBy(dx: -8, dy: 0) }
        return rect
    }

    /// Shows the eyebrow and starts counting down to hiding it again. It only hides while nothing else shows in the collapsed shape.
    func resetBrowHide() {
        browHidden = false
        browHideWork?.cancel()
        browHideWork = nil
        guard settings.autoHideBrow, !geometry.hasNotch else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.browHideWork = nil
                let idle = !self.isExpanded && !self.pointerOverCollapsed && self.hud.event == nil
                    && !self.showsLiveActivity && !self.showsSneakPeek
                if idle { self.browHidden = true } else { self.resetBrowHide() }
            }
        }
        browHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.browHideDelay, execute: work)
    }

    private func triggerSneakPeek() {
        sneakPeekWork?.cancel()
        sneakPeekPending = true
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.sneakPeekPending = false }
        }
        sneakPeekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.sneakPeekDuration, execute: work)
    }

    private func triggerCallPeek() {
        callPeekWork?.cancel()
        callPeekPending = true
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.callPeekPending = false }
        }
        callPeekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.sneakPeekDuration, execute: work)
    }

    var earWidth: CGFloat {
        let height = geometry.collapsedSize.height
        let base = settings.compactLiveActivity ? height * 0.7 : height + 6
        // Room for "1:23:45" during a call, plus a mic-slash while muted, and "12:34" when a timer is running or "100%" for a download.
        if calls.call != nil { return max(base, callControls.state?.mic == .off ? 74 : 60) }
        let needsText = (timer.isRunning && settings.collapsedTimer) || recorder.isRecording
            || (downloads.status != nil && settings.collapsedDownloads)
        return needsText ? max(base, 50) : base
    }

    var currentSize: CGSize {
        isExpanded ? expandedSize : collapsedSize
    }

    private func leaveHiddenTab() {
        if !settings.isVisible(tab) { tab = .home }
    }

    func expand() {
        guard !isExpanded else { return }
        isExpanded = true
        resetBrowHide()
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        resetBrowHide()
        pinned = false
        // The camera must only start from an explicit click on the Mirror tab.
        if tab == .mirror { tab = .home }
        // Search opened by its shortcut may be a tab the header doesn't show.
        leaveHiddenTab()
    }
}

/// Which now-playing changes show the sneak peek. A track already loaded when the app starts, playing or paused,
/// is not news, so the first one seen shortly after launch only becomes the baseline; every later change peeks.
struct SneakPeekFilter {
    /// The first track can take a moment to arrive: the helper starts and the players are asked over AppleScript.
    static let launchWindow: TimeInterval = 5

    let launchedAt: Date
    private var last: String?

    init(launchedAt: Date) {
        self.launchedAt = launchedAt
    }

    /// `key` identifies the track and whether it plays.
    mutating func shouldPeek(_ key: String, at date: Date) -> Bool {
        defer { last = key }
        guard key != last else { return false }
        return last != nil || date.timeIntervalSince(launchedAt) > Self.launchWindow
    }
}
