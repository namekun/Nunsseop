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
    case home, shelf, timer, clipboard, notes, tools, system, apps, search, emoji, ai, notices, agents, mirror

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
        case .agents: return "list.bullet.rectangle"
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
        case .agents: return String(localized: "Agents")
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
    let approvals = PermissionBoard()
    let onboarding = OnboardingTour()
    let muxy: MuxyActivityWatcher
    let notices = NoticeLog()
    let cmux = CmuxWatcher()
    let herdr = HerdrSessions()
    let agents = AgentBoard()
    let agentList: AgentsTabModel
    let agentHooks: ToolHooks
    /// gjc has no hook to send events, so its state files are polled.
    let gjcWatcher: GjcWatcher
    /// Paseo's agents for the count and the tab, and its permissions and finished agents from its local daemon.
    let paseoWatcher: PaseoWatcher
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
    let recap = RecapCard()
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
    nonisolated static let browRevealDwell: TimeInterval = 0.5
    /// The eyebrow had faded out when the pointer arrived.
    var browRevealing = false

    /// How long the pointer must rest on the collapsed shape before it opens: a faded eyebrow also waits out its dwell.
    nonisolated static func hoverOpenDelay(base: TimeInterval, browRevealing: Bool) -> TimeInterval {
        base + (browRevealing ? browRevealDwell + 0.15 : 0)
    }
    /// The eyebrow has faded out after sitting unused.
    @Published private(set) var browHidden = false
    private var browHideWork: DispatchWorkItem?

    /// Whether the eyebrow is faded out right now: hidden, and no HUD, live activity or sneak peek showing. Idle ears do not keep it up.
    var browFaded: Bool {
        browHidden && !isExpanded && hud.event == nil && approvals.current == nil && !showsLiveActivity && !showsSneakPeek
    }
    /// The eyebrow's mood: a moment's (a finished turn, a limit) while it lasts, otherwise the agents'.
    @Published private(set) var browMood: BrowMood = .rest
    /// Counts the cheers for finished turns; each one hops the eyebrow.
    @Published private(set) var browHops = 0
    private var agentsMood: BrowMood = .rest
    private var momentMood: BrowMood?
    private var momentWork: DispatchWorkItem?
    private var finishWatch = FinishWatch()
    private var cancellables: Set<AnyCancellable> = []
    private var limitAlerts = LimitAlerts()
    private var sneakPeekWork: DispatchWorkItem?
    private var peekFilter = SneakPeekFilter(launchedAt: .now)
    private var callPeekWork: DispatchWorkItem?
    private var clockChangeWork: DispatchWorkItem?
    private var clockChangeDue: Date?

    static let sneakPeekHeight: CGFloat = 24
    /// Room for a command and three buttons on a display without a camera, where the shape has no ears to widen it.
    static let approvalWidth: CGFloat = 380

    init(geometry: NotchGeometry, settings: AppSettings) {
        self.geometry = geometry
        self.settings = settings
        self.hud = HUDCenter(settings: settings)
        let isOn = { settings.idleLeft == .agents || settings.idleRight == .agents || settings.agentsTab }
        self.agentList = AgentsTabModel(board: agents)
        self.agentHooks = ToolHooks(board: agents, isOn: isOn, watchesHerdr: { settings.watchesHerdr })
        self.gjcWatcher = GjcWatcher(board: agents, isOn: isOn)
        self.muxy = MuxyActivityWatcher(board: agents)
        muxy.wantsBoard = isOn
        self.paseoWatcher = PaseoWatcher(board: agents, permissions: approvals, isOn: isOn, wantsApprovals: { settings.permissionPrompts },
                                         wantsNotices: { settings.paseoNotifications })
        // Looks only while the count or the tab is showing (every poll asks `isOn`).
        gjcWatcher.start()
        // The agents likewise; the connection to Paseo's daemon runs while cards or notices are wanted, and only if Paseo has been used.
        paseoWatcher.start()
        // Looks only while Muxy runs and a notice or the count wants it (every poll asks).
        muxy.start()
        // The bridge extension the user loads in Muxy is kept current beside Nunsseop's other files.
        if Muxy.isInstalled { DispatchQueue.global(qos: .utility).async { MuxyBridge.installBundled() } }
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
        nowPlaying.$track.map { track in track.map { $0.artist.isEmpty ? $0.title : $0.title + "  " + $0.artist } ?? "" }
            .removeDuplicates()
            .combineLatest(lyrics.$lines.map { $0.map(\.text) }.removeDuplicates(), settings.$lyricsEnabled)
            .map { title, lyricLines, lyricsOn in Self.peekLineWidth(lines: [title] + (lyricsOn ? lyricLines : [])) }
            .removeDuplicates()
            .sink { [weak self] in self?.songPeekWidth = $0 }
            .store(in: &cancellables)
        lyrics.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        recorder.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // The right ear is as wide as a download's percent, which gains a digit at 10 and at 100, even when another live
        // activity already shows.
        downloads.$status.map { $0.map { $0.percent.map { String($0).count } ?? 0 } }.removeDuplicates()
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // A clock counting up needs a longer format at the hour; nothing else tells the notch when that is.
        objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.scheduleClockChange() }
            .store(in: &cancellables)
        // The timer above doesn't count the time the Mac sleeps, and a clock set by hand jumps; either can pass an
        // hour mark unseen, so the due time is worked out again and the notch measured again.
        for (center, name) in LiveEars.clockJumpNotifications {
            center.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.resyncClockChange() }
                .store(in: &cancellables)
        }
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
        // Agents working or waiting, for the closed notch and the Agents tab; each herdr session is a source of its own.
        herdr.onStates = { [weak self] socket, panes in
            self?.agents.replace(source: "herdr:\(socket)", with: Herdr.boardAgents(panes, socket: socket))
        }
        // Claude Code and Codex sessions anywhere, through their hooks; kept only while the count or the tab is shown.
        notifyServer.onAgent = { [agentHooks] in agentHooks.receive($0) }
        // Claude Code's permission prompts wait here until answered, or until their hook is gone.
        PermissionLink.connect(board: approvals, gate: notifyServer.permissions, isOn: settings.$permissionPrompts.eraseToAnyPublisher(),
                               enabled: { AppSettings.load("permissionPrompts", default: true) },
                               other: { [paseoWatcher] in paseoWatcher.approvals.answer($0, $1) })
            .forEach { $0.store(in: &cancellables) }
        approvals.$prompts
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        onboarding.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        recap.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        $isExpanded.removeDuplicates()
            .sink { [weak self] expanded in
                guard let self else { return }
                if expanded {
                    recap.notchOpened(enabled: settings.weeklyRecap) { [weak self] in self?.canShowRecap == true }
                } else {
                    recap.close()
                }
            }
            .store(in: &cancellables)
        $tab.removeDuplicates().dropFirst()
            .sink { [weak self] _ in self?.recap.close() }
            .store(in: &cancellables)
        approvals.$drafts
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        settings.$idleLeft.combineLatest(settings.$idleRight, settings.$agentsTab)
            .map { $0 == .agents || $1 == .agents || $2 }
            .removeDuplicates()
            .filter { !$0 }
            .sink { [weak self] _ in
                self?.agentHooks.reset()
                self?.gjcWatcher.reset()
                self?.paseoWatcher.reset()
            }
            .store(in: &cancellables)
        agents.$counts
            .removeDuplicates()
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        agents.$revision
            .sink { [weak self] _ in self?.followAgents() }
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
        // which resizes the notch, reaches the whole view; IdleEars watches the values itself. A new day can
        // widen the date, which IdleEars redraws by itself but the shape's width has to follow.
        hud.$power.map { _ in () }
            .merge(with: weather.$current.map { _ in () }, Self.dayChanges,
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
        aiUsage.$providers
            .sink { [weak self] in self?.announceLimits($0) }
            .store(in: &cancellables)
        // Off and on again starts from what is so by then: nothing passed while it was off is announced late.
        settings.$limitAlerts
            .removeDuplicates()
            .sink { [weak self] _ in self?.limitAlerts = LimitAlerts() }
            .store(in: &cancellables)
        settings.$eventAlerts.combineLatest(settings.$calendarEnabled)
            .map { $0 && $1 }
            .sink { [weak self] in self?.calendar.alertsEnabled = $0 }
            .store(in: &cancellables)
        settings.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        AlarmRuntime.shared.notices = notices
    }

    private func announceLimits(_ providers: [AIUsageModel.Provider]) {
        guard settings.limitAlerts else { return }
        let alerts = limitAlerts.step(providers, now: .now)
        if let first = alerts.first {
            showMoment(LimitAlerts.mood(first))
            _ = hud.showLasting(duration: CalendarModel.alertSpacing) {
                .notice(symbol: LimitAlerts.symbol(first), title: LimitAlerts.title(first), detail: LimitAlerts.detail(first))
            }
        }
        for alert in alerts {
            notices.add(symbol: LimitAlerts.symbol(alert), title: LimitAlerts.title(alert), detail: LimitAlerts.detail(alert))
        }
    }

    /// Keeps the eyebrow's face with the agents, and cheers for the turns that just finished.
    private func followAgents() {
        let entries = agents.entries()
        agentsMood = BrowMood.steady(entries)
        let finished = finishWatch.step(entries)
        if settings.cheerFinished, let done = finished.first(where: { !Self.isInFront(app: $0.agent.app) }) {
            showMoment(.happy)
            let row = agentList.rows.first { $0.id == done.key }
            let place = (row?.name ?? row?.path.map { URL(fileURLWithPath: $0).lastPathComponent })
            hud.show(.notice(symbol: BrowMood.happy.symbol, title: Self.finishedTitle(AgentRow.toolName(done.agent.tool)), detail: place),
                     duration: BrowMood.happy.lasts ?? 2.6, action: { [agentList] in if let row { agentList.focus(row) } })
        }
        updateBrowMood()
    }

    nonisolated static func finishedTitle(_ tool: String) -> String { String(localized: "\(tool) is done") }

    /// Whether the agent's terminal is the app in front, where its end was seen already.
    private static func isInFront(app: String?) -> Bool {
        app != nil && NSWorkspace.shared.frontmostApplication?.bundleIdentifier == app
    }

    /// Shows a mood for its moment, then goes back to the agents'.
    private func showMoment(_ mood: BrowMood) {
        momentWork?.cancel()
        momentMood = mood
        if mood == .happy { browHops &+= 1 }
        updateBrowMood()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.momentMood = nil
                self?.updateBrowMood()
            }
        }
        momentWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (mood.lasts ?? 0), execute: work)
    }

    private func updateBrowMood() {
        let mood = momentMood ?? agentsMood
        if mood != browMood { browMood = mood }
    }

    /// "in 5 minutes", and "in 5 minutes · Click to join" when the event has a meeting link.
    static func upcomingDetail(_ item: CalendarItem) -> String {
        let when = item.start.formatted(.relative(presentation: .named))
        return item.joinURL == nil ? when : "\(when) · \(String(localized: "Click to join"))"
    }

    var expandedSize: CGSize {
        var width = settings.expandedWidth
        if settings.widenForTabs { width = Self.widened(width, fitting: widthFittingTabs, limit: geometry.maxExpandedWidth) }
        // A permission prompt shows its command in full, so it takes all the height the panel has.
        var height = approvals.current == nil ? settings.expandedHeight : max(settings.expandedHeight, AppSettings.expandedHeightRange.upperBound)
        if recap.isShowing {
            width = max(width, RecapView.minimumSize.width)
            height = max(height, RecapView.minimumSize.height)
        }
        // The tour is laid out for this much room.
        if onboarding.isActive {
            let frame = OnboardingTour.minimumFrame(notchHeight: geometry.collapsedSize.height)
            width = max(width, frame.width)
            height = max(height, frame.height)
        }
        return CGSize(width: width, height: height)
    }

    /// The saved width, or the width that shows every tab when that is more, but never past the panel.
    nonisolated static func widened(_ width: CGFloat, fitting: CGFloat, limit: CGFloat) -> CGFloat {
        max(width, min(fitting, limit))
    }

    /// A tab button is 26 wide with 2 between buttons.
    nonisolated static let tabSlot: CGFloat = 28
    nonisolated static let tabGap: CGFloat = 2
    /// Horizontal inset of the expanded content from the shape's edge.
    nonisolated static let headerInset: CGFloat = 18 + 14
    /// The longest a tab's title gets beside its icon; a longer one is cut short.
    nonisolated static let tabTitleCap: CGFloat = 90

    /// Settings and Quit at the right end of the header, with the gaps the row puts around them.
    nonisolated static let headerStatusWidth: CGFloat = 2 * (26 + 6)

    /// The width of a row of `count` tab buttons.
    nonisolated static func stripWidth(_ count: Int) -> CGFloat {
        count > 0 ? CGFloat(count) * tabSlot - tabGap : 0
    }

    /// What the current tab's capsule takes beyond a bare icon button: its title, at most `tabTitleCap`, the icon's extra width
    /// the capsule's padding and room for a badge. The widest title among `tabs`, so the row keeps its size whichever tab is current.
    nonisolated static func tabLabelWidth(_ tabs: [NotchTab]) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let widest = tabs.map { ceil(($0.title as NSString).size(withAttributes: [.font: font]).width) }.max() ?? 0
        return min(widest, tabTitleCap) + 22
    }

    /// On notched displays the tabs sit on both sides of the camera: the first `left` on the left, the rest on the right
    /// ahead of the status icons. Picks the split that keeps the wider side narrowest; `side` is that side's width.
    /// A tab strip's frame is 2 points wider than its buttons, and a side that holds tabs has room for the current tab's `label`.
    nonisolated static func tabSplit(count: Int, status: CGFloat, label: CGFloat = 0) -> (left: Int, side: CGFloat) {
        var best = (left: count, side: CGFloat.infinity)
        // From the left so a tie keeps more tabs on the left.
        for left in stride(from: count, through: 0, by: -1) {
            let right = count - left
            let side = max(left > 0 ? stripWidth(left) + 2 + label : 0, right > 0 ? stripWidth(right) + 2 + label + status : status)
            if side < best.side { best = (left, side) }
        }
        return best
    }

    /// The width that shows every tab without scrolling: split around the camera on notched displays, otherwise in one row.
    private var widthFittingTabs: CGFloat {
        let tabs = settings.visibleTabs
        return Self.fittingWidth(tabCount: tabs.count, status: Self.headerStatusWidth, label: Self.tabLabelWidth(tabs),
                                 hasNotch: geometry.hasNotch, notchWidth: geometry.collapsedSize.width)
    }

    nonisolated static func fittingWidth(tabCount count: Int, status: CGFloat, label: CGFloat = 0, hasNotch: Bool, notchWidth: CGFloat) -> CGFloat {
        let content: CGFloat
        if hasNotch {
            let side = tabSplit(count: count, status: status, label: label).side
            content = 2 * side + notchWidth + 8 + 12
        } else {
            content = stripWidth(count) + label + 12 + status
        }
        return content + 2 * headerInset
    }

    /// The meeting name the sneak peek shows instead of the track while a call starts.
    var sneakPeekCallTitle: String? {
        callPeekPending ? calls.call?.title : nil
    }

    var showsSneakPeek: Bool {
        Self.showsSneakPeek(enabled: settings.sneakPeekEnabled, callTitle: sneakPeekCallTitle,
                            track: nowPlaying.track.map { $0.isPlaying },
                            lyricsLive: settings.lyricsEnabled && settings.lyricsUnderNotch && !lyrics.lines.isEmpty,
                            always: settings.sneakPeekAlways, pending: sneakPeekPending)
    }

    /// `track` is whether the loaded track plays, nil without one. `lyricsLive` says lyrics are on, shown under the
    /// notch and known for this song; they only count while it plays.
    nonisolated static func showsSneakPeek(enabled: Bool, callTitle: String?, track: Bool?, lyricsLive: Bool,
                                           always: Bool, pending: Bool) -> Bool {
        guard enabled else { return false }
        if callTitle != nil { return true }
        guard let playing = track else { return false }
        return always || pending || (lyricsLive && playing)
    }

    /// While music plays, the collapsed notch grows an "ear" on each side
    /// for the artwork and a playback indicator, plus a text line underneath
    /// while the sneak peek shows.
    static let hudEarWidth: CGFloat = 102
    /// Room for a short value such as "73%" or "16°" on each side while idle.
    static let idleEarWidth: CGFloat = 70

    /// On a display without a notch the sneak peek or lyric sits between the artwork and the visualizer, not in a row below.
    var sneakPeekInline: Bool { !geometry.hasNotch && showsSneakPeek }
    /// The line's room when it sits inline: the song's longest lyric, or its title and artist, measured once per song so
    /// the shape doesn't resize with every line. A call that is starting is measured on its own.
    @Published private(set) var songPeekWidth: CGFloat = NotchViewModel.minInlinePeekWidth
    nonisolated static let minInlinePeekWidth: CGFloat = 240

    /// What the inline line may take, at most a third of the screen; anything longer shrinks a little, then truncates.
    var inlinePeekWidth: CGFloat {
        let wanted = sneakPeekCallTitle.map { Self.peekLineWidth(lines: [$0]) } ?? songPeekWidth
        return Self.clampedPeekWidth(wanted, screenWidth: geometry.screenFrame.width)
    }

    nonisolated static func clampedPeekWidth(_ wanted: CGFloat, screenWidth: CGFloat) -> CGFloat {
        min(max(wanted, minInlinePeekWidth), screenWidth / 3)
    }

    /// The widest of these lines as SneakPeekLine draws them: the play symbol and its gap, the text, and the side padding.
    nonisolated static func peekLineWidth(lines: [String]) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let text = lines.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return ceil(8 + 6 + text + 2 * 10)
    }

    /// On a display without a notch every HUD is one line: the symbol beside its text, level bar or percent.
    var hudSingleRow: Bool {
        guard !geometry.hasNotch, approvals.current == nil, let event = hud.event else { return false }
        return HUDContent.line(for: event) != nil || HUDContent.compactValueWidth(for: event) != nil
    }

    var collapsedSize: CGSize {
        Self.collapsedSize(base: geometry.collapsedSize, hasNotch: geometry.hasNotch, screenWidth: geometry.screenFrame.width,
                           event: hud.event, showsLiveActivity: showsLiveActivity, liveSides: liveEarSides,
                           idleGrowth: showsIdleEars ? (idleFittedSides.map { $0.left + $0.right } ?? 2 * Self.idleEarWidth) : nil,
                           showsSneakPeek: showsSneakPeek, inlinePeekWidth: inlinePeekWidth,
                           approvalHeight: approvals.current.map { PermissionCard.bodyHeight(for: $0, hasNotch: geometry.hasNotch) })
    }

    /// The closed shape's size from the display's own (`base`) and what the notch shows. `idleGrowth` is how much the
    /// idle values add, nil when there are none.
    static func collapsedSize(base: CGSize, hasNotch: Bool, screenWidth: CGFloat, event: HUDEvent?,
                              showsLiveActivity: Bool, liveSides: @autoclosure () -> LiveEars.Sides,
                              idleGrowth: @autoclosure () -> CGFloat?, showsSneakPeek: Bool,
                              inlinePeekWidth: @autoclosure () -> CGFloat, approvalHeight: CGFloat? = nil) -> CGSize {
        var size = base
        // A permission prompt covers whatever else the closed notch would show: it has buttons to reach.
        if let approvalHeight {
            size.width = max(size.width + 2 * hudEarWidth, approvalWidth)
            size.height += approvalHeight
            return size
        }
        if !hasNotch, let event, let value = HUDContent.compactValueWidth(for: event) {
            size.width = max(size.width, 2 * 18 + HUDContent.lineSymbolWidth + HUDContent.lineGap + value)
            return size
        }
        if !hasNotch, let event, let line = HUDContent.line(for: event) {
            // Nothing hides in the middle, so a notice or headphone battery is one line.
            // The symbol, the gap after it and the side padding, then the text; long lines truncate at a third of the screen.
            let text = ceil((line as NSString).size(withAttributes: [.font: HUDContent.lineFont]).width)
            let content = HUDContent.lineSymbolWidth + HUDContent.lineGap + text
            size.width = min(max(size.width, 2 * 18 + content), max(size.width, screenWidth / 3))
            return size
        }
        if let event {
            size.width += 2 * hudEarWidth
            switch event {
            case .headphones, .notice: size.height += sneakPeekHeight
            default: break
            }
            return size
        }
        let sneakPeekInline = !hasNotch && showsSneakPeek
        if showsLiveActivity {
            let sides = liveSides()
            size.width += sides.left + sides.right
        } else if !sneakPeekInline, let growth = idleGrowth() {
            size.width += growth
        }
        if sneakPeekInline {
            size.width = max(size.width, (showsLiveActivity ? 2 * max(liveSides().left, liveSides().right) : 0) + inlinePeekWidth() + 2 * 13)
        } else if showsSneakPeek {
            size.width = max(size.width, 300)
            size.height += sneakPeekHeight
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
        // The inline peek is centred on the line, so it can't make room for the menus by growing right only.
        if sneakPeekInline { return false }
        let notch = geometry.collapsedSize.width
        let width = collapsedSize.width
        guard width > notch else { return false }
        #if DEBUG
        if Self.forcesLeftEarHidden { return true }
        #endif
        // Fitted sides may grow the left side by less than half; growing right only takes all of it.
        let ear = fittedSides?.left ?? (width - notch) / 2
        return Self.menusReachLeftEar(menus: appMenus.frames, screen: geometry.screenFrame, notch: notch, width: width, ear: ear)
    }

    /// Menus whose centre is off the screen belong to another display and are ignored.
    nonisolated static func menusReachLeftEar(menus: [CGRect], screen: CGRect, notch: CGFloat, width: CGFloat, ear: CGFloat) -> Bool {
        guard width > notch else { return false }
        let menus = menus.filter { screen.contains(CGPoint(x: $0.midX, y: $0.midY)) }
        let left = screen.midX - notch / 2, right = screen.midX + notch / 2
        let covers = { (from: CGFloat, to: CGFloat) in menus.contains { $0.maxX > from && $0.minX < to } }
        return covers(left - ear, left) && !covers(right, right + width - notch)
    }

    /// Fires when the calendar day changes, on the main queue.
    nonisolated static var dayChanges: AnyPublisher<Void, Never> {
        NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .map { _ in () }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    /// The room the eyebrow's stroke leaves at each end of its frame, which fitted idle values keep from the wall too.
    nonisolated static let idleFittedMargin: CGFloat = 10

    /// On a display without a notch, the idle values size the shape to fit them instead of taking a fixed ear each.
    var idleFits: Bool {
        !geometry.hasNotch && hud.event == nil && approvals.current == nil && !showsLiveActivity && !showsSneakPeek && showsIdleEars
    }

    private var idleFittedSides: (left: CGFloat, right: CGFloat)? {
        guard idleFits else { return nil }
        return Self.idleFittedSides(left: idleValue(settings.idleLeft), right: idleValue(settings.idleRight))
    }

    /// The widths the two sides are fitted to: the live activity's while it shows, otherwise the idle values'.
    private var fittedSides: (left: CGFloat, right: CGFloat)? {
        Self.fittedSides(prompt: approvals.current != nil, liveShows: showsLiveActivity && hud.event == nil,
                         live: liveEarSides, idle: idleFittedSides)
    }

    /// The widths the two sides are fitted to. A permission prompt is a symmetric card that covers the sides, so it
    /// takes none: the live activity under it must not move the shape sideways.
    nonisolated static func fittedSides(prompt: Bool, liveShows: Bool, live: @autoclosure () -> LiveEars.Sides,
                                        idle: @autoclosure () -> (left: CGFloat, right: CGFloat)?) -> (left: CGFloat, right: CGFloat)? {
        if prompt { return nil }
        if liveShows {
            let sides = live()
            return (sides.left, sides.right)
        }
        return idle()
    }

    /// How far the top row's content starts past the shape's left wall: past the camera when the shape moved right.
    nonisolated static func earLead(shift: CGFloat, notch: CGFloat) -> CGFloat {
        shift > 0 ? notch - 6 : 0
    }

    /// How far fitted idle values grow the shape on each side: each by its own value, nothing where there is none.
    /// The shape then moves sideways so the eyebrow stays over the camera (see `collapsedShift`).
    nonisolated static func idleFittedSides(left: IdleValue?, right: IdleValue?) -> (left: CGFloat, right: CGFloat)? {
        guard left != nil || right != nil else { return nil }
        return (left.map(idleEarWidth(for:)) ?? 0, right.map(idleEarWidth(for:)) ?? 0)
    }

    /// How far one fitted value needs the shape to grow: the value as IdleEars draws it and 8 between it and the
    /// eyebrow's stroke. Its margin from the wall is the one the stroke leaves empty at the end facing it, so the two
    /// cancel out.
    nonisolated static func idleEarWidth(for value: IdleValue) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let text = (value.text as NSString).size(withAttributes: [.font: font]).width
        let symbol = value.brow.map { _ in IdleValue.browWidth + 3 } ?? value.symbol
            .flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 11, weight: .semibold)) }
            .map { $0.size.width + 3 } ?? 0
        return ceil(symbol + text) + 8
    }

    /// How far right the collapsed shape moves: so its left edge stays at the camera's when the left ear is hidden, or
    /// so the camera area stays over the camera when fitted sides grow the two by different amounts.
    var collapsedShift: CGFloat {
        Self.collapsedShift(fitted: fittedSides, hidesLeftEar: hidesLeftEar,
                            width: collapsedSize.width, notch: geometry.collapsedSize.width)
    }

    nonisolated static func collapsedShift(fitted: (left: CGFloat, right: CGFloat)?, hidesLeftEar: Bool,
                                           width: CGFloat, notch: CGFloat) -> CGFloat {
        // Only two sides make room for the menus; a single side keeps the eyebrow over the camera regardless.
        if let fitted, !(fitted.left > 0 && fitted.right > 0 && hidesLeftEar) { return (fitted.right - fitted.left) / 2 }
        return hidesLeftEar ? (width - notch) / 2 : 0
    }

    /// How far the eyebrow's frame sits from the collapsed shape's left wall, which keeps it over the camera.
    nonisolated static func browLead(width: CGFloat, notch: CGFloat, shift: CGFloat) -> CGFloat {
        max(0, (width - notch) / 2 - shift)
    }

    /// Where fitted idle values start past the shape's left wall, besides their margin: just past the eyebrow when it
    /// sits at that wall with room after it (the left ear hidden, or a right side only), otherwise at the wall.
    nonisolated static func idleLead(browLead: CGFloat, shift: CGFloat, notch: CGFloat) -> CGFloat {
        browLead < 0.5 && shift > 0 ? notch - idleFittedMargin + 8 - idleFittedMargin : 0
    }

    /// The collapsed shape on screen.
    var collapsedRect: NSRect {
        Self.collapsedRect(geometry: geometry, size: collapsedSize, shift: collapsedShift)
    }

    static func collapsedRect(geometry: NotchGeometry, size: CGSize, shift: CGFloat) -> NSRect {
        var rect = geometry.shapeRect(size: size).offsetBy(dx: shift, dy: 0)
        // The gap above a floating eyebrow still counts, so flicking the pointer to the screen edge finds it.
        rect.size.height += geometry.topInset
        // The bare eyebrow is small, so the pointer may be a little off to the side.
        if !geometry.hasNotch && size.width == geometry.collapsedSize.width { rect = rect.insetBy(dx: -8, dy: 0) }
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
                let idle = !self.isExpanded && !self.pointerOverCollapsed && self.hud.event == nil && self.approvals.current == nil
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

    /// Where each clock counting up began, so that it has read the same for as long as the clock has.
    private var clockStarts: [Date] {
        var starts: [Date] = []
        if timer.mode == .stopwatch, let anchor = timer.anchor { starts.append(anchor.addingTimeInterval(-(timer.pausedValue ?? 0))) }
        if let started = recorder.startedAt { starts.append(started) }
        if let call = calls.call { starts.append(call.startedAt) }
        return starts
    }

    /// Has the notch measure itself again when the next clock outgrows its format. The widths are fitted to the clock's
    /// format, not its value, so this happens at most twice in a run (an hour in, and ten).
    private func scheduleClockChange() {
        let due = LiveEars.nextClockChange(after: .now, startingAt: clockStarts)
        guard due != clockChangeDue else { return }
        clockChangeWork?.cancel()
        clockChangeWork = nil
        clockChangeDue = due
        guard let due else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.clockChangeWork = nil
                self.clockChangeDue = nil
                self.objectWillChange.send()
            }
        }
        clockChangeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + LiveEars.clockChangeDelay(until: due, now: .now), execute: work)
    }

    /// After a sleep or a jump of the clock: drops the pending change, which was timed on a clock that stopped, and
    /// measures the notch again (a mark passed meanwhile is then seen at once) before timing the next one.
    private func resyncClockChange() {
        clockChangeWork?.cancel()
        clockChangeWork = nil
        clockChangeDue = nil
        objectWillChange.send()
        scheduleClockChange()
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

    /// The two sides' widths while a live activity shows, each fitted to what it holds; nothing without one.
    var liveEarSides: LiveEars.Sides {
        guard showsLiveActivity else { return .zero }
        let height = geometry.collapsedSize.height
        let content = CollapsedActivity.content(
            nowPlaying: nowPlaying, timer: timer, recorder: recorder, downloads: downloads,
            privacy: settings.privacyIndicator ? privacy : nil, call: calls.call, callMuted: callControls.state?.mic == .off,
            showsMusic: settings.collapsedMusic, showsTimer: settings.collapsedTimer, showsDownloads: settings.collapsedDownloads)
        // The line under the notch (or between the sides, without one) is centred, so it wants equal sides.
        return LiveEars.sides(for: content, art: LiveEars.art(height: height),
                              base: Self.earWidth(height: height, compact: settings.compactLiveActivity), at: .now,
                              symmetric: showsSneakPeek)
    }

    /// What decides how the closed shape's ears move: the shape's size, what each side holds, and whether a peek shows.
    struct EarsFrame: Equatable {
        var size: CGSize
        var sides: LiveEars.Sides
        var peek: Bool

        /// What the ears animate on. The size isn't part of it; it only says which way they move.
        struct Key: Equatable {
            var sides: LiveEars.Sides
            var peek: Bool
        }
        var key: Key { Key(sides: sides, peek: peek) }
    }

    /// Whether the ears move as growing (a spring with a little overshoot) rather than shrinking, going from one frame
    /// to the next. Decided by the direction the shape's size takes, so a peek ending (the sides stop being equal and
    /// the line below goes) is one shrink however many of the values change together. When the size stays put, a peek
    /// showing or hiding decides, and otherwise the activity's sides do.
    nonisolated static func earsGrow(from old: EarsFrame, to new: EarsFrame) -> Bool {
        let grew = new.size.width > old.size.width || new.size.height > old.size.height
        let shrank = new.size.width < old.size.width || new.size.height < old.size.height
        if grew || shrank { return grew }
        if new.peek != old.peek { return new.peek }
        return new.sides != .zero
    }

    /// The ear artwork and the visualizer share: the panel's height plus 6, or 70% of it when compact.
    nonisolated static func earWidth(height: CGFloat, compact: Bool) -> CGFloat {
        compact ? height * 0.7 : height + 6
    }

    var currentSize: CGSize {
        isExpanded ? expandedSize : collapsedSize
    }

    /// Home for a tab the settings no longer show.
    nonisolated static func visibleTab(_ tab: NotchTab, isVisible: (NotchTab) -> Bool) -> NotchTab {
        isVisible(tab) ? tab : .home
    }

    private func leaveHiddenTab() {
        let next = Self.visibleTab(tab, isVisible: settings.isVisible)
        if next != tab { tab = next }
    }

    /// The tab the notch shows after closing: never Mirror, which would start the camera when it reopens, and never
    /// one that is hidden.
    nonisolated static func tabAfterCollapse(_ tab: NotchTab, isVisible: (NotchTab) -> Bool) -> NotchTab {
        visibleTab(tab == .mirror ? .home : tab, isVisible: isVisible)
    }

    /// The recap waits for the tour and for a permission prompt, which have the notch first.
    private var canShowRecap: Bool {
        isExpanded && !onboarding.isActive && !onboarding.isPending && approvals.current == nil
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
        // Search opened by its shortcut may be a tab the header doesn't show.
        let next = Self.tabAfterCollapse(tab, isVisible: settings.isVisible)
        if next != tab { tab = next }
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
