import AppKit
import Combine

enum HUDEvent: Equatable {
    case volume(Float, muted: Bool)
    case brightness(Float)
    case keyboard(Float)
    case notice(symbol: String, title: String, detail: String?)
    case power(PowerState)
    case headphones(HeadphoneBattery)
}

/// Collects system events (volume, brightness, power, headphones) and exposes
/// the one the notch should briefly show.
@MainActor
final class HUDCenter: ObservableObject {
    @Published private(set) var event: HUDEvent?
    /// What clicking the notice on screen does, such as going to the terminal it came from.
    private(set) var action: (() -> Void)?
    @Published private(set) var power: PowerState?
    @Published private(set) var interceptorNeedsPermission = false

    private let settings: AppSettings
    private let audio = SystemAudio()
    private let powerMonitor = PowerMonitor()
    private let interceptor = MediaKeyInterceptor()
    private var dismissWork: DispatchWorkItem?
    /// A notice to bring back if covered: built again each time it shows, so its wording stays current.
    private struct Lasting {
        let make: () -> HUDEvent?
        /// What clicking it does, kept when it comes back after another HUD.
        let action: (() -> Void)?
    }
    private var lasting = LastingNotices<Lasting>()
    private var lastHeadphones: HeadphoneBattery?
    private var headphoneCheckInFlight = false
    private let ddcQueue = DispatchQueue(label: "nunsseop.ddc")
    /// External displays answering DDC, with the last known brightness as a fraction of their maximum.
    private var externalDisplays: [(service: CFTypeRef, max: Int)] = []
    private var externalLevel: Float?
    private var lastKeyboardLevel: Float = 0.5
    private var pendingExternalLevel: Float?
    private var cancellables: Set<AnyCancellable> = []
    /// Checks for the Accessibility permission while it is missing, so granting it takes effect without a relaunch.
    private var trustPoll: Timer?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        audio.onVolumeChange = { [weak self] volume, muted in
            guard let self, self.settings.volumeHUDEnabled else { return }
            self.show(.volume(volume, muted: muted))
        }
        audio.onOutputDeviceChange = { [weak self] in self?.checkHeadphones(after: 4) }
        audio.start()

        powerMonitor.onChange = { [weak self] state in
            guard let self else { return }
            let previous = self.power
            let pluggedChanged = previous?.onAC != state.onAC
            self.power = state
            if pluggedChanged && self.settings.chargingHUDEnabled {
                self.show(.power(state), duration: 2.5)
            } else if self.settings.batteryAlerts, let previous {
                if !state.onAC && previous.percent > 20 && state.percent <= 20 {
                    self.show(.notice(symbol: "battery.25percent", title: String(localized: "Battery low"),
                                      detail: "\(state.percent)%"), duration: 5)
                } else if state.onAC && previous.percent < 100 && state.percent >= 100 {
                    self.show(.notice(symbol: "battery.100percent.bolt", title: String(localized: "Fully charged"),
                                      detail: nil), duration: 4)
                }
            }
        }
        powerMonitor.start()
        power = powerMonitor.state

