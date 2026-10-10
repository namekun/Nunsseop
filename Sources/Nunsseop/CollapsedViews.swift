import SwiftUI

struct IdleValue {
    let symbol: String?
    /// nil draws the symbol in its own colours.
    let tint: Color?
    let text: String
}

extension NotchViewModel {
    /// The value an idle ear shows, or nil when there is nothing to show for it yet.
    func idleValue(_ item: IdleItem, at date: Date = .now) -> IdleValue? {
        switch item {
        case .none:
            return nil
        case .claude, .codex:
            guard let left = Self.aiLeft(item, in: aiUsage.providers, window: settings.idleAIWindow) else { return nil }
            return IdleValue(symbol: item == .claude ? "sparkles" : "terminal",
                             tint: left < 15 ? .red : (item == .claude ? .orange : .white), text: "\(left)%")
        case .battery:
            guard let power = hud.power else { return nil }
            return IdleValue(symbol: power.isCharging ? "battery.100percent.bolt" : BatteryBadge.symbol(for: power.percent),
                             tint: power.percent <= 20 && !power.onAC ? .red : .white, text: "\(power.percent)%")
        case .weather:
            guard let weather = weather.current else { return nil }
            return IdleValue(symbol: WeatherModel.symbol(for: weather.code), tint: nil,
                             text: "\(Int(weather.temperature.rounded()))°")
        case .date:
            return IdleValue(symbol: nil, tint: nil, text: date.formatted(.dateTime.day().weekday(.abbreviated)))
        case .agents:
            return Self.agentsValue(agents.counts)
        }
    }

    /// Agents waiting for you come first, in yellow; otherwise how many are working. Nothing when none are.
    nonisolated static func agentsValue(_ counts: AgentBoard.Counts) -> IdleValue? {
        if counts.waiting > 0 { return IdleValue(symbol: "hand.raised.fill", tint: .yellow, text: "\(counts.waiting)") }
        if counts.working > 0 { return IdleValue(symbol: "bolt.fill", tint: .green, text: "\(counts.working)") }
        return nil
    }

    /// Percent left of an AI tool's limits, or nil while none is known.
    /// A window that already reset has no known usage since, so it counts as unknown. When the chosen window is
    /// unknown the ear shows nothing rather than quietly switching to the other limit.
    nonisolated static func aiLeft(_ item: IdleItem, in providers: [AIUsageModel.Provider], window: AIWindow = .tighter) -> Int? {
        guard let provider = providers.first(where: { $0.id == item.rawValue }) else { return nil }
        let windows: [AIUsageModel.Window?] = switch window {
        case .tighter: [provider.session, provider.weekly]
        case .session: [provider.session]
        case .weekly: [provider.weekly]
        }
        guard let used = windows.compactMap({ $0 }).filter({ $0.resetsAt != nil }).map(\.percent).max() else { return nil }
        return max(0, 100 - Int(used.rounded()))
    }

    var showsIdleEars: Bool {
        !showsLiveActivity && (idleValue(settings.idleLeft) != nil || idleValue(settings.idleRight) != nil)
    }
}

struct IdleEars: View {
    @ObservedObject var model: NotchViewModel
    /// Watched here because the notch itself only hears when a limit becomes known or unknown.
    @ObservedObject var aiUsage: AIUsageModel
    let height: CGFloat

    init(model: NotchViewModel, height: CGFloat) {
        self.model = model
        self.aiUsage = model.aiUsage
        self.height = height
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack {
                ear(model.idleValue(model.settings.idleLeft, at: context.date))
                Spacer()
                ear(model.idleValue(model.settings.idleRight, at: context.date))
            }
            // Text is shorter than the artwork, so it keeps the same distance from the side wall as from the top and bottom.
            .padding(.horizontal, 7)
        }
        .font(.system(size: 11, weight: .semibold).monospacedDigit())
        .foregroundStyle(.white)
        .frame(height: height)
    }

    @ViewBuilder
    private func ear(_ value: IdleValue?) -> some View {
        if let value {
            HStack(spacing: 3) {
                if let symbol = value.symbol {
                    if let tint = value.tint {
                        Image(systemName: symbol).foregroundStyle(tint)
                    } else {
                        Image(systemName: symbol).symbolRenderingMode(.multicolor)
                    }
                }
                Text(value.text)
            }
            .lineLimit(1)
            .fixedSize()
        }
    }
}

struct CollapsedActivity: View {
    @ObservedObject var nowPlaying: NowPlayingController
    @ObservedObject var timer: TimerModel
    @ObservedObject var recorder: ScreenRecorder
    @ObservedObject var downloads: DownloadWatcher
    let privacy: PrivacyMonitor?
    let call: CallMonitor.Call?
    /// Known to be muted; unknown states show nothing.
    var callMuted = false
    let height: CGFloat
    let earWidth: CGFloat
    let showsMusic: Bool
    let showsTimer: Bool
    let showsDownloads: Bool

