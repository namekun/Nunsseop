import AppKit
import Combine
import SwiftUI

final class NotchPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = NotchPanel.behavior
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Transient: Mission Control hides it, where a stationary panel would stay on top of the windows it spreads out.
    nonisolated static let behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary, .ignoresCycle]
}

/// The panel never becomes active, so the first click must reach SwiftUI gestures directly.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Tells what a two-finger swipe over the notch does. Each swipe fires at most once, until `reset`.
struct SwipeRecognizer {
    enum Action: Equatable { case open, close, nextTrack, previousTrack }

    static let threshold: CGFloat = 40
    /// How much further one axis must have moved than the other for the swipe to count as along it.
    static let dominance: CGFloat = 1.5

    private var travel = CGVector.zero
    private var fired = false

    /// Only trackpad swipes over the panel; not scrolling in other windows, wheels or momentum.
    static func accepts(overPanel: Bool, precise: Bool, momentum: Bool) -> Bool {
        overPanel && precise && !momentum
    }

    /// The expanded header scrolls its tabs sideways, so swipes there are left to it.
    static func isOverHeader(fromTop: CGFloat, collapsedHeight: CGFloat) -> Bool {
        fromTop < max(collapsedHeight, 24) + 6
    }

    mutating func reset() {
        travel = .zero
        fired = false
    }

    /// Adds a scroll event's deltas and returns the action once the swipe is clear enough. `inverted` is natural
    /// scrolling, which is turned back into the fingers' direction. Skipping tracks needs `tracks`.
    mutating func add(dx: CGFloat, dy: CGFloat, inverted: Bool, opens: Bool, tracks: Bool) -> Action? {
        let sign: CGFloat = inverted ? 1 : -1
        travel.dx += dx * sign
        travel.dy += dy * sign
        guard !fired else { return nil }
        if abs(travel.dy) > Self.threshold && abs(travel.dy) > abs(travel.dx) * Self.dominance, opens {
            fired = true
            return travel.dy > 0 ? .open : .close
        } else if abs(travel.dx) > Self.threshold && abs(travel.dx) > abs(travel.dy) * Self.dominance, tracks {
            fired = true
            return travel.dx < 0 ? .nextTrack : .previousTrack
        }
        return nil
    }
}

/// How an open notch treats the pointer leaving it.
enum OpenNotchHold: Equatable {
    /// A message is being typed: open wherever the pointer goes, and the panel takes every click.
    case composing
    /// The tour runs: open wherever the pointer goes, but a click outside the shape still reaches what is under it.
    case touring
    /// Opened by a shortcut: open until the pointer has visited it, then it follows the pointer again.
    case pinned
    case followsPointer

    static func of(composing: Bool, touring: Bool, pinned: Bool) -> OpenNotchHold {
        if composing { return .composing }
        if touring { return .touring }
        return pinned ? .pinned : .followsPointer
    }
}

@MainActor
final class NotchWindowController {
    private let model: NotchViewModel
    private let panel: NotchPanel
    private var monitors: [Any] = []
    private var collapseWork: DispatchWorkItem?
    private var openWork: DispatchWorkItem?
    private var tourWork: DispatchWorkItem?
    /// Whether the notch was open at the last pointer move.
    private var wasExpanded = false
    /// Set when the notch closed with the pointer still over it (Escape, a swipe up, a click elsewhere);
    /// hovering opens it again only after the pointer has left, so it doesn't spring back open.
    private var hoverOpenBlocked = false
    /// The drag pasteboard's count at the last mouse up; a higher count means the drag running now carries data.
    private var idleDragCount = NSPasteboard(name: .drag).changeCount
    private var swipe = SwipeRecognizer()
    private var swipeIdleWork: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?
    private var wakeObservers: [NSObjectProtocol] = []
    private var settleWork: [DispatchWorkItem] = []
    private var fullScreenObservers: [NSObjectProtocol] = []
    private var fullScreenWork: DispatchWorkItem?
    private var closedAt = Date.distantPast
    private var followWork: DispatchWorkItem?
    private var displayObserver: AnyCancellable?
    private var browHideObserver: AnyCancellable?
    private var liftWork: DispatchWorkItem?
    private var updatesObserver: AnyCancellable?
    private var settingsObservers: [AnyCancellable] = []
    /// Keeps the AI limits fresh while an idle ear shows them.
    private var aiUsageTimer: Timer?
    private var hotKeys: [ShortcutAction: GlobalHotKey] = [:]
    private var resignObserver: NSObjectProtocol?
    private lazy var shakeShelf = ShakeShelf(shelf: model.shelf, hud: model.hud)

    /// A watcher that only feeds the notch: it runs while its setting is on and the panel is on screen.
    private struct Feature {
        let setting: KeyPath<AppSettings, Bool>
        let changes: KeyPath<AppSettings, Published<Bool>.Publisher>
        let start: () -> Void
        /// `hiding` is true when only the panel went away; the setting is still on.
        let stop: (_ hiding: Bool) -> Void
    }

