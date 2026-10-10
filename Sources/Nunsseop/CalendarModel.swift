import AppKit
import EventKit
import SwiftUI

struct CalendarItem: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    /// A video-call link found in the event's URL, location or notes.
    var joinURL: URL? = nil

    func canJoin(at date: Date) -> Bool { joinURL != nil && end > date }
}

struct ReminderItem: Identifiable, Equatable {
    let id: String
    let title: String
    let due: Date?
    let color: Color
}

@MainActor
final class CalendarModel: ObservableObject {
    enum Access { case unknown, granted, denied }

    @Published private(set) var access: Access
    @Published var selectedDay = Calendar.current.startOfDay(for: .now) {
        didSet { reload(alerts: false) }
    }
    @Published private(set) var items: [CalendarItem] = []
    /// Calendars whose events are left out.
    var hiddenCalendarIDs: Set<String> = [] {
        didSet { if hiddenCalendarIDs != oldValue { reload() } }
    }
    /// Days of `week` that have at least one event, as start-of-day dates.
    @Published private(set) var busyDays: Set<Date> = []
    @Published private(set) var reminderAccess: Access
    @Published private(set) var reminders: [ReminderItem] = []
    /// Called shortly before a timed event starts, while `alertsEnabled` is on.
    var onUpcoming: ((CalendarItem) -> Void)?
    var alertsEnabled = false {
        didSet { if alertsEnabled != oldValue { scheduleAlert() } }
    }
    private var alertTimer: Timer?
    /// How long an event notice stays, and the gap before the next one when several are due.
    static let alertSpacing: TimeInterval = 8
    private var alertQueue = EventAlertQueue(spacing: CalendarModel.alertSpacing)

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var wakeObservers: [NSObjectProtocol] = []
    #if DEBUG
    private let isDemo = CommandLine.arguments.contains("--demo-track")
    #else
    private let isDemo = false
    #endif

