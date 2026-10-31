import AppKit
import SwiftUI

/// One nonactivating popup at a time, including when multiple reservations come due together.
@MainActor
final class AlarmRuntime {
    static let shared = AlarmRuntime()
    weak var notices: NoticeLog?
    private let store = AlarmStore.shared
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var panel: AlarmPanel?
    private var current: UUID?
    private var queue: [UUID] = []
    private var hideWork: DispatchWorkItem?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        store.onPresent = { [weak self] alarm, repeating in
            guard let self else { return }
            if !repeating {
                self.notices?.add(symbol: "alarm", title: "눈썹 알림", detail: alarm.displayMessage)
            }
            self.enqueue(alarm.id)
        }
        store.onDismiss = { [weak self] id in self?.remove(id) }
        store.onChange = { [weak self] in self?.schedule() }
        observe(.NSSystemClockDidChange, center: .default) { [weak self] in self?.store.clockChanged() }
        observe(NSNotification.Name.NSSystemTimeZoneDidChange, center: .default) { [weak self] in self?.store.clockChanged() }
        observe(NSWorkspace.didWakeNotification, center: NSWorkspace.shared.notificationCenter) { [weak self] in self?.resume() }
        observe(NSWorkspace.sessionDidBecomeActiveNotification, center: NSWorkspace.shared.notificationCenter) { [weak self] in self?.resume() }
        observe(NSApplication.didChangeScreenParametersNotification, center: .default) { [weak self] in self?.positionPanel() }
        store.resume()
        schedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        hideWork?.cancel()
        panel?.orderOut(nil)
        panel = nil
        current = nil
        queue = []
        for (center, observer) in observers { center.removeObserver(observer) }
        observers = []
        store.onPresent = nil
        store.onDismiss = nil
        store.onChange = nil
        started = false
    }

    private func observe(_ name: Notification.Name, center: NotificationCenter, action: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { action() }
        }
        observers.append((center, token))
    }

    private func resume() {
        // A pre-sleep popup may still be marked current while its dismissal is overdue.
        // Rebuild from persisted state rather than letting that stale window swallow the catch-up.
        hideWork?.cancel()
        hideWork = nil
        panel?.orderOut(nil)
        current = nil
        queue = []
        store.resume()
        schedule()
    }

    /// Sleep until the earliest delivery instead of polling every second.
    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard let due = store.nextDelivery else { return }
        let timer = Timer(timeInterval: max(0.05, due.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.store.tick()
                self?.schedule()
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func enqueue(_ id: UUID) {
        guard current != id, !queue.contains(id) else { return }
        queue.append(id)
        showNext()
    }

    private func showNext() {
        guard current == nil else { return }
        while !queue.isEmpty {
            let id = queue.removeFirst()
            guard let alarm = store.alarms.first(where: { $0.id == id && $0.isEnabled && $0.activeSince != nil }) else { continue }
            let panel = self.panel ?? AlarmPanel()
            self.panel = panel
            current = id
            panel.contentView = AlarmHostingView(rootView: AlarmPopupContent(alarm: alarm) { [weak self] in
                self?.store.acknowledge(id)
            })
            positionPanel()
            panel.orderFrontRegardless()
            if alarm.soundEnabled { NSSound(named: "Glass")?.play() }
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.hideCurrent() }
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
            return
        }
    }

    private func remove(_ id: UUID) {
        queue.removeAll { $0 == id }
        if current == id { hideCurrent() }
    }

    private func hideCurrent() {
        hideWork?.cancel()
        hideWork = nil
        panel?.orderOut(nil)
        current = nil
        showNext()
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.maxX - AlarmPopupContent.size.width - 16,
                                     y: frame.maxY - AlarmPopupContent.size.height - 16))
    }
}

private final class AlarmPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(origin: .zero, size: AlarmPopupContent.size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class AlarmHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct AlarmPopupContent: View {
    static let size = CGSize(width: 360, height: 210)
    let alarm: UserAlarm
    var acknowledge: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("눈썹 알림", systemImage: "alarm.fill").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(verbatim: alarm.timeLabel).font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
            }
            // Collapse manual line breaks so a 100-character message cannot push the button offscreen.
            Text(verbatim: alarm.displayMessage.split(whereSeparator: { $0.isWhitespace }).joined(separator: " "))
                .font(.system(size: 14))
                .lineLimit(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack {
                Text("미확인 시 \(alarm.repeatMinutes)분마다 반복")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("확인", action: acknowledge)
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("이번 알람의 반복 알림을 종료합니다")
            }
        }
        .padding(16)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.12)))
    }
}
