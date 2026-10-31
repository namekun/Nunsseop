import Combine
import Foundation

struct UserAlarm: Codable, Identifiable, Equatable {
    enum Schedule: String, Codable, CaseIterable {
        case daily, weekdays, once

        var title: String {
            switch self {
            case .daily: return "매일"
            case .weekdays: return "요일별"
            case .once: return "특정 날짜 1회"
            }
        }
    }

    static let messageLimit = 100
    var id = UUID()
    var message = ""
    var hour = 21
    var minute = 30
    var schedule: Schedule = .daily
    /// Calendar weekdays: Sunday = 1, Saturday = 7.
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    var date = Date()
    var repeatMinutes = 1
    var soundEnabled = true
    var isEnabled = true
    /// Persist the pending occurrence so sleeping or quitting cannot silently skip it.
    var nextDue: Date?
    var activeSince: Date?
    var nextRepeat: Date?

    var displayMessage: String {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "눈썹 알림" : String(text.prefix(Self.messageLimit))
    }

    var timeLabel: String { String(format: "%02d:%02d", hour, minute) }

    func nextOccurrence(after now: Date, calendar: Calendar) -> Date? {
        if schedule == .once {
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)
        }
        let days: [Int?] = schedule == .daily ? [nil] : weekdays.sorted().map { Optional($0) }
        return days.compactMap { day -> Date? in
            var parts = DateComponents()
            parts.hour = hour
            parts.minute = minute
            parts.second = 0
            parts.weekday = day
            // One occurrence through DST: spring-forward uses the next valid time,
            // fall-back uses the first occurrence of a repeated wall-clock time.
            return calendar.nextDate(after: now, matching: parts, matchingPolicy: .nextTime,
                                     repeatedTimePolicy: .first)
        }.min()
    }

    mutating func normalize() {
        message = String(message.prefix(Self.messageLimit))
        hour = min(23, max(0, hour))
        minute = min(59, max(0, minute))
        repeatMinutes = min(1440, max(1, repeatMinutes))
        weekdays = weekdays.filter { (1...7).contains($0) }
    }
}

/// Reservation and acknowledgment state are independent of how a notice is displayed.
@MainActor
final class AlarmStore: ObservableObject {
    static let shared = AlarmStore()
    private static let key = "userAlarms.v1"
    @Published private(set) var alarms: [UserAlarm]
    @Published private(set) var storageError: String?
    var onPresent: ((UserAlarm, Bool) -> Void)?
    var onDismiss: ((UUID) -> Void)?
    var onChange: (() -> Void)?

    private let defaults: UserDefaults
    private let now: () -> Date
    private let calendar: () -> Calendar

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = { .now },
         calendar: @escaping () -> Calendar = { .autoupdatingCurrent }) {
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        if let data = defaults.data(forKey: Self.key) {
            do {
                alarms = try JSONDecoder().decode([UserAlarm].self, from: data)
                for index in alarms.indices { alarms[index].normalize() }
            } catch {
                alarms = []
                storageError = "저장된 알람을 읽지 못했습니다. 앱을 다시 실행해 주세요."
            }
        } else {
            alarms = []
        }
    }

    func save(_ draft: UserAlarm) {
        guard storageError == nil else { return }
        var alarm = draft
        alarm.normalize()
        guard alarm.schedule != .weekdays || !alarm.weekdays.isEmpty else { return }
        alarm.activeSince = nil
        alarm.nextRepeat = nil
        alarm.nextDue = alarm.isEnabled ? alarm.nextOccurrence(after: now(), calendar: calendar()) : nil
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index] = alarm
            onDismiss?(alarm.id)
        } else {
            alarms.append(alarm)
        }
        persist()
    }

    func setEnabled(_ id: UUID, _ enabled: Bool) {
        guard var alarm = alarms.first(where: { $0.id == id }) else { return }
        alarm.isEnabled = enabled
        save(alarm)
    }

    func remove(_ id: UUID) {
        guard storageError == nil else { return }
        alarms.removeAll { $0.id == id }
        onDismiss?(id)
        persist()
    }

    /// Acknowledge this occurrence only; recurring alarms keep their next reservation.
    func acknowledge(_ id: UUID) {
        guard storageError == nil,
              let index = alarms.firstIndex(where: { $0.id == id }),
              alarms[index].activeSince != nil else { return }
        alarms[index].activeSince = nil
        alarms[index].nextRepeat = nil
        if alarms[index].schedule == .once {
            alarms[index].isEnabled = false
            alarms[index].nextDue = nil
        } else {
            alarms[index].nextDue = alarms[index].nextOccurrence(after: now(), calendar: calendar())
        }
        onDismiss?(id)
        persist()
    }

    /// Catch up once, never replay the entire backlog of missed minute intervals.
    func tick() {
        guard storageError == nil else { return }
        let current = now()
        var presentations: [(UserAlarm, Bool)] = []
        for index in alarms.indices where alarms[index].isEnabled {
            let repeating = alarms[index].activeSince != nil
            let due = repeating ? alarms[index].nextRepeat : alarms[index].nextDue
            guard let due, due <= current else { continue }
            if !repeating {
                alarms[index].activeSince = due
                alarms[index].nextDue = nil
            }
            alarms[index].nextRepeat = current.addingTimeInterval(TimeInterval(alarms[index].repeatMinutes * 60))
            presentations.append((alarms[index], repeating))
        }
        guard !presentations.isEmpty else { return }
        // Commit before presenting, so an immediate acknowledgment cannot be overwritten.
        persist()
        for (alarm, repeating) in presentations { onPresent?(alarm, repeating) }
    }

    /// A still-unconfirmed alarm is shown immediately when the app or Mac wakes up.
    func resume() {
        guard storageError == nil else { return }
        let current = now()
        var changed = false
        for index in alarms.indices where alarms[index].isEnabled {
            if alarms[index].activeSince != nil {
                alarms[index].nextRepeat = current
            } else if (alarms[index].nextDue ?? .distantFuture) > current {
                // The time zone can change while the app is closed, too.
                let due = alarms[index].nextOccurrence(after: current, calendar: calendar())
                if due != alarms[index].nextDue {
                    alarms[index].nextDue = due
                    changed = true
                }
            }
        }
        if changed { persist() }
        tick()
    }

    /// Move future reservations to the new local wall-clock time, retaining overdue ones.
    func clockChanged() {
        resume()
    }

    var nextDelivery: Date? {
        alarms.filter(\.isEnabled).compactMap { $0.activeSince == nil ? $0.nextDue : $0.nextRepeat }.min()
    }

    private func persist() {
        guard storageError == nil else { return }
        do {
            defaults.set(try JSONEncoder().encode(alarms), forKey: Self.key)
        } catch {
            storageError = "알람을 저장하지 못했습니다."
        }
        onChange?()
    }
}
