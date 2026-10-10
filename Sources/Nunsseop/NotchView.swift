import SwiftUI

struct NotchView: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var nowPlaying: NowPlayingController
    @State private var isDropTargeted = false
    @State private var isAirDropTargeted = false
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
        let earLead = shift > 0 ? model.geometry.collapsedSize.width - 6 : 0

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchBackground(shape: shape, glass: model.settings.liquidGlass, tint: (model.isExpanded ? model.settings.glassTint : model.settings.browGlassTint) / 100, expanded: model.isExpanded, notchHeight: notchHeight,
                                floatingPill: !model.geometry.hasNotch)
                    // Without this, content being removed is drawn under the black body and vanishes instead of fading.
                    .zIndex(-1)

                if !model.isExpanded && !model.geometry.hasNotch && !model.hudSingleRow {
                    EyebrowMark(lift: model.browFaded ? -1 : model.browLifted ? 1 : 0)
                        .animation(model.browFaded ? .easeIn(duration: 0.3) : motion.brow, value: model.browFaded)
                        .animation(motion.brow, value: model.browLifted)
                        .frame(width: model.geometry.collapsedSize.width, height: notchHeight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: shift > 0 ? .topLeading : shift < 0 ? .topTrailing : .top)
                }

                if model.isExpanded {
                    VStack(spacing: 0) {
                        HeaderBar(model: model, height: notchHeight)
                        Group {
                            switch model.tab {
                            case .home:
                                VStack(spacing: 8) {
                                    if let call = model.calls.call, let controls = model.callControls.state {
                                        CallRow(call: call, state: controls) { model.callControls.toggle($0) }
                                    }
                                    HStack(spacing: 16) {
                                        HomeTab(nowPlaying: nowPlaying, lyrics: model.settings.lyricsEnabled ? model.lyrics : nil)
                                        if model.settings.calendarEnabled {
                                            // A wide notch gives the calendar room for the whole week in large digits.
                                            let wide = model.expandedSize.width >= 700
                                            CalendarPanel(calendar: model.calendar, showsReminders: model.settings.remindersEnabled, wide: wide)
                                                .frame(width: wide ? 220 : 168)
                                        }
                                    }
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
                                SystemTab(stats: model.stats, peripherals: model.settings.peripheralBatteries ? model.peripherals : nil)
                            case .apps:
                                AppsTab(launcher: model.launcher)
                            case .search:
                                SearchTab(model: model.search, shortcut: model.settings.searchHotkey ? model.settings.searchHotKey.label : nil)
                            case .emoji:
                                EmojiTab(model: model.emoji)
                            case .ai:
                                AIUsageTab(usage: model.aiUsage)
                            case .notices:
                                NoticesTab(log: model.notices)
                            case .mirror:
                                MirrorTab(mirror: model.mirror, deviceID: model.settings.mirrorCameraID)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, topRadius + 14)
                    .padding(.bottom, 16)
                    // No scale here: scaling the scrolling tab row while it appears leaves it a few points off.
                    .transition(motion.expandedContent)
                } else if let event = model.hud.event {
                    HUDContent(event: event, height: notchHeight, earWidth: NotchViewModel.hudEarWidth, leadingInset: earLead,
                               singleLine: model.hudSingleRow)
                        .padding(.horizontal, topRadius + 12)
                        .transition(motion.hudContent)
                } else if model.showsLiveActivity || model.showsSneakPeek || model.showsIdleEars {
                    VStack(spacing: 0) {
                        if model.showsLiveActivity {
                            CollapsedActivity(nowPlaying: nowPlaying, timer: model.timer, recorder: model.recorder, downloads: model.downloads,
                                              privacy: model.settings.privacyIndicator ? model.privacy : nil, call: model.calls.call,
                                              callMuted: model.callControls.state?.mic == .off,
                                              height: notchHeight, earWidth: model.earWidth,
                                              showsMusic: model.settings.collapsedMusic, showsTimer: model.settings.collapsedTimer,
                                              showsDownloads: model.settings.collapsedDownloads)
                            .padding(.leading, earLead)
                        } else if model.showsIdleEars {
                            IdleEars(model: model, height: notchHeight)
                                .padding(.leading, earLead)
                        } else {
                            Color.clear.frame(height: notchHeight)
                        }
                        if model.showsSneakPeek, let title = model.sneakPeekCallTitle {
                            HStack(spacing: 6) {
                                Image(systemName: "phone.fill").font(.system(size: 8)).foregroundStyle(.green)
                                Text(title).foregroundStyle(.white)
                            }
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(height: NotchViewModel.sneakPeekHeight, alignment: .top)
                            .transition(.opacity)
                        } else if model.showsSneakPeek, let track = nowPlaying.track {
                            SneakPeekLine(track: track, lyrics: model.settings.lyricsEnabled ? model.lyrics : nil)
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
            .offset(x: shift)
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
        .animation(model.showsSneakPeek ? motion.earsGrow : motion.earsShrink, value: model.showsSneakPeek)
        .animation(model.showsIdleEars ? motion.earsGrow : motion.earsShrink, value: model.showsIdleEars)
        .animation(model.hud.event != nil ? motion.earsGrow : motion.earsShrink, value: model.hud.event)
        // The shape slides over when the left ear hides or shows, rather than jumping.
        .animation(motion.earsGrow, value: model.collapsedShift)
        .animation(.easeInOut(duration: 0.18), value: model.tab)
    }

    private var motion: NotchMotion { NotchMotion(reduceMotion: reduceMotion) }
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
    /// Where ShelfView's AirDrop tile sits inside the expanded shape.
    func airDropRect(in size: CGSize) -> CGRect {
        let inset: CGFloat = 18 + 14
        let top = max(model.geometry.collapsedSize.height, 24) + 8
        return CGRect(x: size.width - inset - ShelfView.airDropWidth, y: top,
                      width: ShelfView.airDropWidth, height: size.height - top - 16)
    }
}

/// Drops land on the shelf, or go straight to AirDrop when released over the AirDrop tile.
private struct NotchDropDelegate: DropDelegate {
    let model: NotchViewModel
    @Binding var isTargeted: Bool
    @Binding var isAirDropTargeted: Bool
    let airDropRect: CGRect

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }

    func dropEntered(info: DropInfo) {
        isTargeted = true
        model.tab = .shelf
        model.expand()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        isAirDropTargeted = model.isExpanded && model.tab == .shelf && airDropRect.contains(info.location)
        return DropProposal(operation: .copy)
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