    /// Everything else runs regardless of the panel: now playing, the HUD (it may be taking over the volume and
    /// brightness keys), tools, the screenshot and download watchers (they still fill the shelf), the AI usage
    /// timer, lyrics, weather and update checks.
    private lazy var features: [Feature] = {
        let model = model
        let shakeShelf = shakeShelf
        return [
            Feature(setting: \.clipboardTab, changes: \.$clipboardTab,
                    start: { model.clipboard.start() }, stop: { _ in model.clipboard.stop() }),
            Feature(setting: \.capsLockHUD, changes: \.$capsLockHUD,
                    start: { model.capsLock.start() }, stop: { _ in model.capsLock.stop() }),
            Feature(setting: \.localNotifications, changes: \.$localNotifications,
                    start: {
                        model.notifyServer.start()
                        // Kept current for WezTerm's pasted lines, which call it.
                        TerminalBell.install()
                        // Tools connected with an older version get this version's hook.
                        NotifyIntegration.updateConnected()
                        if model.settings.tmuxBells { model.tmux.start() }
                    },
                    stop: { _ in
                        model.notifyServer.stop()
                        model.tmux.stop()
                    }),
            Feature(setting: \.muxyNotifications, changes: \.$muxyNotifications,
                    start: { model.muxy.noticesEnabled = true }, stop: { _ in model.muxy.noticesEnabled = false }),
            Feature(setting: \.cmuxNotifications, changes: \.$cmuxNotifications,
                    // Started even before they're installed: both look for their app again while running.
                    start: { model.cmux.start() }, stop: { _ in model.cmux.stop() }),
            // Watched for notices or for the agents count in the closed notch.
            Feature(setting: \.watchesHerdr, changes: \.$watchesHerdr,
                    start: { model.herdr.start() }, stop: { _ in model.herdr.stop() }),
            // The hook sends to the notification server, so it's only added while that runs.
            Feature(setting: \.tmuxBells, changes: \.$tmuxBells,
                    start: { if model.settings.localNotifications { model.tmux.start() } }, stop: { _ in model.tmux.stop() }),
            Feature(setting: \.callIsland, changes: \.$callIsland,
                    start: { model.calls.start() }, stop: { _ in model.calls.stop() }),
            // Hiding keeps the last camera/mic state, so showing again during a call already announced stays quiet.
            Feature(setting: \.privacyIndicator, changes: \.$privacyIndicator,
                    start: { model.privacy.start() }, stop: { hiding in model.privacy.stop(clearing: !hiding) }),
            Feature(setting: \.peripheralBatteries, changes: \.$peripheralBatteries,
                    start: { model.peripherals.start() }, stop: { _ in model.peripherals.stop() }),
            Feature(setting: \.shakeToShelf, changes: \.$shakeToShelf,
                    start: { shakeShelf.start() }, stop: { _ in shakeShelf.stop() }),
        ]
    }()

    /// Shows a notice from an agent, terminal or tool, and keeps it in the Notifications tab.
    private func announce(symbol: String, title: String, detail: String?, action: (() -> Void)?) {
        model.hud.show(.notice(symbol: symbol, title: title, detail: detail), duration: 6, action: action)
        model.notices.add(symbol: symbol, title: title, detail: detail, action: action)
    }

    /// What a global shortcut does: opens the notch on a tab with the keyboard, closes it, or goes to a session or the source of a notice.
    private func perform(_ action: ShortcutAction) {
        // The tour has the notch, and shows the shortcut itself.
        guard panel.isVisible, !model.onboarding.isActive else { return }
        switch action.step(expanded: model.isExpanded, tab: model.tab) {
        case .collapse:
            model.collapse()
            panel.ignoresMouseEvents = true
        case .open(let tab, let focusSearch):
            if let tab { model.tab = tab }
            model.expand()
            model.pinned = true
            panel.ignoresMouseEvents = false
            panel.makeKey()
            if focusSearch { model.search.focusToken += 1 }
        case .goToWaitingAgent:
            if !model.agentList.focusLongestWaiting() {
                model.hud.show(.notice(symbol: "checkmark.circle", title: String(localized: "No agent is waiting"), detail: nil), duration: 3)
            }
        case .goToLastNotice:
            if let action = model.notices.latestWithAction?.action {
                action()
            } else {
                model.hud.show(.notice(symbol: "bell.slash", title: String(localized: "No notice to go back to"), detail: nil), duration: 3)
            }
        }
    }

