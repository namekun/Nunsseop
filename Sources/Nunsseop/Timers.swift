import AppKit
import SwiftUI

/// Countdown, Pomodoro and stopwatch. Only one runs at a time.
@MainActor
final class TimerModel: ObservableObject {
    enum Mode: String, CaseIterable { case countdown, pomodoro, stopwatch }
    enum Phase { case work, rest }

    @Published var mode: Mode = .countdown { didSet { if mode != oldValue { reset() } } }
    @Published var countdownSeconds: Int {
        didSet { defaults.set(countdownSeconds, forKey: "countdownSeconds") }
    }
    @Published var workMinutes: Int {
        didSet { defaults.set(workMinutes, forKey: "pomodoroWorkMinutes") }
    }
    @Published var restMinutes: Int {
        didSet { defaults.set(restMinutes, forKey: "pomodoroRestMinutes") }
    }
    @Published private(set) var phase: Phase = .work
    @Published private(set) var completedPomodoros = 0
    /// Countdown and Pomodoro: when the current run ends. Stopwatch: when it was (re)started.
    @Published private(set) var anchor: Date?
    /// Time left (countdown) or elapsed (stopwatch) while paused.
    @Published private(set) var pausedValue: TimeInterval?

    private static func stored(_ key: String, _ fallback: Int, in defaults: UserDefaults) -> Int {
        let value = defaults.integer(forKey: key)
        return value > 0 ? value : fallback
    }

    private let defaults: UserDefaults
    private let now: () -> Date
    private let chime: () -> Void

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = { .now },
         chime: @escaping () -> Void = { NSSound(named: "Glass")?.play() }) {
        self.defaults = defaults
        self.now = now
        self.chime = chime
        countdownSeconds = Self.stored("countdownSeconds", 5 * 60, in: defaults)
        workMinutes = Self.stored("pomodoroWorkMinutes", 25, in: defaults)
        restMinutes = Self.stored("pomodoroRestMinutes", 5, in: defaults)
    }

    var onFinished: ((String) -> Void)?
    private var ticker: Timer?

    var isRunning: Bool { anchor != nil }
    var isActive: Bool { anchor != nil || pausedValue != nil }

    /// Seconds left for countdown modes, seconds elapsed for the stopwatch.
    func value(at date: Date? = nil) -> TimeInterval {
        let date = date ?? now()
        switch mode {
        case .stopwatch:
            if let anchor { return (pausedValue ?? 0) + date.timeIntervalSince(anchor) }
            return pausedValue ?? 0
        case .countdown, .pomodoro:
            if let anchor { return max(0, anchor.timeIntervalSince(date)) }
            return pausedValue ?? fullLength
        }
    }

    var fullLength: TimeInterval {
        switch mode {
        case .countdown: return TimeInterval(countdownSeconds)
        case .pomodoro: return TimeInterval((phase == .work ? workMinutes : restMinutes) * 60)
        case .stopwatch: return 0
        }
    }

    func start() {
        guard anchor == nil else { return }
        switch mode {
        case .stopwatch:
            anchor = now()
        case .countdown, .pomodoro:
            anchor = now().addingTimeInterval(pausedValue ?? fullLength)
            pausedValue = nil
        }
        startTicking()
    }

    func pause() {
        guard anchor != nil else { return }
        pausedValue = value()
        anchor = nil
        ticker?.invalidate()
    }

    func reset() {
        anchor = nil
        pausedValue = nil
        phase = .work
        ticker?.invalidate()
    }

    /// The length can be changed only while nothing is running or paused.
    var canEditLength: Bool { mode != .stopwatch && !isActive }

    /// Picks which Pomodoro phase to edit and start from.
    func selectPhase(_ phase: Phase) {
        guard mode == .pomodoro, !isActive else { return }
        self.phase = phase
    }

    func adjustLength(byMinutes delta: Int) {
        guard canEditLength else { return }
        switch mode {
        case .countdown:
            // Steps snap to whole minutes, so 1:30 goes to 2:00 or 1:00.
            let minutes = (delta > 0 ? countdownSeconds / 60 : (countdownSeconds + 59) / 60) + delta
            countdownSeconds = min(Self.maxCountdown, max(60, minutes * 60))
        case .pomodoro:
            if phase == .work { workMinutes = min(180, max(1, workMinutes + delta)) }
            else { restMinutes = min(60, max(1, restMinutes + delta)) }
        case .stopwatch:
            break
        }
    }

    /// Sets the length from typed text: "90" is 90 minutes, "1:30" is 1 min 30 s, "1:00:00" is an hour.
    /// Pomodoro lengths are rounded to whole minutes. Returns false if the text isn't a length.
    @discardableResult
    func setLength(from text: String) -> Bool {
        guard canEditLength, let seconds = Self.parseLength(text), seconds > 0 else { return false }
        switch mode {
        case .countdown:
            countdownSeconds = min(Self.maxCountdown, seconds)
        case .pomodoro:
            let minutes = max(1, Int((Double(seconds) / 60).rounded()))
            if phase == .work { workMinutes = min(180, minutes) } else { restMinutes = min(60, minutes) }
        case .stopwatch:
            return false
        }
        return true
    }

    static let maxCountdown = 24 * 3600

    nonisolated static func parseLength(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        // Six digits per part is far beyond any real length and keeps the arithmetic from overflowing.
        guard (1...3).contains(parts.count), parts.allSatisfy({ $0.count <= 6 }) else { return nil }
        let numbers = parts.map { Int($0) }
        guard numbers.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        let n = numbers.map { $0! }
        switch n.count {
        case 1: return n[0] * 60
        case 2: return n[1] < 60 ? n[0] * 60 + n[1] : nil
        default: return n[1] < 60 && n[2] < 60 ? n[0] * 3600 + n[1] * 60 + n[2] : nil
        }
    }

    private func startTicking() {
        ticker?.invalidate()
        guard mode != .stopwatch else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        ticker?.tolerance = 0.05
    }

    func tick() {
        guard let anchor, anchor <= now() else { return }
        chime()
        switch mode {
        case .countdown:
            reset()
            onFinished?(String(localized: "Timer finished"))
        case .pomodoro:
            if phase == .work { completedPomodoros += 1 }
            let finishedWork = phase == .work
            phase = finishedWork ? .rest : .work
            self.anchor = now().addingTimeInterval(fullLength)
            onFinished?(finishedWork ? String(localized: "Time for a break") : String(localized: "Back to work"))
        case .stopwatch:
            break
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.down))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// A length with units, so it can't be read as a time of day: "25 min", "1 hr 30 min", "1분 30초".
    /// Each unit is formatted on its own and joined with a space, which avoids the list commas and
    /// "and" some languages put between units. Units follow the app's language, like the words around them,
    /// rather than the system's.
    nonisolated static func lengthLabel(_ seconds: Int,
                                        locale: Locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .short
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        let parts: [(Int, NSCalendar.Unit)] = [(seconds / 3600, .hour), (seconds / 60 % 60, .minute), (seconds % 60, .second)]
        let shown = parts.filter { $0.0 > 0 }
        return (shown.isEmpty ? [(0, .minute)] : shown).compactMap { value, unit in
            formatter.allowedUnits = unit
            return formatter.string(from: TimeInterval(value) * (unit == .hour ? 3600 : unit == .minute ? 60 : 1))
        }.joined(separator: " ")
    }
}

