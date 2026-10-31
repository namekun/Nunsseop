import Foundation
import Testing
@testable import Nunsseop

@MainActor
@Suite(.serialized)
struct AlarmTests {
    @MainActor private final class Clock {
        var now = AlarmTests.date("2026-10-25T12:00:00Z")
        var calendar: Calendar = {
            var value = Calendar(identifier: .gregorian)
            value.timeZone = TimeZone(secondsFromGMT: 0)!
            return value
        }()
    }

    @MainActor private final class Fixture {
        let scratch = ScratchDefaults("Alarms")
        let clock = Clock()
        let store: AlarmStore
        var shown: [(UserAlarm, Bool)] = []
        var dismissed: [UUID] = []

        init() {
            let clock = self.clock
            store = AlarmStore(defaults: scratch.defaults, now: { clock.now }, calendar: { clock.calendar })
            store.onPresent = { [weak self] in self?.shown.append(($0, $1)) }
            store.onDismiss = { [weak self] in self?.dismissed.append($0) }
        }

        func reload() -> AlarmStore {
            let clock = self.clock
            return AlarmStore(defaults: scratch.defaults, now: { clock.now }, calendar: { clock.calendar })
        }
    }

    private static func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    @Test func firesAtReservationAndRepeatsUntilAcknowledged() {
        let f = Fixture()
        defer { f.scratch.remove() }
        let alarm = UserAlarm()
        f.store.save(alarm)
        f.clock.now = Self.date("2026-10-25T21:29:59Z")
        f.store.tick()
        #expect(f.shown.isEmpty)
        f.clock.now = Self.date("2026-10-25T21:30:00Z")
        f.store.tick()
        #expect(f.shown.count == 1 && !f.shown[0].1)
        f.clock.now.addTimeInterval(59)
        f.store.tick()
        #expect(f.shown.count == 1)
        f.clock.now.addTimeInterval(1)
        f.store.tick()
        #expect(f.shown.count == 2 && f.shown[1].1)
        f.store.acknowledge(alarm.id)
        f.clock.now.addTimeInterval(60)
        f.store.tick()
        #expect(f.shown.count == 2)
        #expect(f.store.alarms[0].nextDue == Self.date("2026-10-26T21:30:00Z"))
        #expect(f.dismissed == [alarm.id])
    }

    @Test func customIntervalIsMeasuredFromEachDelivery() {
        let f = Fixture()
        defer { f.scratch.remove() }
        var alarm = UserAlarm()
        alarm.repeatMinutes = 7
        f.store.save(alarm)
        f.clock.now = Self.date("2026-10-25T21:30:00Z")
        f.store.tick()
        f.clock.now.addTimeInterval(419)
        f.store.tick()
        #expect(f.shown.count == 1)
        f.clock.now.addTimeInterval(1)
        f.store.tick()
        #expect(f.shown.count == 2)
    }

    @Test func selectedWeekdaysAndDailyAcknowledgmentKeepFutureReservations() {
        let f = Fixture()
        defer { f.scratch.remove() }
        var alarm = UserAlarm()
        alarm.schedule = .weekdays
        alarm.weekdays = [2, 4]
        f.store.save(alarm)
        #expect(f.store.nextDelivery == Self.date("2026-10-26T21:30:00Z"))
        f.clock.now = Self.date("2026-10-26T21:30:00Z")
        f.store.tick()
        f.store.acknowledge(alarm.id)
        #expect(f.store.nextDelivery == Self.date("2026-10-28T21:30:00Z"))
    }

    @Test func oneTimeAlarmDisablesOnlyWhenAcknowledged() {
        let f = Fixture()
        defer { f.scratch.remove() }
        var alarm = UserAlarm()
        alarm.schedule = .once
        alarm.date = f.clock.now
        f.store.save(alarm)
        f.clock.now = Self.date("2026-10-25T21:30:00Z")
        f.store.tick()
        #expect(f.store.alarms[0].isEnabled)
        f.store.acknowledge(alarm.id)
        #expect(!f.store.alarms[0].isEnabled)
        #expect(f.store.nextDelivery == nil)
        let reloaded = f.reload()
        reloaded.resume()
        #expect(!reloaded.alarms[0].isEnabled)
    }

    @Test func simultaneousAlarmsHaveIndependentAcknowledgmentsAndToggles() {
        let f = Fixture()
        defer { f.scratch.remove() }
        let first = UserAlarm(), second = UserAlarm()
        f.store.save(first)
        f.store.save(second)
        f.clock.now = Self.date("2026-10-25T21:30:00Z")
        f.store.tick()
        #expect(Set(f.shown.map { $0.0.id }) == [first.id, second.id])
        f.store.acknowledge(first.id)
        f.clock.now.addTimeInterval(60)
        f.store.tick()
        #expect(f.shown.count == 3 && f.shown.last?.0.id == second.id)
        f.store.setEnabled(second.id, false)
        f.clock.now.addTimeInterval(60)
        f.store.tick()
        #expect(f.shown.count == 3)
        #expect(f.store.alarms[1].activeSince == nil)
    }

    @Test func restartCatchesMissedReservationOnceWithoutBacklog() {
        let f = Fixture()
        defer { f.scratch.remove() }
        f.store.save(UserAlarm())
        f.clock.now = Self.date("2026-10-28T22:00:00Z")
        let reloaded = f.reload()
        var shown = 0
        reloaded.onPresent = { _, _ in shown += 1 }
        reloaded.resume()
        reloaded.tick()
        #expect(shown == 1)
        #expect(reloaded.nextDelivery == f.clock.now.addingTimeInterval(60))
    }

