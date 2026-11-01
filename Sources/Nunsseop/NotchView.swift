import SwiftUI

struct NotchView: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var nowPlaying: NowPlayingController
    @State private var isDropTargeted = false
    @State private var isAirDropTargeted = false
    /// The ears as they were drawn last, to tell which way they move next. Read while drawing and written after, so it
    /// is not state the view redraws for.
    @State private var earsMemory = EarsMemory()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: NotchViewModel) {
        self.model = model
        self.nowPlaying = model.nowPlaying
    }

    var body: some View {
        let size = model.currentSize
        let topRadius: CGFloat = model.isExpanded ? 18 : 6
        let bottomRadius: CGFloat = model.isExpanded ? 26 : 14
        let notchHeight = model.geometry.collapsedSize.height
        let shape = NotchShape(topRadius: model.geometry.hasNotch ? topRadius : (model.isExpanded ? 0 : 14), bottomRadius: bottomRadius, floating: !model.geometry.hasNotch,
                              sideInset: !model.geometry.hasNotch && model.isExpanded ? 18 : 0)
        // With the left ear hidden, the collapsed shape grows right only and its top row starts past the camera.
        let shift = model.isExpanded ? 0 : model.collapsedShift
        let earLead = NotchViewModel.earLead(shift: shift, notch: model.geometry.collapsedSize.width)

        let ears = earsMotion

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchBackground(shape: shape, glass: model.settings.liquidGlass, tint: (model.isExpanded ? model.settings.glassTint : model.settings.browGlassTint) / 100, expanded: model.isExpanded, notchHeight: notchHeight,
                                floatingPill: !model.geometry.hasNotch)
                    // Without this, content being removed is drawn under the black body and vanishes instead of fading.
                    .zIndex(-1)

                if !model.isExpanded && !model.geometry.hasNotch && !model.hudSingleRow && !model.sneakPeekInline {
                    EyebrowMark(lift: model.browFaded ? -1 : model.browLifted ? 1 : 0, mood: model.browMood, hops: reduceMotion ? 0 : model.browHops)
                        .animation(model.browFaded ? .easeIn(duration: 0.3) : motion.brow, value: model.browFaded)
                        .animation(motion.brow, value: model.browLifted)
                        .animation(motion.mood, value: model.browMood)
                        .frame(width: model.geometry.collapsedSize.width, height: notchHeight)
                        .padding(.leading, NotchViewModel.browLead(width: size.width, notch: model.geometry.collapsedSize.width, shift: shift))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }

                if model.onboarding.shows(expanded: model.isExpanded, approvalShowing: model.approvals.current != nil) {
                    OnboardingView(tour: model.onboarding, settings: model.settings,
                                   hasNotch: model.geometry.hasNotch && !model.onboarding.showsWithoutNotch,
                                   bandHeight: OnboardingTour.band(notchHeight: notchHeight))
                        .padding(.horizontal, topRadius + 14)
                        .padding(.bottom, 16)
                        .transition(motion.expandedContent)
                } else if model.isExpanded {
                    VStack(spacing: 0) {
                        HeaderBar(model: model, height: notchHeight)
                        // The tab stays where it is under a permission prompt, so what was typed in it is still there after.
                        ZStack(alignment: .top) {
                            Group {
                                switch model.tab {
                                case .home:
                                    VStack(spacing: 8) {
                                        if let call = model.calls.call, let controls = model.callControls.state {
                                            CallRow(call: call, state: controls) { model.callControls.toggle($0) }
                                        }
                                        HomePanels(nowPlaying: nowPlaying, lyrics: model.settings.lyricsEnabled ? model.lyrics : nil,
                                                   calendar: model.settings.calendarEnabled ? model.calendar : nil,
                                                   showsReminders: model.settings.remindersEnabled,
                                                   weather: model.settings.headerWeather ? model.weather : nil)
                                    }
                                case .shelf:
                                    ShelfView(shelf: model.shelf, isDropTargeted: isDropTargeted && !isAirDropTargeted,
                                              isAirDropTargeted: isAirDropTargeted)
                                case .timer:
                                    TimerTab(timer: model.timer)
                                case .clipboard:
                                    ClipboardTab(history: model.clipboard)
                                case .notes:
                                    NotesTab(notes: model.notes)
                                case .tools:
                                    ToolsTab(tools: model.tools, recorder: model.recorder, recordAudio: model.settings.recordAudio,
                                             appVolume: model.settings.perAppVolume ? model.appVolume : nil)
                                case .system:
                                    SystemTab(stats: model.stats, peripherals: model.settings.peripheralBatteries ? model.peripherals : nil,
                                              power: model.settings.batteryInHeader ? model.hud.power : nil)
                                case .apps:
                                    AppsTab(launcher: model.launcher)
                                case .search:
                                    SearchTab(model: model.search, shortcut: model.settings.searchHotkey ? model.settings.searchHotKey.label : nil)
                                case .emoji:
                                    EmojiTab(model: model.emoji)
                                case .ai:
                                    AIUsageTab(usage: model.aiUsage) { model.recap.show() }
                                case .notices:
                                    NoticesTab(log: model.notices)
                                case .agents:
                                    AgentsTab(model: model.agentList)
                                case .mirror:
                                    MirrorTab(mirror: model.mirror, deviceID: model.settings.mirrorCameraID)
                                }
                            }
                            .allowsHitTesting(model.approvals.current == nil && !model.recap.isShowing)
                            .disabled(model.approvals.current != nil || model.recap.isShowing)
                            .opacity(model.approvals.current == nil && !model.recap.isShowing ? 1 : 0)
                            .accessibilityHidden(model.approvals.current != nil || model.recap.isShowing)
                            if model.recap.isShowing && model.approvals.current == nil {
                                RecapView(card: model.recap)
                            }
                            if let prompt = model.approvals.current {
                                PermissionPanel(prompt: prompt, count: model.approvals.prompts.count, gate: model.approvals.gate,
                                                draft: model.approvals.draft(for: prompt), act: { model.approvals.act(prompt, $0) }) {
                                    model.approvals.answerByClick(prompt, $0)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // A list that fits its cell would otherwise spring up and down under a swipe.
                        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, topRadius + 14)
                    // As far from the bottom edge as from the sides.
                    .padding(.bottom, 14)
                    // No scale here: scaling the scrolling tab row while it appears leaves it a few points off.
                    .transition(motion.expandedContent)
                } else if let prompt = model.approvals.current {
                    PermissionCard(prompt: prompt, count: model.approvals.prompts.count, height: notchHeight,
                                   earWidth: NotchViewModel.hudEarWidth, leadingInset: earLead, hasNotch: model.geometry.hasNotch,
                                   gate: model.approvals.gate, draft: model.approvals.draft(for: prompt),
                                   act: { model.approvals.act(prompt, $0) }) {
                        model.approvals.answerByClick(prompt, $0)
                    }
                    .padding(.horizontal, topRadius + 12)
                    .transition(motion.hudContent)
                } else if let event = model.hud.event {
                    HUDContent(event: event, height: notchHeight, earWidth: NotchViewModel.hudEarWidth, leadingInset: earLead,
                               singleLine: model.hudSingleRow)
                        .padding(.horizontal, topRadius + 12)
                        .transition(motion.hudContent)
                } else if model.showsLiveActivity || model.showsSneakPeek || model.showsIdleEars {
                    VStack(spacing: 0) {
                        ZStack {
                            if model.showsLiveActivity {
                                CollapsedActivity(nowPlaying: nowPlaying, timer: model.timer, recorder: model.recorder, downloads: model.downloads,
                                                  privacy: model.settings.privacyIndicator ? model.privacy : nil, call: model.calls.call,
                                                  callMuted: model.callControls.state?.mic == .off,
                                                  height: notchHeight,
                                                  showsMusic: model.settings.collapsedMusic, showsTimer: model.settings.collapsedTimer,
                                                  showsDownloads: model.settings.collapsedDownloads)
                                // Sides of different widths shift the shape without hiding the left one.
                                .padding(.leading, model.hidesLeftEar ? earLead : 0)
                            } else if model.showsIdleEars && !model.sneakPeekInline {
                                IdleEars(model: model, height: notchHeight)
                                    .padding(.leading, model.idleFits
                                             ? NotchViewModel.idleLead(browLead: NotchViewModel.browLead(width: size.width, notch: model.geometry.collapsedSize.width, shift: shift),
                                                                       shift: shift, notch: model.geometry.collapsedSize.width)
                                             : earLead)
                            } else {
                                Color.clear.frame(height: notchHeight)
                            }
                            if model.sneakPeekInline {
                                peekLine
                                    // A line longer than its room gives up a little size before it truncates.
                                    .minimumScaleFactor(0.9)
                                    .frame(width: model.inlinePeekWidth, height: notchHeight)
                                    .transition(.opacity)
                            }
                        }
                        if model.showsSneakPeek && !model.sneakPeekInline {
                            peekLine
                                .frame(height: NotchViewModel.sneakPeekHeight, alignment: .top)
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, topRadius + 7)
                    .transition(motion.collapsedContent)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .contentShape(shape)
            // A notice that leads somewhere (a terminal) goes there; otherwise a click opens the notch.
            .onTapGesture { if !model.hud.performAction() { model.expand() } }
            .contextMenu {
                Button("Settings…") { SettingsWindowController.shared.show() }
                Button("Quit Nunsseop") { NSApp.terminate(nil) }
            }
            .onDrop(of: [.fileURL], delegate: NotchDropDelegate(
                model: model,
                isTargeted: $isDropTargeted,
                isAirDropTargeted: $isAirDropTargeted,
                airDropRect: airDropRect(in: size)
            ))
            .offset(x: shift + (model.isExpanded ? 0 : model.geometry.restShift))
            // Fading out waits for the brow to lower first, like an eye closing; coming back shows at once.
            // Scoped to the opacity, so the shape resizing when a HUD or live activity ends isn't held back too.
            .animation(model.browFaded ? .easeIn(duration: 0.3).delay(0.28) : .easeOut(duration: 0.2)) {
                $0.opacity(model.browFaded ? 0 : 1)
            }
            .padding(.top, model.isExpanded ? 0 : model.geometry.topInset)
            // Ears appearing is when the app's menus matter, so they are read again then.
            .onChange(of: model.collapsedSize.width) { old, new in
                if new > old { model.appMenus.refresh() }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.liquidGlass, model.settings.liquidGlass)
        // Each animation is picked by the state being entered: growing springs overshoot a little, shrinking ones don't.
        .animation(model.isExpanded ? motion.open : motion.close, value: model.isExpanded)
        .animation(model.showsLiveActivity ? motion.earsGrow : motion.earsShrink, value: model.showsLiveActivity)
        // A clock gaining a digit, a download its percent, the activity changing what a side holds, or a peek coming and
        // going. These change together (a peek ending evens out the sides no more), so one animation is picked by the
        // direction the shape's size takes rather than by whichever of several modifiers applies last.
        .animation(ears.grows ? motion.earsGrow : motion.earsShrink, value: ears.frame.key)
        .onChange(of: ears.frame, initial: true) { _, frame in earsMemory.last = frame }
        .animation(model.showsIdleEars ? motion.earsGrow : motion.earsShrink, value: model.showsIdleEars)
        .animation(motion.earsGrow, value: model.inlinePeekWidth)
        .animation(model.hud.event != nil ? motion.earsGrow : motion.earsShrink, value: model.hud.event)
        .animation(model.approvals.current != nil ? motion.earsGrow : motion.earsShrink, value: model.approvals.current?.id)
        // The shape slides over when the left ear hides or shows, rather than jumping.
        .animation(motion.earsGrow, value: model.collapsedShift)
        .animation(.easeInOut(duration: 0.18), value: model.tab)
    }

    private var motion: NotchMotion { NotchMotion(reduceMotion: reduceMotion) }

    /// The ears' frame now, and whether they grow or shrink from the one drawn last.
    private var earsMotion: (frame: NotchViewModel.EarsFrame, grows: Bool) {
        let frame = NotchViewModel.EarsFrame(size: model.collapsedSize, sides: model.liveEarSides, peek: model.showsSneakPeek)
        return (frame, earsMemory.last.map { NotchViewModel.earsGrow(from: $0, to: frame) } ?? true)
    }

    /// The call that is starting, or the track or its sung line.
    @ViewBuilder private var peekLine: some View {
        if let title = model.sneakPeekCallTitle {
            HStack(spacing: 6) {
                Image(systemName: "phone.fill").font(.system(size: 8)).foregroundStyle(.green)
                Text(title).foregroundStyle(.white)
            }
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 10)
        } else if let track = nowPlaying.track {
            SneakPeekLine(track: track, lyrics: model.settings.lyricsEnabled ? model.lyrics : nil)
        }
    }
}

/// The ears as last drawn; a reference so that writing it doesn't redraw the notch.
private final class EarsMemory {
    var last: NotchViewModel.EarsFrame?
}

/// How the notch opens, closes and grows its ears. The shape's size and corner radii move together on one spring;
/// content fades in once the shape has room for it and fades out before the shape shrinks around it.
/// With Reduce Motion everything is a short ease without overshoot, and content only fades.
private struct NotchMotion {
    let reduceMotion: Bool

    private static let fade = Animation.easeInOut(duration: 0.15)
    private static let ease = Animation.easeInOut(duration: 0.2)

    /// About 3% overshoot, settled in roughly 0.45 s.
    var open: Animation { reduceMotion ? Self.ease : .spring(response: 0.4, dampingFraction: 0.75) }
    /// Critically damped and quicker; it waits a moment for the content to fade out first.
    var close: Animation { reduceMotion ? Self.ease : .spring(response: 0.3, dampingFraction: 1).delay(0.04) }
    /// A quick spring with a little bounce, like a brow popping up.
    var brow: Animation { reduceMotion ? Self.ease : .spring(response: 0.25, dampingFraction: 0.55) }
    /// Softer than a hover: the face changes as a mood settles in.
    var mood: Animation { reduceMotion ? Self.ease : .spring(response: 0.45, dampingFraction: 0.7) }
    var earsGrow: Animation { reduceMotion ? Self.ease : .spring(response: 0.34, dampingFraction: 0.75) }
    var earsShrink: Animation { reduceMotion ? Self.ease : .spring(response: 0.28, dampingFraction: 1) }

    /// Fades and settles down a few points once the shape is about halfway open; gone almost at once on close.
    /// The offset only moves pixels, so the tab row lays out where it ends up.
    var expandedContent: AnyTransition {
        if reduceMotion { return .opacity.animation(Self.fade) }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: -6)).animation(.easeOut(duration: 0.22).delay(0.09)),
            removal: .opacity.animation(.easeIn(duration: 0.08)))
    }

    /// The music, call and idle ears come back once the shape has nearly closed, and step aside at once when it opens.
    var collapsedContent: AnyTransition {
        if reduceMotion { return .opacity.animation(Self.fade) }
        return .asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.18).delay(0.16)),
                           removal: .opacity.animation(.easeIn(duration: 0.08)))
    }

    /// The HUD shows as soon as its ears have started to grow.
    var hudContent: AnyTransition {
        if reduceMotion { return .opacity.animation(Self.fade) }
        return .asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.16).delay(0.06)),
                           removal: .opacity.animation(.easeIn(duration: 0.08)))
    }
}