        // The tap callback runs on the main run loop.
        interceptor.handlesVolume = { [weak self] in MainActor.assumeIsolated { self?.audio.canSetVolume ?? false } }
        interceptor.handlesBrightness = { [weak self] in
            MainActor.assumeIsolated { BuiltInBrightness.isAvailable || self?.externalTarget != nil }
        }
        interceptor.handlesKeyboard = { KeyboardBacklight.isAvailable }
        refreshExternalDisplays()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshExternalDisplays() }
        }
        interceptor.onKey = { [weak self] key, fine in self?.handle(key, fine: fine) }
        settings.$replaceSystemHUD
            .removeDuplicates()
            .sink { [weak self] enabled in self?.setInterception(enabled) }
            .store(in: &cancellables)

        checkHeadphones(after: 1)

        #if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "--demo-hud"), i + 1 < CommandLine.arguments.count {
            let demo: HUDEvent = switch CommandLine.arguments[i + 1] {
            case "power": .power(PowerState(percent: 76, isCharging: true, onAC: true))
            case "brightness": .brightness(0.6)
            case "keyboard": .keyboard(0.7)
            case "notice": .notice(symbol: "sparkles", title: "Claude Code", detail: "Claude is waiting for your input")
            default: .headphones(HeadphoneBattery(name: "AirPods Pro", levels: [(String(localized: "Left"), 90), (String(localized: "Right"), 85), (String(localized: "Case"), 60)]))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.show(demo, duration: 30) }
        }
        #endif
    }

    func retryInterception() {
        setInterception(settings.replaceSystemHUD)
    }

    private func setInterception(_ enabled: Bool) {
        trustPoll?.invalidate()
        trustPoll = nil
        guard enabled else {
            interceptor.stop()
            interceptorNeedsPermission = false
            return
        }
        if !MediaKeyInterceptor.isTrusted {
            MediaKeyInterceptor.requestTrust()
            interceptorNeedsPermission = true
            trustPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    if MediaKeyInterceptor.isTrusted { self?.retryInterception() }
                }
            }
            trustPoll?.tolerance = 0.2
            return
        }
        interceptorNeedsPermission = !interceptor.start()
    }

    private func handle(_ key: MediaKey, fine: Bool) {
        let step: Float = fine ? 1.0 / 64 : 1.0 / 16
        switch key {
        case .volumeUp:
            audio.setVolume(audio.volume + step)
        case .volumeDown:
            audio.setVolume(audio.volume - step)
        case .mute:
            audio.setMuted(!audio.isMuted)
        case .brightnessUp, .brightnessDown:
            let delta = key == .brightnessUp ? step : -step
            if BuiltInBrightness.isAvailable && (pointerIsOnBuiltInDisplay || externalTarget == nil),
               let level = BuiltInBrightness.level {
                let new = min(1, max(0, level + delta))
                BuiltInBrightness.set(new)
                show(.brightness(new))
            } else if let level = externalLevel, let display = externalTarget {
                let new = min(1, max(0, level + delta))
                externalLevel = new
                show(.brightness(new))
                // Coalesce key repeats: only the latest value is written.
                let alreadyQueued = pendingExternalLevel != nil
                pendingExternalLevel = new
                guard !alreadyQueued else { return }
                ddcQueue.async { [weak self] in
                    let value = DispatchQueue.main.sync { () -> Float? in
                        MainActor.assumeIsolated {
                            defer { self?.pendingExternalLevel = nil }
                            return self?.pendingExternalLevel
                        }
                    }
                    if let value {
                        ExternalBrightness.set(Int((Float(display.max) * value).rounded()), on: display.service)
                    }
                }
            }
        case .keyboardUp, .keyboardDown, .keyboardToggle:
            guard let level = KeyboardBacklight.level else { return }
            let new: Float
            switch key {
            case .keyboardUp: new = min(1, level + step)
            case .keyboardDown: new = max(0, level - step)
            default: new = level > 0 ? 0 : lastKeyboardLevel
            }
            if level > 0 { lastKeyboardLevel = level }
            KeyboardBacklight.set(new)
            show(.keyboard(new))
        }
        // Volume HUDs come from the audio listener; show one even if it stays silent at the limits.
        if key == .volumeUp || key == .volumeDown || key == .mute {
            show(.volume(audio.volume, muted: audio.isMuted))
        }
    }

    /// DDC services can't be matched to screens here, so external brightness is only
    /// handled when exactly one external screen is connected and it answers DDC.
    private var externalTarget: (service: CFTypeRef, max: Int)? {
        let externalScreens = NSScreen.screens.filter { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
            return CGDisplayIsBuiltin(id) == 0
        }
        guard externalScreens.count <= 1, externalDisplays.count == 1 else { return nil }
        return externalDisplays[0]
    }

    private var pointerIsOnBuiltInDisplay: Bool {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }),
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { return false }
        return CGDisplayIsBuiltin(id) != 0
    }

    /// Finds external displays that answer DDC and reads their brightness once.
    private func refreshExternalDisplays() {
        ddcQueue.async { [weak self] in
            var found: [(service: CFTypeRef, max: Int)] = []
            var level: Float?
            for service in ExternalBrightness.services() {
                guard let reading = ExternalBrightness.level(of: service) else { continue }
                found.append((service, reading.max))
                if level == nil { level = Float(reading.current) / Float(reading.max) }
            }
            DispatchQueue.main.async {
                self?.externalDisplays = found
                self?.externalLevel = level
            }
        }
    }

    private func checkHeadphones(after delay: Double) {
        guard settings.headphoneHUDEnabled, !headphoneCheckInFlight else { return }
        headphoneCheckInFlight = true
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            let battery = HeadphoneBatteryReader.read()
            DispatchQueue.main.async {
                guard let self else { return }
                self.headphoneCheckInFlight = false
                defer { self.lastHeadphones = battery }
                guard let battery, battery.name != self.lastHeadphones?.name else { return }
                self.show(.headphones(battery), duration: 3.5)
            }
        }
    }

    func show(_ newEvent: HUDEvent, duration: Double = 1.6, action: (() -> Void)? = nil) {
        lasting.replace(with: nil, duration: duration, now: .now)
        present(newEvent, duration: duration)
        self.action = action
    }

    /// Runs the notice's action and takes the notice away; false when it has none.
    func performAction() -> Bool {
        guard let action else { return false }
        action()
        dismissWork?.cancel()
        dismiss()
        return true
    }

    /// A notice that must be seen once: if another HUD covers it before its time is up, it comes back
    /// when that HUD is gone, for the time it had left. `make` runs again then; returning nil drops it.
    /// Returns whether it showed: `make` can decline from the start.
    @discardableResult
    func showLasting(duration: Double, action: (() -> Void)? = nil, _ make: @escaping () -> HUDEvent?) -> Bool {
        guard let notice = make() else { return false }
        lasting.replace(with: Lasting(make: make, action: action), duration: duration, now: .now)
        present(notice, duration: duration)
        self.action = action
        return true
    }

    private func present(_ newEvent: HUDEvent, duration: Double) {
        dismissWork?.cancel()
        action = nil
        event = newEvent
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func dismiss() {
        while let next = lasting.finish(now: .now) {
            if let event = next.notice.make() {
                present(event, duration: next.remaining)
                action = next.notice.action
                return
            }
        }
        action = nil
        event = nil
    }
}
