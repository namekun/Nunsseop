import SwiftUI

/// Home: what is playing on the left, the week, the day's events and the weather on the right, a hairline between.
struct HomePanels: View {
    let nowPlaying: NowPlayingController
    let lyrics: LyricsModel?
    let calendar: CalendarModel?
    let showsReminders: Bool
    let weather: WeatherModel?
    var worldClock: WorldClockModel?

    /// The right column's width, and the days of the week it has room for.
    nonisolated static func column(for width: CGFloat) -> (width: CGFloat, days: Int) {
        width >= 520 ? (280, 7) : (214, 5)
    }

    var body: some View {
        GeometryReader { proxy in
            let column = Self.column(for: proxy.size.width)
            HStack(spacing: 0) {
                HomeTab(nowPlaying: nowPlaying, lyrics: lyrics)
                    .padding(.trailing, calendar == nil && weather == nil && worldClock == nil ? 0 : 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if calendar != nil || weather != nil || worldClock != nil {
                    PanelVLine().padding(.vertical, 2)
                    VStack(spacing: 0) {
                        if let calendar {
                            CalendarPanel(calendar: calendar, showsReminders: showsReminders, days: column.days)
                        } else {
                            Spacer(minLength: 0)
                        }
                        if let weather { WeatherRow(weather: weather) }
                        if let worldClock { WorldClockRow(worldClock: worldClock) }
                    }
                    .padding(.leading, 14)
                    .frame(width: column.width, alignment: .topLeading)
                }
            }
        }
    }
}

/// The place, its low and high, and the temperature now; nothing until the weather is known.
struct WeatherRow: View {
    @ObservedObject var weather: WeatherModel