extension NotchView {
    /// Where ShelfView's right side, the one a drop sends to AirDrop, sits inside the expanded shape.
    func airDropRect(in size: CGSize) -> CGRect {
        Self.airDropRect(in: size, collapsedHeight: model.geometry.collapsedSize.height)
    }

    static func airDropRect(in size: CGSize, collapsedHeight: CGFloat) -> CGRect {
        let inset: CGFloat = 18 + 14
        let top = max(collapsedHeight, 24) + 8
        let split = inset + (size.width - 2 * inset) * ShelfView.listFraction
        return CGRect(x: split, y: top, width: size.width - inset - split, height: size.height - top - 16)
    }
}

/// Drops land on the shelf, or go straight to AirDrop when released over the AirDrop tile.
struct NotchDropDelegate: DropDelegate {
    let model: NotchViewModel
    @Binding var isTargeted: Bool
    @Binding var isAirDropTargeted: Bool
    let airDropRect: CGRect

    /// Not on the Agents tab: files dropped there belong to the session rows, and entering the notch would switch to the shelf.
    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL]) && !Self.agentsTabTakesDrops(expanded: model.isExpanded, tab: model.tab)
    }

    static func agentsTabTakesDrops(expanded: Bool, tab: NotchTab) -> Bool { expanded && tab == .agents }

    func dropEntered(info: DropInfo) {
        isTargeted = true
        model.tab = .shelf
        model.expand()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        isAirDropTargeted = Self.targetsAirDrop(at: info.location, in: airDropRect, expanded: model.isExpanded, tab: model.tab)
        return DropProposal(operation: .copy)
    }

    static func targetsAirDrop(at point: CGPoint, in rect: CGRect, expanded: Bool, tab: NotchTab) -> Bool {
        expanded && tab == .shelf && rect.contains(point)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
        isAirDropTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        let toAirDrop = isAirDropTargeted
        isTargeted = false
        isAirDropTargeted = false
        if toAirDrop {
            ShelfSharing.loadURLs(from: providers) { ShelfSharing.airDrop($0) }
            return true
        }
        return model.shelf.handleDrop(providers)
    }
}

/// A file drag held over a tab's button opens that tab after `delay`, so files can be taken to a tab that is not on screen yet
/// (a Shelf item to a session in the Agents tab). It never takes the drop itself.
@MainActor
final class TabDragHover {
    static let delay: TimeInterval = 0.6
    private let schedule: (TimeInterval, DispatchWorkItem) -> Void
    private var pending: DispatchWorkItem?

    init(schedule: @escaping (TimeInterval, DispatchWorkItem) -> Void = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }) {
        self.schedule = schedule
    }

    func entered(open: @escaping () -> Void) {
        pending?.cancel()
        let work = DispatchWorkItem { open() }
        pending = work
        schedule(Self.delay, work)
    }

    func exited() {
        pending?.cancel()
        pending = nil
    }
}

struct TabDragHoverDelegate: DropDelegate {
    let hover: TabDragHover
    let open: () -> Void

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }
    func dropEntered(info: DropInfo) { hover.entered(open: open) }
    func dropExited(info: DropInfo) { hover.exited() }
    func performDrop(info: DropInfo) -> Bool {
        hover.exited()
        return false
    }
}