    var body: some View {
        let art = min(height - 14, 32)
        let playing = showsMusic && nowPlaying.track?.isPlaying == true
        // A download takes the timer's place, after it: a timer someone set outranks a download.
        let download = showsDownloads && !(showsTimer && timer.isRunning) ? downloads.status : nil
        HStack {
            // A call outranks music and timers; a screen recording keeps its time on the right.
            if let call {
                Image(nsImage: call.icon)
                    .resizable()
                    .frame(width: art, height: art)
            } else if playing {
                ArtworkView(image: nowPlaying.artwork, cornerRadius: art > 16 ? 5 : 3, style: .circular)
                    .frame(width: art, height: art)
            } else if recorder.isRecording {
                Circle().fill(.red).frame(width: 8, height: 8)
            } else if let privacy, privacy.cameraInUse || privacy.micInUse {
                HStack(spacing: 3) {
                    if privacy.cameraInUse { Image(systemName: "video.fill").foregroundStyle(.green) }
                    if privacy.micInUse { Image(systemName: "mic.fill").foregroundStyle(.orange) }
                }
                .font(.system(size: 10, weight: .semibold))
            } else if download != nil {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.blue)
            } else {
                Image(systemName: timer.mode == .stopwatch ? "stopwatch.fill" : "timer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(timer.mode == .pomodoro && timer.phase == .rest ? .green : .orange)
            }
            Spacer()
            if let started = recorder.startedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(TimerModel.format(context.date.timeIntervalSince(started)))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.red)
                }
            } else if let call {
                HStack(spacing: 3) {
                    if callMuted {
                        Image(systemName: "mic.slash.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(TimerModel.format(context.date.timeIntervalSince(call.startedAt)))
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.green)
                    }
                }
            } else if let privacy, (privacy.cameraInUse || privacy.micInUse), !(showsTimer && timer.isRunning), playing {
                HStack(spacing: 3) {
                    if privacy.cameraInUse { Circle().fill(.green).frame(width: 6, height: 6) }
                    if privacy.micInUse { Circle().fill(.orange).frame(width: 6, height: 6) }
                }
            } else if showsTimer && timer.isRunning {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(TimerModel.format(timer.value(at: context.date)))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.orange)
                }
            } else if let download {
                Group {
                    if let percent = download.percent {
                        Text("\(percent)%")
                    } else {
                        // Until the browser knows the size.
                        Image(systemName: "ellipsis")
                    }
                }
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.blue)
            } else {
                SpectrumBars(isPlaying: playing, tint: nowPlaying.tint)
                    .frame(width: art - 2, height: max(8, art - 6))
            }
        }
        .frame(height: height)
    }
}

struct SneakPeekLine: View {
    let track: NowPlayingTrack
    let lyrics: LyricsModel?

    var body: some View {
        // Only the lyrics follow the clock, and they move only while playing.
        TimelineView(.animation(minimumInterval: 0.5, paused: !track.isPlaying)) { context in
            HStack(spacing: 6) {
                Image(systemName: track.isPlaying ? "play.fill" : "pause.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.6))
                if track.isPlaying, let line = lyrics?.line(at: track.position(at: context.date)) {
                    Text(line).foregroundStyle(.white)
                        .id(line)
                        .transition(.opacity)
                } else {
                    Text(track.title).foregroundStyle(.white)
                    if !track.artist.isEmpty {
                        Text(track.artist).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: lyrics?.line(at: track.position(at: context.date)))
        }
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)
        // A line longer than its room gives up a little size before it truncates.
        .minimumScaleFactor(0.9)
        .padding(.horizontal, 10)
    }
}

// MARK: - Shared pieces

struct ArtworkView: View {
    let image: NSImage?
    let cornerRadius: CGFloat
    /// Circular where the artwork sits inside the notch's corner, so the two curves run parallel.
    var style: RoundedCornerStyle = .continuous

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: style)
            .fill(.white.opacity(0.12))
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note").foregroundStyle(.white.opacity(0.5))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: style))
    }
}

/// Four bars bouncing between 30% and full height while playing, flat at 25% while paused.
/// Core Animation repeats the bounce in the render server, so playing music costs the app no redraws.
/// With Reduce Motion on, the bars stand still at uneven heights while playing.
struct SpectrumBars: NSViewRepresentable {
    let isPlaying: Bool
    let tint: Color

    func makeNSView(context: Context) -> BarsView { BarsView() }

    func updateNSView(_ view: BarsView, context: Context) {
        view.update(isPlaying: isPlaying, reduceMotion: context.environment.accessibilityReduceMotion,
                    color: NSColor(tint).cgColor)
    }

    final class BarsView: NSView {
        /// Seconds each bar takes to rise or fall, and where in that it starts, so the bars move out of step.
        private static let durations: [CFTimeInterval] = [0.36, 0.25, 0.19, 0.16]
        private static let starts: [Double] = [0.4, 1, 0.1, 0.7]
        private let bars = (0..<4).map { _ in CALayer() }
        private var isPlaying = false
        private var reduceMotion = false

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            bars.forEach { layer?.addSublayer($0) }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        /// Clicks go to the SwiftUI views around the bars.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            layoutBars()
        }