    var body: some View {
        if let current = weather.current {
            VStack(spacing: 0) {
                PanelHLine()
                HStack(spacing: 8) {
                    Image(systemName: WeatherModel.symbol(for: current.code)).symbolRenderingMode(.monochrome)
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.8)).frame(width: 16).accessibilityHidden(true)
                    Text.panel(current.place, size: 12, weight: .semibold).lineLimit(1)
                    Text.panel("\(Int(current.low.rounded()))° / \(Int(current.high.rounded()))°", size: 11, opacity: 0.6, mono: true).lineLimit(1).fixedSize()
                    Spacer(minLength: 4)
                    Text.panel("\(Int(current.temperature.rounded()))°", size: 15, weight: .semibold, mono: true).fixedSize()
                }
                .padding(.horizontal, 8).frame(height: 26)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct HomeTab: View {
    @ObservedObject var nowPlaying: NowPlayingController
    let lyrics: LyricsModel?

    private var emptyMessage: String {
        if let browser = nowPlaying.browserNeedingJavaScript {
            return BrowserMedia.enableHint(for: browser)
        }
        if nowPlaying.needsAutomationPermission {
            return String(localized: "Allow Nunsseop in System Settings › Privacy & Security › Automation")
        }
        return String(localized: "Play something in any app or browser and it shows up here")
    }

    /// Podcasts, videos and long mixes, where skipping and speed matter.
    private func isLong(_ track: NowPlayingTrack) -> Bool { track.duration > 600 }

    static func rateLabel(_ rate: Double) -> String {
        rate.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }

    @ViewBuilder
    private func transportButtons(_ track: NowPlayingTrack) -> some View {
        ControlButton(symbol: "backward.fill", label: String(localized: "Previous")) { nowPlaying.send(.previous) }
        ControlButton(symbol: track.isPlaying ? "pause.fill" : "play.fill",
                      label: track.isPlaying ? String(localized: "Pause") : String(localized: "Play"), prominent: true) {
            nowPlaying.send(.playPause)
        }
        ControlButton(symbol: "forward.fill", label: String(localized: "Next")) { nowPlaying.send(.next) }
    }

    var body: some View {
        if let track = nowPlaying.track {
            HStack(spacing: 12) {
                // Gives way to the controls when the notch is narrow.
                Artwork(image: nowPlaying.artwork, sourceBundleID: track.sourceBundleID)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(minWidth: 80, maxWidth: 96, maxHeight: 96)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 6) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: track.title)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            if track.isPlaying, let lyrics, !lyrics.lines.isEmpty {
                                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                                    Text(verbatim: lyrics.line(at: track.position(at: context.date)) ?? (track.artist.isEmpty ? track.album : track.artist))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.85))
                                        .lineLimit(1)
                                }
                            } else {
                                Text(verbatim: track.artist.isEmpty ? track.album : track.artist)
                                    .font(.system(size: 12))
                                    .foregroundStyle(PanelInk.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        if track.canChangeRate && (isLong(track) || track.rate != 1) {
                            Button { nowPlaying.cycleRate() } label: {
                                Text(Self.rateLabel(track.rate))
                                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                    .padding(.horizontal, 6).frame(height: 18)
                                    .background(Capsule().fill(.white.opacity(track.rate == 1 ? 0.1 : 0.22)))
                                    .frame(height: 24)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(Text("Playback speed"))
                        }
                        SpectrumBars(isPlaying: track.isPlaying, tint: .white.opacity(0.75))
                            .frame(width: 18, height: 14)
                            .padding(.top, 2)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 4)
                    ProgressRow(track: track) { nowPlaying.send(.seek($0)) }
                    // Skip buttons only for long tracks, and only where they fit beside the calendar.
                    ViewThatFits(in: .horizontal) {
                        if track.canSeek && isLong(track) {
                            HStack(spacing: 10) {
                                ControlButton(symbol: "gobackward.15", label: String(localized: "Back 15 seconds"), size: 13) { nowPlaying.skip(by: -15) }
                                transportButtons(track)
                                ControlButton(symbol: "goforward.15", label: String(localized: "Forward 15 seconds"), size: 13) { nowPlaying.skip(by: 15) }
                            }
                        }
                        HStack(spacing: 14) { transportButtons(track) }
                        HStack(spacing: 6) { transportButtons(track) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                }
                .frame(height: 96)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08))
                    Image(systemName: "music.note").font(.system(size: 28)).foregroundStyle(.white.opacity(0.5)).accessibilityHidden(true)
                }
                .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nothing playing").font(.system(size: 13, weight: .semibold))
                    Text(emptyMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(PanelInk.secondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                    if nowPlaying.browserNeedingJavaScript == BrowserMedia.diaBundleID {
                        PanelAction(title: "Relaunch Dia with JavaScript allowed",
                                    hint: String(localized: "Quits Dia and opens it again with \(BrowserMedia.diaJavaScriptFlag). Dia restores its tabs.")) {
                            BrowserMedia.relaunchDiaWithJavaScript()
                        }
                    }
                }
                .frame(maxWidth: 200, alignment: .leading)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

/// The call in progress with its microphone and camera toggles, above the Home tab.
struct CallRow: View {
    let call: CallMonitor.Call
    let state: CallControls.State
    let toggle: (CallControls.Control) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: call.icon).resizable().frame(width: 20, height: 20)
            Text(call.appName).font(.system(size: 12, weight: .semibold)).lineLimit(1).layoutPriority(1)
            if let title = call.title {
                Text(title).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(TimerModel.format(context.date.timeIntervalSince(call.startedAt)))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.green)
            }
            .fixedSize()
            Spacer(minLength: 8)
            if let mic = state.mic {
                button(mic, on: "mic.fill", off: "mic.slash.fill", unknown: "mic",
                       help: mic == .on ? "Mute" : mic == .off ? "Unmute" : "Microphone") { toggle(.mic) }
            }
            if let camera = state.camera {
                button(camera, on: "video.fill", off: "video.slash.fill", unknown: "video",
                       help: camera == .on ? "Turn camera off" : camera == .off ? "Turn camera on" : "Camera") { toggle(.camera) }
            }
        }
        .foregroundStyle(.white)
        .padding(.leading, 8).padding(.trailing, 4)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08)))
    }

    private func button(_ value: CallControls.Toggle, on: String, off: String, unknown: String,
                        help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: value == .on ? on : value == .off ? off : unknown)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(value == .off ? .red : .white)
                .frame(width: 30, height: 22)
                .background(Capsule().fill(value == .off ? Color.red.opacity(0.18) : .white.opacity(0.1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(Text(help))
    }
}

/// The cover, flat: no glow. The app it plays in sits on its corner.
private struct Artwork: View {
    let image: NSImage?
    let sourceBundleID: String

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ArtworkView(image: image, cornerRadius: 12)
            if let icon = InstalledApps.icon(for: sourceBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 22, height: 22)
                    .offset(x: 5, y: 5)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct ProgressRow: View {
    let track: NowPlayingTrack
    let onSeek: (Double) -> Void
    @State private var dragFraction: Double?

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: !track.isPlaying)) { context in
            let live = track.duration > 0 ? track.position(at: context.date) / track.duration : 0
            let fraction = min(1, max(0, dragFraction ?? live))
            let position = fraction * track.duration
            VStack(spacing: 0) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        Capsule().fill(.white.opacity(0.9)).frame(width: max(3, proxy.size.width * fraction))
                    }
                    .frame(height: dragFraction == nil ? 3 : 5)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard track.duration > 0 else { return }
                                dragFraction = min(1, max(0, value.location.x / proxy.size.width))
                            }
                            .onEnded { _ in
                                if let dragFraction, track.duration > 0 { onSeek(dragFraction * track.duration) }
                                dragFraction = nil
                            }
                    )
                }
                .frame(height: 12)
                .animation(.easeOut(duration: 0.12), value: dragFraction == nil)
                HStack {
                    Text(Self.format(position))
                    Spacer()
                    Text("-" + Self.format(max(0, track.duration - position)))
                }
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(PanelInk.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Playback position"))
            .accessibilityValue(Text(verbatim: "\(Self.format(position)) / \(Self.format(track.duration))"))
        }
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let s = Int(max(0, seconds).rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct ControlButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 13
    var prominent = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(.white.opacity(prominent || hovering ? 1 : 0.85))
                .frame(width: prominent ? 30 : size + 16, height: 26)
                .background { if prominent || hovering { Capsule().fill(.white.opacity(prominent ? (hovering ? 0.2 : 0.14) : 0.1)) } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}