struct TimerTab: View {
    @ObservedObject var timer: TimerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pickerWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            // The ring takes the height it's given, within reason, so it grows with taller notches, but no more than the
            // width the picker (its width depends on the language), spacers, side column and buttons leave.
            let diameter = min(150, max(92, geometry.size.height - 4), geometry.size.width - pickerWidth - 2 * 12 - 18 - 104 - 44)
            HStack(spacing: 0) {
                ModePicker(mode: $timer.mode, animated: !reduceMotion)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pickerWidth = $0 }
                Spacer(minLength: 12)
                HStack(spacing: 18) {
                    TimerRing(timer: timer, diameter: diameter, tint: tint, animated: !reduceMotion)
                    sideColumn
                        .frame(width: 104)
                }
                Spacer(minLength: 12)
                VStack(spacing: 10) {
                    RoundButton(symbol: timer.isRunning ? "pause.fill" : "play.fill", prominent: true) {
                        timer.isRunning ? timer.pause() : timer.start()
                    }
                    RoundButton(symbol: "arrow.counterclockwise", prominent: false) { timer.reset() }
                        .disabled(!timer.isActive)
                        .opacity(timer.isActive ? 1 : 0.4)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tint: Color { timer.mode == .pomodoro && timer.phase == .rest ? .green : .orange }

    @ViewBuilder
    private var sideColumn: some View {
        switch timer.mode {
        case .countdown:
            // Fewer presets when the notch is too short for all of them.
            ViewThatFits(in: .vertical) {
                presets([5, 10, 15, 25, 45])
                presets([5, 10, 25, 45])
            }
            .disabled(timer.isRunning)
        case .pomodoro:
            VStack(spacing: 5) {
                Group {
                    Chip(title: String(localized: "Focus \(TimerModel.lengthLabel(timer.workMinutes * 60))"), tint: .orange,
                         selected: timer.phase == .work) { timer.selectPhase(.work) }
                    Chip(title: String(localized: "Break \(TimerModel.lengthLabel(timer.restMinutes * 60))"), tint: .green,
                         selected: timer.phase == .rest) { timer.selectPhase(.rest) }
                }
                .disabled(timer.isActive)
                Text("Completed today: \(timer.completedPomodoros)")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.top, 4)
            }
        case .stopwatch:
            Text("Counts up until you stop it")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func presets(_ list: [Int]) -> some View {
        VStack(spacing: 5) {
            ForEach(list, id: \.self) { minutes in
                Chip(title: TimerModel.lengthLabel(minutes * 60), tint: .orange,
                     selected: timer.countdownSeconds == minutes * 60) {
                    timer.reset()
                    timer.countdownSeconds = minutes * 60
                }
            }
        }
    }
}

/// Timer, Pomodoro or stopwatch, as a column of capsules styled like the notch's tab buttons.
private struct ModePicker: View {
    @Binding var mode: TimerModel.Mode
    let animated: Bool
    @Namespace private var selection

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            item(.countdown, "timer", String(localized: "Timer"))
            item(.pomodoro, "target", String(localized: "Pomodoro"))
            item(.stopwatch, "stopwatch", String(localized: "Stopwatch"))
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(.white.opacity(0.06)))
    }