        override func layout() {
            super.layout()
            layoutBars()
        }

        /// Animations can be dropped while the view is out of a window, so they are added again.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { applyState() }
        }

        private func layoutBars() {
            let spacing: CGFloat = 2
            let width = max(0, (bounds.width - spacing * 3) / 4)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (i, bar) in bars.enumerated() {
                bar.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height)
                bar.position = CGPoint(x: (width + spacing) * CGFloat(i) + width / 2, y: bounds.midY)
                bar.cornerRadius = min(width, bounds.height) / 2
            }
            CATransaction.commit()
        }

        func update(isPlaying: Bool, reduceMotion: Bool, color: CGColor) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            bars.forEach { $0.backgroundColor = color }
            CATransaction.commit()
            let animating = isPlaying && !reduceMotion
            guard isPlaying != self.isPlaying || reduceMotion != self.reduceMotion
                    || animating != (bars[0].animation(forKey: "bounce") != nil) else { return }
            self.isPlaying = isPlaying
            self.reduceMotion = reduceMotion
            applyState()
        }

        private func applyState() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (i, bar) in bars.enumerated() {
                bar.removeAllAnimations()
                // While playing this resting height shows with Reduce Motion and in snapshots; otherwise the bounce covers it.
                let start = Self.starts[i]
                bar.transform = CATransform3DMakeScale(1, isPlaying ? 0.3 + 0.7 * start : 0.25, 1)
                guard isPlaying && !reduceMotion else { continue }
                let bounce = CABasicAnimation(keyPath: "transform.scale.y")
                bounce.fromValue = 0.3
                bounce.toValue = 1
                bounce.duration = Self.durations[i]
                bounce.timeOffset = start * Self.durations[i]
                bounce.autoreverses = true
                bounce.repeatCount = .infinity
                bounce.isRemovedOnCompletion = false
                bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                bar.add(bounce, forKey: "bounce")
            }
            CATransaction.commit()
        }
    }
}

/// The app's eyebrow, shown in place of the camera housing on displays without a notch.
/// It lifts and arches while the pointer is over it, like a raised brow.
struct EyebrowMark: View {
    /// -1 lowered like a closing eye, 0 at rest, 1 raised.
    let lift: CGFloat

    var body: some View {
        EyebrowArch(lift: lift)
            .fill(Color(red: 0.957, green: 0.957, blue: 0.945))
            .frame(width: 24, height: 10)
            .accessibilityHidden(true)
    }
}

/// One brush stroke: a thick head on the left tapering to a thin tail, drawn on a 100 × 40 grid.
/// Raising it lifts the whole stroke and arches it higher, with the tail rising the most; lowering it drops and
/// flattens it, the way a brow settles as the eye closes.
struct EyebrowArch: Shape {
    /// -1 lowered, 0 at rest, 1 fully raised.
    var lift: CGFloat

    var animatableData: CGFloat {
        get { lift }
        set { lift = newValue }
    }

    // A move and five cubic curves, as (x, y) pairs; both poses share the same structure so they blend point by point.
    private static let rest: [CGFloat] = [4, 30, 18, 16, 44, 9, 68, 11, 81, 12, 91, 16, 97, 21,
                                          89, 19, 79, 18, 68, 19, 47, 20, 27, 26, 11, 35, 7, 37, 2, 34, 4, 30]
    private static let raised: [CGFloat] = [4, 26, 16, 9, 42, 1, 67, 4, 80, 5, 90, 10, 97, 16,
                                            89, 13, 79, 12, 68, 13, 47, 14, 27, 20, 11, 31, 7, 33, 2, 30, 4, 26]

    /// The rest pose pulled down and flattened toward a line near its lower edge.
    private static let lowered: [CGFloat] = rest.enumerated().map { $0.offset.isMultiple(of: 2) ? $0.element : 33 + ($0.element - 30) * 0.4 }

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / 100, rect.height / 40)
        let origin = CGPoint(x: rect.midX - 50 * scale, y: rect.midY - 20 * scale)
        let target = lift < 0 ? Self.lowered : Self.raised
        let amount = abs(lift)
        let point = { (i: Int) -> CGPoint in
            let x = Self.rest[2 * i] + (target[2 * i] - Self.rest[2 * i]) * amount
            let y = Self.rest[2 * i + 1] + (target[2 * i + 1] - Self.rest[2 * i + 1]) * amount
            return CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
        }
        var p = Path()
        p.move(to: point(0))
        for curve in 0..<5 {
            let i = 1 + curve * 3
            p.addCurve(to: point(i + 2), control1: point(i), control2: point(i + 1))
        }
        p.closeSubpath()
        return p
    }
}
