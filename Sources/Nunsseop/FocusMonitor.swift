import Foundation
import Intents

/// Notices macOS Focus (Do Not Disturb and the other Focus modes) turning on and off, through the public Focus Status API:
/// no Full Disk Access, but the system asks once, and the answer is only known while "Share Focus Status" is on in System
/// Settings › Focus. It reads whether any Focus is on, not which one. It polls only while started.
@MainActor
final class FocusMonitor: ObservableObject {
    /// Nil while it isn't known: not started, not allowed, or the system isn't sharing the status.
    @Published private(set) var isFocused: Bool?
    /// A Focus turned on or off; the first reading after starting is not a change.
    var onChange: ((_ isFocused: Bool) -> Void)?

    private var timer: Timer?
    private var running = false

    static let pollInterval: TimeInterval = 5

    func start() {
        guard !running else { return }
        running = true
        let center = INFocusStatusCenter.default
        switch center.authorizationStatus {
        case .authorized:
            poll()
        case .notDetermined:
            center.requestAuthorization { [weak self] status in
                Task { @MainActor in
                    guard let self, self.running, status == .authorized else { return }
                    self.poll()
                }
            }
        default:
            break
        }
    }

    /// `clearing: false` keeps the last state, so starting again while a Focus is on stays quiet.
    func stop(clearing: Bool = true) {
        running = false
        timer?.invalidate()
        timer = nil
        if clearing { isFocused = nil }
    }

    private func poll() {
        guard timer == nil else { return }
        read()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.read() }
        }
        timer?.tolerance = 1
    }

    private func read() {
        apply(INFocusStatusCenter.default.focusStatus.isFocused)
    }

    /// Takes a reading; announces a change from one known state to the other.
    func apply(_ focused: Bool?) {
        let previous = isFocused
        guard focused != previous else { return }
        isFocused = focused
        if let previous, let focused, previous != focused { onChange?(focused) }
    }
}