    private func item(_ value: TimerModel.Mode, _ symbol: String, _ title: String) -> some View {
        let selected = mode == value
        return Button {
            withAnimation(animated ? .snappy(duration: 0.25) : nil) { mode = value }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? .white : .white.opacity(0.45))
            .padding(.leading, 9).padding(.trailing, 12)
            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
            .background {
                if selected {
                    Capsule().fill(.white.opacity(0.16))
                        .matchedGeometryEffect(id: "selection", in: selection)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct RoundButton: View {
    let symbol: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 16 : 13, weight: .semibold))
                .frame(width: prominent ? 44 : 34, height: prominent ? 44 : 34)
                .background(Circle().fill(.white.opacity(prominent ? 0.2 : 0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// A preset length or Pomodoro phase; the selected one takes the tint.
private struct Chip: View {
    let title: String
    let tint: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.75)
                .foregroundStyle(selected ? tint : .white.opacity(0.65))
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 22)
                .background(Capsule().fill(selected ? tint.opacity(0.18) : .white.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The ring and the time inside it. Stopped, it shows the length with units and is the control: scroll over it
/// or use the arrows to change it a minute at a time (five with Shift), or click it to type a length.
/// Running, it shows what's left (or elapsed) and the ring empties; the stopwatch's ring sweeps once a minute.
private struct TimerRing: View {
    @ObservedObject var timer: TimerModel
    let diameter: CGFloat
    let tint: Color
    let animated: Bool
    @State private var editing = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let editable = timer.canEditLength
        let lineWidth = max(6, diameter * 0.06)
        // Redraws only while running; the arc moves less than a point per step, so it needs no animation.
        TimelineView(.animation(minimumInterval: 0.25, paused: !timer.isRunning)) { context in
            let value = timer.value(at: context.date)
            ZStack {
                Circle().stroke(.white.opacity(0.1), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: progress(value))
                    .stroke(tint.opacity(timer.isActive && !timer.isRunning ? 0.5 : 1),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    // Only state changes animate (a new length, start, reset, the next phase), not the ticking.
                    .animation(animated ? .easeOut(duration: 0.35) : nil, value: AnimationKey(timer: timer))
                if timer.isActive || timer.mode == .stopwatch {
                    running(value)
                } else {
                    stopped(editable: editable)
                }
            }
            .padding(lineWidth / 2)
        }
        .frame(width: diameter, height: diameter)
        .onChange(of: editable) { _, isEditable in if !isEditable { editing = false } }
    }

    private struct AnimationKey: Equatable {
        let active: Bool, mode: TimerModel.Mode, phase: TimerModel.Phase, length: TimeInterval
        @MainActor init(timer: TimerModel) {
            active = timer.isActive; mode = timer.mode; phase = timer.phase; length = timer.fullLength
        }
    }

    private func progress(_ value: TimeInterval) -> CGFloat {
        switch timer.mode {
        case .stopwatch: return CGFloat(value.truncatingRemainder(dividingBy: 60) / 60)
        case .countdown, .pomodoro: return timer.fullLength > 0 ? CGFloat(min(1, value / timer.fullLength)) : 0
        }
    }

    private func running(_ value: TimeInterval) -> some View {
        VStack(spacing: 1) {
            Text(TimerModel.format(value))
                .font(.system(size: diameter * 0.24, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(caption)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(timer.isActive && !timer.isRunning ? tint : .white.opacity(0.5))
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(width: diameter * 0.72)
    }

    private var caption: String {
        if timer.isActive && !timer.isRunning { return String(localized: "Paused") }
        return timer.mode == .stopwatch ? String(localized: "elapsed") : String(localized: "left")
    }

    private func stopped(editable: Bool) -> some View {
        VStack(spacing: 2) {
            arrow("chevron.up", delta: 1)
            ZStack {
                lengthText(TimerModel.lengthLabel(Int(timer.fullLength)))
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .opacity(editing ? 0 : 1)
                if editing {
                    TextField("", text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: diameter * 0.2, weight: .semibold, design: .rounded).monospacedDigit())
                        .multilineTextAlignment(.center)
                        .focused($focused)
                        .onSubmit(commit)
                        .onExitCommand { editing = false }
                        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                }
            }
            .frame(width: diameter * 0.74)
            .overlay {
                if editable && !editing {
                    ScrollCatcher(onStep: { timer.adjustLength(byMinutes: $0) }, onClick: startEditing)
                }
            }
            .help(editable ? String(localized: "Scroll or click the time to change it") : "")
            arrow("chevron.down", delta: -1)
        }
    }

    /// Numbers large, units small: "25" big with "min" beside it. Lengths with more units get smaller numbers.
    private func lengthText(_ label: String) -> Text {
        let units = label.split(whereSeparator: { !$0.isNumber }).count
        let digitSize = diameter * (units >= 3 ? 0.15 : units == 2 ? 0.19 : 0.26)
        var result = Text("")
        var run = ""
        var runIsDigits = true
        func flush() {
            guard !run.isEmpty else { return }
            result = result + Text(run).font(runIsDigits
                ? .system(size: digitSize, weight: .semibold, design: .rounded).monospacedDigit()
                : .system(size: digitSize * 0.46, weight: .semibold, design: .rounded))
                .foregroundColor(runIsDigits ? .white : .white.opacity(0.6))
            run = ""
        }
        for character in label {
            let isDigit = character.isNumber
            if isDigit != runIsDigits { flush(); runIsDigits = isDigit }
            run.append(character)
        }
        flush()
        return result
    }

    private func startEditing() {
        // Whole minutes are typed as a plain number, the same way they are read back.
        let seconds = Int(timer.fullLength)
        text = seconds % 60 == 0 ? "\(seconds / 60)" : TimerModel.format(timer.fullLength)
        editing = true
        focused = true
    }

    private func arrow(_ symbol: String, delta: Int) -> some View {
        Button {
            timer.adjustLength(byMinutes: NSEvent.modifierFlags.contains(.shift) ? delta * 5 : delta)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 40, height: 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!timer.canEditLength)
        .opacity(editing ? 0 : 1)
    }

    private func commit() {
        guard editing else { return }
        timer.setLength(from: text)
        editing = false
    }
}

/// Set while the pointer is over the timer's time, so notch swipes leave that scrolling alone.
@MainActor
enum TimeScrollTarget {
    static var isHovered = false
}

/// Turns scroll-wheel and trackpad scrolling over a view into whole steps: up is +1, down is -1, Shift makes it 5.
private struct ScrollCatcher: NSViewRepresentable {
    let onStep: (Int) -> Void
    let onClick: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onStep = onStep
        view.onClick = onClick
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onStep = onStep
        view.onClick = onClick
    }

    static func dismantleNSView(_ view: CatcherView, coordinator: ()) {
        TimeScrollTarget.isHovered = false
    }

    final class CatcherView: NSView {
        var onStep: ((Int) -> Void)?
        var onClick: (() -> Void)?
        private var accumulated: CGFloat = 0

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self))
        }

        override func mouseEntered(with event: NSEvent) { TimeScrollTarget.isHovered = true }
        override func mouseExited(with event: NSEvent) { TimeScrollTarget.isHovered = false }
        override func mouseDown(with event: NSEvent) { onClick?() }

        override func scrollWheel(with event: NSEvent) {
            guard event.momentumPhase.isEmpty else { return }
            // Shift turns a mouse wheel into horizontal scrolling, so take whichever axis moved.
            var delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.scrollingDeltaX
            // Positive means the wheel or fingers moved up, whatever the natural scrolling setting.
            if event.isDirectionInvertedFromDevice { delta = -delta }
            // Trackpads report many small precise deltas; a mouse wheel reports whole lines.
            accumulated += event.hasPreciseScrollingDeltas ? delta / 12 : delta
            let steps = Int(accumulated)
            guard steps != 0 else { return }
            accumulated -= CGFloat(steps)
            onStep?(event.modifierFlags.contains(.shift) ? steps * 5 : steps)
        }
    }
}