    init() {
        let settings = AppSettings.shared
        let geometry = NotchGeometry.pickScreen(preferredName: settings.displayName,
                                                pointer: settings.followPointerAcrossDisplays ? NSEvent.mouseLocation : nil)
            .map { NotchGeometry(screen: $0) }
            ?? NotchGeometry()
        // Before the view model exists: its notification server writes the token this looks for.
        let freshInstall = OnboardingTour.isFreshInstall()
        model = NotchViewModel(geometry: geometry, settings: .shared)
        model.onboarding.prepare(freshInstall: freshInstall)
        panel = NotchPanel(frame: geometry.panelFrame)

        let hosting = FirstMouseHostingView(rootView: NotchView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting

        #if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot-dir"), i + 1 < CommandLine.arguments.count {
            snapshotter = DebugSnapshotter(directory: URL(fileURLWithPath: CommandLine.arguments[i + 1]),
                                           view: hosting, model: model)
        }
        if CommandLine.arguments.contains("--demo-shake-shelf") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.shakeShelf.demo { label, view in self?.snapshotter?.capture(label: label, of: view) }
            }
        }
        // Debug: --demo-permission shows a prompt for checking its layout; answering it only closes the card.
        if CommandLine.arguments.contains("--demo-permission") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.model.approvals.add(.demo) }
        }
        // Debug: --demo-codex-permission shows Codex's prompt, which has "Answer in terminal" in place of "Always allow".
        if CommandLine.arguments.contains("--demo-codex-permission") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.model.approvals.add(.demoCodex) }
        }
        // Debug: --demo-question shows two questions, the second with several answers; answering only closes the card.
        if CommandLine.arguments.contains("--demo-question") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.model.approvals.add(.demoQuestion) }
        }
        if CommandLine.arguments.contains("--demo-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { SettingsWindowController.shared.show() }
        }
        #endif
        SettingsWindowController.shared.onReplayTour = { [weak self] in self?.beginTour(replay: true) }
    }

    // MARK: Tour

    /// Opens the notch on the tour's first step, whatever it is doing, and has the keyboard for the tour's keys.
    private func beginTour(replay: Bool = false) {
        if replay { model.onboarding.replay() } else { model.onboarding.start() }
        model.expand()
        engageTour()
    }

    /// Pinned, so that a click elsewhere closes the notch (the tour waits where it is), and key, for Return, the arrows and Escape.
    private func engageTour() {
        guard panel.isVisible else { return }
        model.pinned = true
        panel.ignoresMouseEvents = false
        panel.makeKey()
    }

    /// The tour starts a moment after launch, once nothing needs answering first.
    private func scheduleTourStart(after delay: TimeInterval) {
        tourWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.model.onboarding.isPending else { return }
                if OnboardingTour.canBegin(panelVisible: self.panel.isVisible, approvalShowing: self.model.approvals.current != nil,
                                           noticeClickable: self.model.hud.action != nil) {
                    self.beginTour()
                } else {
                    self.scheduleTourStart(after: 1)
                }
            }
        }
        tourWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Return, the arrows and Escape, while the notch shows the tour and is the key window.
    private func handlesTourKey(_ event: NSEvent) -> Bool {
        guard event.window === panel, model.onboarding.shows(expanded: model.isExpanded, approvalShowing: model.approvals.current != nil)
        else { return false }
        return model.onboarding.handle(keyCode: event.keyCode, modifiers: event.modifierFlags, isRepeat: event.isARepeat)
    }

    /// Escape closes the recap, while the notch shows it and is the key window.
    private func handlesRecapKey(_ event: NSEvent) -> Bool {
        guard event.window === panel, model.recap.isShowing, model.approvals.current == nil, event.keyCode == 53,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
        model.recap.close()
        return true
    }

    #if DEBUG
    private var snapshotter: DebugSnapshotter?
    #endif

    func show() {
        panel.setFrame(model.geometry.panelFrame, display: true)
        panel.orderFrontRegardless()
        updateVisibility()
        installMonitors()
        #if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "--demo-tab"), i + 1 < CommandLine.arguments.count,
           let tab = NotchTab(rawValue: CommandLine.arguments[i + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                if let j = CommandLine.arguments.firstIndex(of: "--demo-timer-mode"), j + 1 < CommandLine.arguments.count,
                   let mode = TimerModel.Mode(rawValue: CommandLine.arguments[j + 1]) {
                    self.model.timer.mode = mode
                }
                // `--demo-timer-state running|paused` starts the timer (and pauses it after a few seconds).
                if let j = CommandLine.arguments.firstIndex(of: "--demo-timer-state"), j + 1 < CommandLine.arguments.count {
                    self.model.timer.start()
                    if CommandLine.arguments[j + 1] == "paused" {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.model.timer.pause() }
                    }
                }
                self.model.tab = tab
                self.model.expand()
                self.model.pinned = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self.model.expand()
                    self.snapshotter?.capture(label: "tab")
                }
            }
        }
        // Debug: --demo-onboarding <1-4|ready|nonotch> shows that step pinned.
        let demoSteps = ["1": 0, "2": 1, "3": 2, "4": 3, "ready": 3, "nonotch": 0]
        if let i = CommandLine.arguments.firstIndex(of: "--demo-onboarding"), i + 1 < CommandLine.arguments.count,
           let step = demoSteps[CommandLine.arguments[i + 1]] {
            let name = CommandLine.arguments[i + 1]
            // The demo is what shows, not the real first-run tour.
            model.onboarding.prepare(freshInstall: false, version: "")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                self.model.onboarding.startDemo(step: step, tools: name == "ready" ? [] : [.claudeCode, .codex],
                                                connected: [.claudeCode], withoutNotch: name == "nonotch")
                self.model.expand()
                self.engageTour()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.snapshotter?.capture(label: "onboarding") }
            }
        }
        // Debug: --demo-whats-new <version> shows that release's notes pinned.
        if let i = CommandLine.arguments.firstIndex(of: "--demo-whats-new"), i + 1 < CommandLine.arguments.count {
            let version = CommandLine.arguments[i + 1]
            model.onboarding.prepare(freshInstall: false, version: "")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                self.model.onboarding.startDemo(news: version)
                self.model.expand()
                self.engageTour()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.snapshotter?.capture(label: "whats-new") }
            }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--demo-search"), i + 1 < CommandLine.arguments.count {
            let query = CommandLine.arguments[i + 1]
            model.search.loadApps()
            model.search.query = query
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                self.model.tab = .search
                self.model.expand()
                self.model.search.query = query
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    self.model.tab = .search
                    self.model.expand()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.snapshotter?.capture(label: "search") }
                }
            }
        }
        #endif
        scheduleTourStart(after: 1)
        model.nowPlaying.start()
        model.hud.start()
        model.appMenus.start()
        model.tools.start()
        model.tools.onNotice = { [weak self] symbol, title, detail in
            self?.model.hud.show(.notice(symbol: symbol, title: title, detail: detail), duration: 2.5)
        }
        model.screenshots.onScreenshot = { [weak self] url in
            guard let self else { return }
            self.model.shelf.add([url])
            self.model.hud.show(.notice(symbol: "camera.viewfinder", title: String(localized: "Screenshot added to the shelf"),
                                        detail: url.lastPathComponent), duration: 3)
        }
        model.screenshots.start()
        model.capsLock.onChange = { [weak self] on in
            guard let self, self.model.settings.capsLockHUD else { return }
            self.model.hud.show(.notice(symbol: on ? "capslock.fill" : "capslock",
                                        title: on ? String(localized: "Caps Lock on") : String(localized: "Caps Lock off"),
                                        detail: nil), duration: 1.2)
        }
        model.downloads.onStart = { [weak self] name in
            guard let self, self.model.settings.downloadAlerts else { return }
            self.model.hud.show(.notice(symbol: "arrow.down.circle", title: String(localized: "Downloading"), detail: name), duration: 3)
        }
        model.downloads.onFinish = { [weak self] url in
            guard let self else { return }
            if self.model.settings.downloadsToShelf { self.model.shelf.add([url]) }
            if self.model.settings.downloadAlerts {
                self.model.hud.show(.notice(symbol: "checkmark.circle.fill", title: String(localized: "Download finished"),
                                            detail: url.lastPathComponent), duration: 4)
            }
        }
        model.downloads.start()
        model.peripherals.onLow = { [weak self] device in
            self?.model.hud.show(.notice(symbol: device.symbol, title: String(localized: "Low battery"),
                                         detail: "\(device.name) \(device.percent)%"), duration: 5)
        }
        model.privacy.onChange = { [weak self] camera, mic in
            guard let self, self.model.settings.privacyIndicator else { return }
            let title = camera && mic ? String(localized: "Camera and microphone in use")
                : camera ? String(localized: "Camera in use") : String(localized: "Microphone in use")
            self.model.hud.show(.notice(symbol: camera ? "video.fill" : "mic.fill", title: title, detail: nil), duration: 3)
        }
        model.recorder.onFinished = { [weak self] url in
            guard let self, let url else { return }
            self.model.shelf.add([url])
            self.model.hud.show(.notice(symbol: "record.circle", title: String(localized: "Recording saved"),
                                        detail: url.lastPathComponent), duration: 4)
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Clicking away from the message field closes it; the notch then follows the pointer again.
                self.model.agentList.cancelCompose()
                guard self.model.pinned else { return }
                self.model.collapse()
                self.panel.ignoresMouseEvents = true
            }
        }
        // The tour waits where it is when the notch closes, and takes the notch again whenever it opens.
        settingsObservers.append(model.$isExpanded.removeDuplicates().sink { [weak self] expanded in
            guard let self, expanded, self.model.onboarding.isActive else { return }
            self.engageTour()
        })
        // Finishing or skipping puts the notch back to its tabs.
        settingsObservers.append(model.onboarding.$isActive.removeDuplicates().sink { [weak self] active in
            guard let self, !active, self.model.isExpanded else { return }
            self.model.collapse()
            self.panel.ignoresMouseEvents = true
        })
        // The recap takes the keyboard for Escape.
        settingsObservers.append(model.recap.$isShowing.removeDuplicates().sink { [weak self] showing in
            guard showing, self?.panel.isVisible == true else { return }
            self?.panel.makeKey()
        })
        // The field needs the keyboard, which a panel that never activates gets by becoming key.
        settingsObservers.append(model.agentList.$composing.sink { [weak self] row in
            guard row != nil else { return }
            self?.panel.ignoresMouseEvents = false
            self?.panel.makeKey()
        })
        // Selecting a session takes the keyboard too, for ↑↓, Return and ⌘M (see `handlesAgentKey`).
        settingsObservers.append(model.agentList.$selected.sink { [weak self] id in
            guard id != nil else { return }
            self?.panel.makeKey()
        })
        let settings = model.settings
        settingsObservers.append(Publishers.CombineLatest4(settings.$searchHotkey, settings.$searchHotKey, settings.$shortcuts, settings.$recordingShortcut)
            .sink { [weak self] enabled, search, others, recording in
                guard let self else { return }
                self.hotKeys = [:]
                guard !recording else { return }
                var taken: Set<ShortcutAction> = []
                for (action, combo) in ShortcutAction.active(searchEnabled: enabled, search: search, others: others) {
                    let key = GlobalHotKey(combo: combo) { [weak self] in self?.perform(action) }
                    if key.isRegistered { self.hotKeys[action] = key } else { taken.insert(action) }
                }
                self.model.settings.shortcutsTaken = taken
            })
        model.search.onFinish = { [weak self] in
            guard let self, self.model.isExpanded else { return }
            self.model.collapse()
            self.panel.ignoresMouseEvents = true
        }
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self else { return event }
            if MainActor.assumeIsolated({ self.handlesTourKey(event) || self.handlesRecapKey(event) }) { return nil }
            guard event.keyCode == 53 else {
                return MainActor.assumeIsolated { self.handlesAgentKey(event) || self.handlesPanelKey(event) } ? nil : event
            }
            MainActor.assumeIsolated {
                // Escape closes the message field or the diff first, and the notch only the next time.
                if self.model.agentList.composing != nil { self.model.agentList.cancelCompose(); return }
                if self.model.agentList.diffing != nil, self.model.agentList.isShowing { self.model.agentList.closeDiff(); return }
                self.model.collapse()
                self.panel.ignoresMouseEvents = true
            }
            return nil
        }) {
            monitors.append(keys)
        }
        settingsObservers.append(model.settings.$weatherCity.combineLatest(model.settings.$headerWeather,
                                                                           model.settings.$idleLeft, model.settings.$idleRight)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] city, header, left, right in
                self?.model.weather.setCity(header || left == .weather || right == .weather ? city : "")
            })
        // The limits are also read in the background for the limit alerts, not only for an ear that shows them.
        settingsObservers.append(model.settings.$idleLeft.combineLatest(model.settings.$idleRight, model.settings.$limitAlerts)
            .map { left, right, alerts in left.usesAIUsage || right.usesAIUsage ? 20 : alerts ? 60 : nil as TimeInterval? }
            .removeDuplicates()
            .sink { [weak self] interval in
                guard let self else { return }
                self.aiUsageTimer?.invalidate()
                self.aiUsageTimer = nil
                guard let interval else { return }
                self.model.aiUsage.refresh(includeTokens: false)
                self.aiUsageTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.model.aiUsage.refresh(includeTokens: false) }
                }
                self.aiUsageTimer?.tolerance = 2
            })
        settingsObservers.append(model.settings.$lyricsEnabled.sink { [weak self] enabled in
            guard let self else { return }
            self.model.lyrics.isEnabled = enabled
            self.model.lyrics.update(for: enabled ? self.model.nowPlaying.track : nil)
        })
        // A click on a notice goes to the terminal, and where possible the pane, it came from. Every one is also kept
        // in the Notifications tab, in case it went by unseen.
        model.notifyServer.onNotify = { [weak self] notice in
            self?.announce(symbol: BrowMood.waiting.symbol, title: notice.title, detail: notice.message,
                           action: TerminalFocus.action(app: notice.app, target: notice.target))
        }
        model.cmux.onNotice = { [weak self] notice in
            self?.announce(symbol: "terminal", title: String(notice.title.prefix(80)),
                           detail: notice.body.isEmpty ? nil : String(notice.body.prefix(200)), action: { Cmux.focus(notice) })
        }
        model.herdr.onNotice = { [weak self] notice, session in
            // herdr may be watched only for the agents count, with its notices turned off.
            guard self?.model.settings.herdrNotifications == true else { return }
            let state = notice.status == "blocked" ? String(localized: "Waiting for you") : String(localized: "Finished")
            let detail = [state, notice.title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            // A named session shows its name beside the agent.
            let title = session.map { "\(notice.agent) · \($0)" } ?? notice.agent
            let mood: BrowMood = notice.status == "blocked" ? .waiting : .happy
            self?.announce(symbol: mood.symbol, title: String(title.prefix(80)), detail: String(detail.prefix(200)),
                           action: { Herdr.focus(notice) })
        }
        model.paseoWatcher.onNotice = { [weak self] notice in
            self?.announce(symbol: "sparkles", title: notice.title, detail: notice.detail, action: notice.open)
        }
        model.muxy.onNotice = { [weak self] event, project, folder in
            guard let title = event.notice(project: project) else { return }
            let session = event.session
            self?.announce(symbol: "terminal", title: String(title.prefix(80)), detail: nil, action: {
                DispatchQueue.global(qos: .userInitiated).async {
                    MuxyFocus.run(session: session, folder: folder)
                    DispatchQueue.main.async { TerminalFocus.activate(bundleID: Muxy.bundleID) }
                }
            })
        }
        // App volume taps run whenever the setting is on; the list of apps refreshes only while the Tools tab shows.
        // Once it has closed, the notch catches up with a pointer that went to another screen and stopped there.
        settingsObservers.append(model.$isExpanded.removeDuplicates().dropFirst().filter { !$0 }.sink { [weak self] _ in
            guard let self else { return }
            closedAt = .now
            followWork?.cancel()
            let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.followPointer(to: NSEvent.mouseLocation) } }
            followWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeSettle, execute: work)
        })
        // A pop-up shows where the pointer is, so it isn't missed on another display.
        for appears in [model.hud.$event.map { $0 != nil }.eraseToAnyPublisher(),
                        model.approvals.$prompts.map { !$0.isEmpty }.eraseToAnyPublisher(),
                        model.$sneakPeekPending.eraseToAnyPublisher()] {
            settingsObservers.append(appears.removeDuplicates().filter { $0 }.sink { [weak self] _ in self?.showPopUpUnderPointer() })
        }
        settingsObservers.append(model.settings.$perAppVolume.combineLatest(model.$isExpanded, model.$tab)
            .sink { [weak self] enabled, expanded, tab in
                self?.model.appVolume.update(enabled: enabled, listing: expanded && tab == .tools)
            })
        settingsObservers.append(model.settings.$cleanLinks.sink { [weak self] in self?.model.clipboard.cleansLinks = $0 })
        settingsObservers.append(model.settings.$screenshotsToShelf.sink { [weak self] in self?.model.screenshots.isEnabled = $0 })
        model.timer.onFinished = { [weak self] message in
            self?.model.hud.show(.notice(symbol: "timer", title: message, detail: nil), duration: 4)
        }
        // The publisher sends the new value before the setting changes, so the value is passed along.
        for feature in features {
            settingsObservers.append(model.settings[keyPath: feature.changes].sink { [weak self] enabled in
                guard let self else { return }
                if enabled && self.panel.isVisible { feature.start() } else { feature.stop(false) }
            })
        }
        // The feature above refreshes what is connected, but only while notifications are on and the notch is showing;
        // hooks of an older version that put the token on curl's command line are replaced regardless.
        NotifyIntegration.replaceLegacyTokenCommands()
        // A Nunsseop that crashed with tmux bells on left its hook; with the feature off now, it comes off once.
        if !(model.settings.tmuxBells && model.settings.localNotifications) { model.tmux.clearLeftover() }
        updatesObserver = model.settings.$checkForUpdates
            .removeDuplicates()
            .sink { UpdateChecker.shared.startAutomaticChecks(enabled: $0) }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.relayoutAsScreensSettle() }
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            wakeObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.relayoutAsScreensSettle() }
            })
        }
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            fullScreenObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkFullScreenAsItSettles() }
            })
        }
        browHideObserver = model.settings.$autoHideBrow.map { _ in () }
            .merge(with: model.settings.$browHideDelay.map { _ in () })
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.model.resetBrowHide() }
            }
        model.resetBrowHide()
        displayObserver = model.settings.$displayName.map { _ in () }
            .merge(with: model.settings.$showInClamshell.map { _ in () },
                   model.settings.$followPointerAcrossDisplays.map { _ in () })
            .dropFirst(3)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.relayout() }
            }
    }

    /// Puts every app back to full volume before quitting.
    func prepareToQuit() {
        model.appVolume.shutdown()
        model.notes.flush()
    }

    /// Closing or opening the lid announces the change before the list of screens has caught up with it, and no second
    /// notice follows, so the screen is picked again once things have settled.
    private func relayoutAsScreensSettle() {
        relayout()
        settleWork.forEach { $0.cancel() }
        settleWork = [0.5, 2].map { delay in
            let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.relayout() } }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return work
        }
    }

    /// With no display chosen in Settings and following turned on, the closed notch moves to the screen the pointer goes to.
    /// It stays put while it is open or shows a pop-up.
    private func followPointer(to point: NSPoint) {
        guard followsPointer, isIdle, Self.hasSettled(closedAt: closedAt, now: .now),
              NotchGeometry.pointerLeft(model.geometry.screenFrame, for: point, among: NSScreen.screens.map(\.frame)) else { return }
        relayout()
    }

    /// Takes the closed notch to the pointer's screen as a pop-up is about to show. The pop-up is not on screen yet, so the
    /// notch is moved as if it were idle.
    private func showPopUpUnderPointer() {
        let point = NSEvent.mouseLocation
        guard followsPointer, !model.isExpanded, Self.hasSettled(closedAt: closedAt, now: .now),
              NotchGeometry.pointerLeft(model.geometry.screenFrame, for: point, among: NSScreen.screens.map(\.frame)) else { return }
        relayout(followingPointer: true)
    }

    /// How long the closing notch takes to settle. Moved sooner, it would finish closing on the other screen.
    nonisolated static let closeSettle: TimeInterval = 0.5

    nonisolated static func hasSettled(closedAt: Date, now: Date) -> Bool { now.timeIntervalSince(closedAt) >= closeSettle }

    private var followsPointer: Bool {
        Self.followsPointer(displayName: model.settings.displayName, enabled: model.settings.followPointerAcrossDisplays)
    }

    nonisolated static func followsPointer(displayName: String, enabled: Bool) -> Bool { displayName.isEmpty && enabled }

    /// The point a screen is picked by: the pointer's while the notch may follow it; the notch's own screen while it is open
    /// or shows a pop-up; none when it stays on its display, which is then the one with a camera housing or the main one.
    nonisolated static func screenPoint(following: Bool, idle: Bool, pointer: NSPoint, current: NSRect) -> NSPoint? {
        guard idle else { return NSPoint(x: current.midX, y: current.midY) }
        return following ? pointer : nil
    }

    /// Closed with nothing showing, so the notch may change screens.
    private var isIdle: Bool { !model.isExpanded && model.hud.event == nil && model.approvals.current == nil }

    private func relayout(followingPointer: Bool? = nil) {
        // An open notch or a pop-up stays on its screen while that screen is still there.
        let pointer = Self.screenPoint(following: followsPointer, idle: followingPointer ?? isIdle,
                                       pointer: NSEvent.mouseLocation, current: model.geometry.screenFrame)
        guard let screen = NotchGeometry.pickScreen(preferredName: model.settings.displayName, pointer: pointer) else { return }
        model.geometry = NotchGeometry(screen: screen)
        panel.setFrame(model.geometry.panelFrame, display: true)
        checkFullScreen()
        model.resetBrowHide()
        updateVisibility()
    }

    /// Notes whether an app is full screen on the notch's screen. Only a screen without a camera housing needs to know: on one
    /// with it, the app stays below the housing.
    private func checkFullScreen() {
        model.fullScreenInFront = !model.geometry.hasNotch && FullScreenWindows.cover(screenFrame: model.geometry.screenFrame)
    }

    /// An app going full screen may still be growing into the screen when the space changes, so it is looked at again once that
    /// animation has had time to end.
    private func checkFullScreenAsItSettles() {
        checkFullScreen()
        fullScreenWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.checkFullScreen() } }
        fullScreenWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    /// Hides the notch in clamshell mode when the user turned that off.
    private func updateVisibility() {
        let hidden = !model.settings.showInClamshell && NotchGeometry.lidIsClosed
        if hidden {
            model.collapse()
            panel.ignoresMouseEvents = true
            panel.orderOut(nil)
            // Nothing can be shown while hidden, so stop the watchers that only feed the notch.
            for feature in features { feature.stop(true) }
        } else if !panel.isVisible {
            panel.orderFrontRegardless()
            for feature in features where model.settings[keyPath: feature.setting] { feature.start() }
        }
    }

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.pointerMoved(type) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.pointerMoved(type) }
            return event
        }) {
            monitors.append(local)
        }
        if let scroll = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            let overHeader = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                self.scrolled(event)
                return self.isWheelOverHeader(event)
            }
            return overHeader ? (Self.sideways(event) ?? event) : event
        }) {
            monitors.append(scroll)
        }
    }

    /// A mouse wheel turned over the expanded header scrolls the tab row sideways.
    private func isWheelOverHeader(_ event: NSEvent) -> Bool {
        event.window === panel && model.isExpanded && !event.hasPreciseScrollingDeltas
            && event.scrollingDeltaX == 0 && event.scrollingDeltaY != 0
            && SwipeRecognizer.isOverHeader(fromTop: panel.frame.height - event.locationInWindow.y,
                                            collapsedHeight: model.geometry.collapsedSize.height)
    }

    nonisolated static func sideways(_ event: NSEvent) -> NSEvent? {
        guard let copy = event.cgEvent?.copy() else { return nil }
        for (vertical, horizontal) in [(CGEventField.scrollWheelEventDeltaAxis1, CGEventField.scrollWheelEventDeltaAxis2),
                                       (.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2),
                                       (.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2)] {
            copy.setIntegerValueField(horizontal, value: copy.getIntegerValueField(vertical))
            copy.setIntegerValueField(vertical, value: 0)
        }
        return NSEvent(cgEvent: copy)
    }

    /// Turns two-finger swipes over the notch into open/close and track skips.
    /// Each swipe fires at most once; it ends when the gesture ends or input pauses.
    private func scrolled(_ event: NSEvent) {
        let settings = model.settings
        guard settings.swipeToOpen || settings.swipeForTracks else { return }
        // Scrolling a long list of tools in the tour must not close it.
        if model.isExpanded && model.onboarding.isActive { return }
        guard SwipeRecognizer.accepts(overPanel: event.window === panel, precise: event.hasPreciseScrollingDeltas,
                                      momentum: !event.momentumPhase.isEmpty) else { return }
        // Scrolling over the timer's time changes its length instead.
        if TimeScrollTarget.isHovered { return }
        let fromTop = panel.frame.height - event.locationInWindow.y
        if model.isExpanded && SwipeRecognizer.isOverHeader(fromTop: fromTop, collapsedHeight: model.geometry.collapsedSize.height) { return }
        if event.phase == .began || event.phase == .mayBegin { swipe.reset() }

        swipeIdleWork?.cancel()
        let idle = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.swipe.reset() }
        }
        swipeIdleWork = idle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: idle)

        // Finger direction regardless of the natural scrolling setting.
        let tracks = settings.swipeForTracks && model.isExpanded && model.tab == .home && model.nowPlaying.track != nil
        switch swipe.add(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, inverted: event.isDirectionInvertedFromDevice,
                         opens: settings.swipeToOpen, tracks: tracks) {
        case .open: model.expand()
        case .close: model.collapse()
        case .nextTrack: model.nowPlaying.send(.next)
        case .previousTrack: model.nowPlaying.send(.previous)
        case nil: break
        }
    }

    /// ↑↓, Return and ⌘M in the Agents tab, while the notch is the key window and nothing else wants the keys: not while a
    /// message is typed (its field takes Return), not behind a permission card, not in another text field. True when the tab used the key.
    private func handlesAgentKey(_ event: NSEvent) -> Bool {
        guard event.window === panel, model.isExpanded, model.approvals.current == nil, model.agentList.isShowing,
              model.agentList.composing == nil, !(panel.firstResponder is NSText),
              let key = AgentKey(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers, modifiers: event.modifierFlags) else { return false }
        return model.agentList.perform(key)
    }

    /// ↑↓ for the tab that lists items (see `PanelKeys`), under the same conditions as the Agents tab's keys. True when the tab used the key.
    private func handlesPanelKey(_ event: NSEvent) -> Bool {
        guard event.window === panel, model.isExpanded, model.approvals.current == nil, model.tab != .agents,
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty, !(panel.firstResponder is NSText) else { return false }
        switch event.keyCode {
        case 125: return PanelKeys.move(1)
        case 126: return PanelKeys.move(-1)
        default: return false
        }
    }

    /// A faded eyebrow comes back when the pointer arrives and raises, then opens, only if the pointer stays.
    private func pointerOverCollapsedChanged(_ over: Bool) {
        let fromFaded = model.browFaded
        liftWork?.cancel()
        liftWork = nil
        model.pointerOverCollapsed = over
        model.browRevealing = over && fromFaded
        guard over else {
            model.browLifted = false
            return
        }
        guard fromFaded else {
            model.browLifted = true
            return
        }
        model.browLifted = false
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.model.pointerOverCollapsed else { return }
                self.model.browLifted = true
            }
        }
        liftWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchViewModel.browRevealDwell, execute: work)
    }

    private func pointerMoved(_ type: NSEvent.EventType) {
        if type == .leftMouseUp { idleDragCount = NSPasteboard(name: .drag).changeCount }
        guard panel.isVisible else { return }
        let point = NSEvent.mouseLocation
        followPointer(to: point)
        // Every shape fits in the panel, so away from it the pointer is outside without working out the shape's size.
        let nearPanel = panel.frame.insetBy(dx: -8, dy: -8).contains(point)

        defer { wasExpanded = model.isExpanded }

        let overCollapsed = !model.isExpanded && nearPanel && model.collapsedRect.contains(point)
        if model.pointerOverCollapsed != overCollapsed { pointerOverCollapsedChanged(overCollapsed) }

        if model.isExpanded {
            let inside = nearPanel && model.geometry.shapeRect(size: model.expandedSize, inset: model.geometry.expandedInset).insetBy(dx: -6, dy: -6).contains(point)
            switch OpenNotchHold.of(composing: model.agentList.composing != nil, touring: model.onboarding.isActive, pinned: model.pinned) {
            case .composing:
                // Typing a message to an agent: the notch stays open wherever the pointer goes, until the field closes.
                collapseWork?.cancel()
                collapseWork = nil
                panel.ignoresMouseEvents = false
                return
            case .touring:
                collapseWork?.cancel()
                collapseWork = nil
                panel.ignoresMouseEvents = !inside
                return
            case .pinned:
                if inside { model.pinned = false }
                panel.ignoresMouseEvents = false
                return
            case .followsPointer:
                break
            }
            panel.ignoresMouseEvents = !inside
            if inside {
                collapseWork?.cancel()
                collapseWork = nil
            } else if collapseWork == nil {
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated {
                        self?.model.collapse()
                        self?.collapseWork = nil
                        self?.panel.ignoresMouseEvents = true
                    }
                }
                collapseWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
            }
        } else {
            let inside = nearPanel && model.collapsedRect.contains(point)
            panel.ignoresMouseEvents = !inside
            if wasExpanded && inside { hoverOpenBlocked = true }
            // Files dragged onto the notch open it even right after it closed; text selections and window moves don't.
            if hoverOpenBlocked && inside && type == .leftMouseDragged {
                let drag = NSPasteboard(name: .drag)
                if drag.changeCount != idleDragCount && drag.types?.contains(.fileURL) == true { hoverOpenBlocked = false }
            }
            if !inside {
                openWork?.cancel()
                openWork = nil
                hoverOpenBlocked = false
            } else if openWork == nil && !hoverOpenBlocked && model.hud.action == nil && model.approvals.current == nil {
                // While a notice that can be clicked or a permission prompt shows, hovering doesn't open the notch, so they can be clicked.
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated {
                        self?.openWork = nil
                        guard let self, self.model.collapsedRect.contains(NSEvent.mouseLocation) else { return }
                        self.model.expand()
                    }
                }
                openWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + NotchViewModel.hoverOpenDelay(base: model.settings.openDelay, browRevealing: model.browRevealing), execute: work)
            }
        }
    }
}
