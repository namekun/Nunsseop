import AppKit

/// Claude Code sessions for the agents count, told by the hooks Nunsseop installs, so one running in Muxy or a
/// plain terminal counts as well as one in herdr. Every session is an entry that expires, because a hook can't say
/// when a turn is cut short with Esc or Claude Code is killed: neither sends an event.
///
/// Known limit: approving a permission sends no event either (PostToolUse isn't installed, to spare a process per
/// tool call), so an approved turn that then works silently keeps its hand until the next event, and drops out of
/// the count after `activeWindow` while it still runs, until its Stop.
@MainActor
final class AgentHooks {
    /// How long a session keeps counting as working, or as asking for input, after its last event.
    static let activeWindow: TimeInterval = 20 * 60
    static let source = "hooks:claude"

    private struct Entry {
        var state: AgentBoard.State
        /// Done and not yet looked at, as opposed to asking for input.
        var finished = false
        var app: String?
        var expiresAt: Date
    }

    private let board: AgentBoard
    private let isOn: () -> Bool
    private let watchesHerdr: () -> Bool
    private let frontmostApp: () -> String?
    private var entries: [String: Entry] = [:]
    private var activation: NSObjectProtocol?

    /// - isOn: whether the closed notch shows the agents count; nothing is kept while it doesn't.
    /// - watchesHerdr: whether herdr's own count is running, which already includes a session in a herdr pane.
    init(board: AgentBoard, isOn: @escaping () -> Bool, watchesHerdr: @escaping () -> Bool,
         frontmostApp: @escaping () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }) {
        self.board = board
        self.isOn = isOn
        self.watchesHerdr = watchesHerdr
        self.frontmostApp = frontmostApp
        // Coming to an app looks at what finished in it. Muxy's tabs and the like aren't told apart.
        activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated { self?.activated(app) }
        }
    }

    deinit {
        if let activation { NSWorkspace.shared.notificationCenter.removeObserver(activation) }
    }

    func apply(_ event: AgentEvent, now: Date = .now) {
        guard isOn(), !(event.inHerdr && watchesHerdr()) else { return }
        entries = entries.filter { $0.value.expiresAt > now }
        let id = event.session
        switch event.action {
        case .working:
            entries[id] = Entry(state: .working, app: event.app, expiresAt: now.addingTimeInterval(Self.activeWindow))
        case .needsInput:
            entries[id] = Entry(state: .waiting, app: event.app, expiresAt: now.addingTimeInterval(Self.activeWindow))
        case .finished:
            // Finished in the app that's in front: it's being looked at.
            if event.app != nil, event.app == frontmostApp() {
                entries[id] = nil
            } else {
                entries[id] = Entry(state: .waiting, finished: true, app: event.app,
                                    expiresAt: now.addingTimeInterval(Herdr.doneWindow))
            }
        case .idle:
            // Claude Code only says idle with no dialog open, so a question or a working turn is over; a finished hand stays.
            if let entry = entries[id], !entry.finished { entries[id] = nil }
        case .remove:
            entries[id] = nil
        }
        publish(now: now)
    }

    /// Forgets everything, once the count isn't shown any more.
    func reset() {
        guard !entries.isEmpty else { return }
        entries = [:]
        board.clear(source: Self.source)
    }

    func activated(_ app: String?) {
        guard let app, entries.values.contains(where: { $0.finished && $0.app == app }) else { return }
        entries = entries.filter { !($0.value.finished && $0.value.app == app) }
        publish(now: .now)
    }

    private func publish(now: Date) {
        board.replace(source: Self.source,
                      with: entries.mapValues { AgentBoard.Agent(state: $0.state, expiresAt: $0.expiresAt) }, now: now)
    }
}