    @Test func restartRestoresActiveAlarmAndAcknowledgmentPersists() {
        let f = Fixture()
        defer { f.scratch.remove() }
        let alarm = UserAlarm()
        f.store.save(alarm)
        f.clock.now = Self.date("2026-10-25T21:30:00Z")
        f.store.tick()
        f.clock.now.addTimeInterval(10)
        let reloaded = f.reload()
        var shown = 0
        reloaded.onPresent = { _, repeating in
            #expect(repeating)
            shown += 1
        }
        reloaded.resume()
        #expect(shown == 1)
        reloaded.acknowledge(alarm.id)
        let again = f.reload()
        again.onPresent = { _, _ in shown += 1 }
        again.resume()
        #expect(shown == 1)
        #expect(again.alarms[0].activeSince == nil)
    }

    @Test func wakeCoalescesMissedRepeats() {
        let f = Fixture()
        defer { f.scratch.remove() }
        f.store.save(UserAlarm())
        f.clock.now = Self.date("2026-10-25T21:30:00Z")
        f.store.tick()
        f.clock.now.addTimeInterval(7200)
        f.store.resume()
        f.store.tick()
        #expect(f.shown.count == 2)
        #expect(f.store.nextDelivery == f.clock.now.addingTimeInterval(60))
    }

    @Test func editingOrDeletingActiveAlarmStopsOldOccurrence() {
        let f = Fixture()
        defer { f.scratch.remove() }
        var alarm = UserAlarm()
        f.store.save(alarm)
        f.clock.now = Self.date("2026-10-25T21:30:00Z")
        f.store.tick()
        alarm.hour = 23
        f.store.save(alarm)
        #expect(f.store.alarms[0].activeSince == nil)
        #expect(f.store.nextDelivery == Self.date("2026-10-25T23:30:00Z"))
        f.store.remove(alarm.id)
        #expect(f.store.alarms.isEmpty && f.reload().alarms.isEmpty)
        #expect(f.store.nextDelivery == nil)
    }

    @Test func blankAndUnicodeMessagesRespectCharacterLimit() {
        var alarm = UserAlarm()
        alarm.message = " \n\t "
        #expect(alarm.displayMessage == "눈썹 알림")
        alarm.message = String(repeating: "👨‍👩‍👧‍👦", count: 101)
        alarm.normalize()
        #expect(alarm.message.count == 100)
        #expect(alarm.displayMessage.count == 100)
        alarm.repeatMinutes = 0
        alarm.normalize()
        #expect(alarm.repeatMinutes == 1)
    }

    @Test func emptyWeekdaySelectionCannotCreateAnUnreachableAlarm() {
        let f = Fixture()
        defer { f.scratch.remove() }
        var alarm = UserAlarm()
        alarm.schedule = .weekdays
        alarm.weekdays = []
        f.store.save(alarm)
        #expect(f.store.alarms.isEmpty)
    }

    @Test func clockChangeRecalculatesFutureLocalTime() {
        let f = Fixture()
        defer { f.scratch.remove() }
        f.store.save(UserAlarm())
        f.clock.calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        f.store.clockChanged()
        #expect(f.store.nextDelivery == Self.date("2026-10-25T12:30:00Z"))
    }

    @Test func restartAlsoRecalculatesFutureReservationsAfterTimeZoneChange() {
        let f = Fixture()
        defer { f.scratch.remove() }
        f.store.save(UserAlarm())
        f.clock.calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let reloaded = f.reload()
        reloaded.resume()
        #expect(reloaded.nextDelivery == Self.date("2026-10-25T12:30:00Z"))
        #expect(f.shown.isEmpty)
    }

    @Test func disablingPersistsAndReenablingUsesANewReservation() {
        let f = Fixture()
        defer { f.scratch.remove() }
        let alarm = UserAlarm()
        f.store.save(alarm)
        f.store.setEnabled(alarm.id, false)
        f.clock.now = Self.date("2026-10-25T22:00:00Z")
        let reloaded = f.reload()
        reloaded.resume()
        #expect(reloaded.nextDelivery == nil)
        reloaded.setEnabled(alarm.id, true)
        #expect(reloaded.nextDelivery == Self.date("2026-10-26T21:30:00Z"))
    }

    @Test func daylightSavingGapsAndRepeatedHoursProduceOneReservation() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        var alarm = UserAlarm()
        alarm.hour = 2
        alarm.minute = 30
        #expect(alarm.nextOccurrence(after: Self.date("2026-03-08T05:00:00Z"), calendar: calendar)
                == Self.date("2026-03-08T07:00:00Z"))
        alarm.hour = 1
        #expect(alarm.nextOccurrence(after: Self.date("2026-11-01T04:00:00Z"), calendar: calendar)
                == Self.date("2026-11-01T05:30:00Z"))
    }

    @Test func corruptStorageIsNotSilentlyOverwritten() {
        let f = Fixture()
        defer { f.scratch.remove() }
        let broken = Data("broken".utf8)
        f.scratch.defaults.set(broken, forKey: "userAlarms.v1")
        let reloaded = f.reload()
        reloaded.save(UserAlarm())
        #expect(reloaded.storageError != nil)
        #expect(f.scratch.defaults.data(forKey: "userAlarms.v1") == broken)
    }
}