    init() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .granted
        case .denied, .restricted, .writeOnly: access = .denied
        default: access = .unknown
        }
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: reminderAccess = .granted
        case .denied, .restricted, .writeOnly: reminderAccess = .denied
        default: reminderAccess = .unknown
        }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        // Timers don't count time asleep, so a pending alert is worked out again on wake and clock changes.
        wakeObservers = [
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleAlert() }
            },
            NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleAlert() }
            },
        ]
        reload()
    }

    func requestAccess() {
        if access == .denied {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            return
        }
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.access = granted ? .granted : .denied
                self?.reload()
            }
        }
    }

    func requestReminderAccess() {
        if reminderAccess == .denied {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!)
            return
        }
        store.requestFullAccessToReminders { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.reminderAccess = granted ? .granted : .denied
                self?.reload()
            }
        }
    }

    func complete(_ item: ReminderItem) {
        reminders.removeAll { $0.id == item.id }
        guard !isDemo, let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
        } catch {
            reloadReminders()
        }
    }

    /// Incomplete reminders due by the end of the selected day, including undated ones.
    private func reloadReminders() {
        guard reminderAccess == .granted,
              let end = Calendar.current.date(byAdding: .day, value: 1, to: selectedDay) else {
            reminders = []
            return
        }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] found in
            let items = (found ?? [])
                .compactMap { reminder -> ReminderItem? in
                    let due = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
                    if let due, due >= end { return nil }
                    return ReminderItem(id: reminder.calendarItemIdentifier, title: reminder.title ?? "",
                                        due: due, color: Color(nsColor: reminder.calendar?.color ?? .systemOrange))
                }
                .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            DispatchQueue.main.async { self?.reminders = items }
        }
    }

    /// Fixed events for checking the layout without calendar access.
    private func showDemoItems() {
        access = .granted
        let day = selectedDay
        func at(_ h: Int, _ m: Int) -> Date { Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: day)! }
        items = [
            CalendarItem(id: "a", title: "Team standup", start: at(10, 0), end: at(10, 15), isAllDay: false, color: .blue,
                         joinURL: URL(string: "https://meet.google.com/abc-defg-hij")),
            CalendarItem(id: "b", title: "Lunch", start: at(12, 30), end: at(13, 30), isAllDay: false, color: .orange),
            CalendarItem(id: "c", title: "5 km run", start: at(19, 0), end: at(19, 40), isAllDay: false, color: .green),
        ]
        busyDays = Set([0, 2, 5].compactMap { Calendar.current.date(byAdding: .day, value: $0, to: Calendar.current.startOfDay(for: .now)) })
        reminderAccess = .granted
        reminders = [
            ReminderItem(id: "r1", title: "Pay the electricity bill", due: at(18, 0), color: .orange),
            ReminderItem(id: "r2", title: "Buy coffee beans", due: nil, color: .orange),
        ]
    }

    /// The selected day and the six days after it.
    var week: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: Calendar.current.startOfDay(for: .now)) }
    }

    /// The start of each of `days` days from `first` that any of the event spans (start, end) touches.
    nonisolated static func busyDays(spans: [(start: Date, end: Date)], from first: Date, days: Int, calendar: Calendar) -> Set<Date> {
        let firstDay = calendar.startOfDay(for: first)
        return Set((0..<days).compactMap { offset -> Date? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            return spans.contains { $0.start < next && ($0.end > day || $0.start >= day) } ? day : nil
        })
    }

    /// The calendars to show: nil means every calendar, and an empty list none at all
    /// (to EventKit an empty list would also mean every calendar).
    private var shownCalendars: [EKCalendar]? {
        guard !hiddenCalendarIDs.isEmpty else { return nil }
        return store.calendars(for: .event).filter { !hiddenCalendarIDs.contains($0.calendarIdentifier) }
    }

    private func item(_ event: EKEvent, findingLink: Bool = true) -> CalendarItem {
        CalendarItem(id: event.eventIdentifier ?? UUID().uuidString,
                     title: event.title ?? "",
                     start: event.startDate, end: event.endDate,
                     isAllDay: event.isAllDay,
                     color: Color(nsColor: event.calendar.color ?? .systemBlue),
                     joinURL: findingLink ? MeetingLink.find(in: [event.url?.absoluteString, event.location, event.notes]) : nil)
    }

    /// Leaves out cancelled events, invitations the user declined, and events without an identifier,
    /// which would get a new random one, and so a new alert, on every check.
    nonisolated static func isAlertable(_ event: EKEvent) -> Bool {
        guard let id = event.eventIdentifier, !id.isEmpty else { return false }
        return event.status != .canceled && event.attendees?.first(where: \.isCurrentUser)?.participantStatus != .declined
    }

    /// Announces the next event whose alert is due and sets a timer for the one after.
    /// Looks a day and a half ahead, and checks again within 12 hours when nothing is coming.
    private func scheduleAlert() {
        alertTimer?.invalidate()
        alertTimer = nil
        guard alertsEnabled, access == .granted, !isDemo else { return }
        let calendars = shownCalendars
        guard calendars?.isEmpty != true else { return }
        let now = Date.now
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-EventAlert.grace),
                                                 end: now.addingTimeInterval(36 * 3600), calendars: calendars)
        let events = store.events(matching: predicate).filter(Self.isAlertable)
        let upcoming = events.map { item($0, findingLink: false) }
        // Events starting together are shown one after another, once each notice has had its time.
        let (announce, next) = alertQueue.step(items: upcoming, now: now)
        // Only the event being announced is searched for a meeting link, so a click on the notice can join.
        if let announce, let index = upcoming.firstIndex(of: announce) { onUpcoming?(item(events[index])) }
        let timer = Timer(fire: next ?? now.addingTimeInterval(12 * 3600), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleAlert() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        alertTimer = timer
    }

    /// Whether a notice for `item` may still show, checked again when one covered by another HUD comes back.
    func stillAlerts(_ item: CalendarItem) -> Bool {
        guard alertsEnabled, access == .granted, !isDemo else { return false }
        let calendars = shownCalendars
        guard calendars?.isEmpty != true else { return false }
        let predicate = store.predicateForEvents(withStart: item.start, end: max(item.end, item.start.addingTimeInterval(1)),
                                                 calendars: calendars)
        let current = store.events(matching: predicate).filter(Self.isAlertable).map { self.item($0, findingLink: false) }
        return EventAlert.isStillDue(item, enabled: true, among: current, now: .now)
    }

    /// Picking another day leaves the alerts alone; they don't depend on it.
    func reload(alerts: Bool = true) {
        if isDemo { showDemoItems(); return }
        reloadReminders()
        if alerts { scheduleAlert() }
        guard access == .granted else { items = []; busyDays = []; return }
        let calendars = shownCalendars
        if calendars?.isEmpty == true { items = []; busyDays = []; return }
        if let first = week.first, let last = week.last, let weekEnd = Calendar.current.date(byAdding: .day, value: 1, to: last) {
            let weekEvents = store.events(matching: store.predicateForEvents(withStart: first, end: weekEnd, calendars: calendars))
            busyDays = Self.busyDays(spans: weekEvents.map { ($0.startDate, $0.endDate) }, from: first, days: 7, calendar: .current)
        }
        let start = selectedDay
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        items = store.events(matching: predicate)
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .map { item($0) }
    }
}
