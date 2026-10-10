import Foundation
import Testing
@testable import Nunsseop

struct CalendarBusyDaysTests {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ calendar: Calendar, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    private func days(_ calendar: Calendar, _ month: Int, _ days: [Int]) -> Set<Date> {
        Set(days.map { date(calendar, month, $0) })
    }

    // 2026-10-05 is a Monday.
    @Test(arguments: ["Asia/Seoul", "America/Los_Angeles", "UTC"])
    func anEventSpanningDaysMarksEachOfThem(zone: String) {
        let calendar = calendar(zone)
        let busy = CalendarModel.busyDays(spans: [(date(calendar, 10, 5, 10), date(calendar, 10, 7, 12))],
                                          from: date(calendar, 10, 5), days: 7, calendar: calendar)
        #expect(busy == days(calendar, 10, [5, 6, 7]))
    }

    @Test func anAllDayEventEndingAtTheEndOfItsDayMarksOnlyThatDay() {
        let calendar = calendar("Asia/Seoul")
        let busy = CalendarModel.busyDays(spans: [(date(calendar, 10, 6), date(calendar, 10, 6, 23, 59, 59))],
                                          from: date(calendar, 10, 5), days: 7, calendar: calendar)
        #expect(busy == days(calendar, 10, [6]))
    }

    @Test func anEventThatStartedBeforeTheWeekMarksTheDaysItReaches() {
        let calendar = calendar("Asia/Seoul")
        let busy = CalendarModel.busyDays(spans: [(date(calendar, 10, 4, 22), date(calendar, 10, 6, 8))],
                                          from: date(calendar, 10, 5), days: 7, calendar: calendar)
        #expect(busy == days(calendar, 10, [5, 6]))
    }

    @Test func anEventAcrossMidnightMarksBothDays() {
        let calendar = calendar("Asia/Seoul")
        let busy = CalendarModel.busyDays(spans: [(date(calendar, 10, 6, 23, 30), date(calendar, 10, 7, 0, 30))],
                                          from: date(calendar, 10, 5), days: 7, calendar: calendar)
        #expect(busy == days(calendar, 10, [6, 7]))
    }

    @Test func anEventEndingExactlyAtMidnightDoesNotMarkTheNextDay() {
        let calendar = calendar("Asia/Seoul")
        let busy = CalendarModel.busyDays(spans: [(date(calendar, 10, 6, 23), date(calendar, 10, 7))],
                                          from: date(calendar, 10, 5), days: 7, calendar: calendar)
        #expect(busy == days(calendar, 10, [6]))
    }

    @Test func daysOutsideTheWeekAreLeftOut() {
        let calendar = calendar("Asia/Seoul")
        let busy = CalendarModel.busyDays(spans: [(date(calendar, 10, 10, 12), date(calendar, 10, 14, 12))],
                                          from: date(calendar, 10, 5), days: 7, calendar: calendar)
        #expect(busy == days(calendar, 10, [10, 11]))
    }

    @Test func noEventsMarkNothing() {
        let calendar = calendar("UTC")
        #expect(CalendarModel.busyDays(spans: [], from: date(calendar, 10, 5), days: 7, calendar: calendar).isEmpty)
    }

    @Test func aWeekAcrossTheEndOfDaylightSavingTimeHasSevenDistinctDays() {
        let calendar = calendar("America/New_York")
        // 2026-11-01 has 25 hours.
        let busy = CalendarModel.busyDays(spans: [(date(calendar, 10, 30, 10), date(calendar, 11, 6, 10))],
                                          from: date(calendar, 10, 30), days: 7, calendar: calendar)
        #expect(busy == days(calendar, 10, [30, 31]).union(days(calendar, 11, [1, 2, 3, 4, 5])))
        #expect(busy.count == 7)
    }

    @Test func aLongDayAtTheEndOfDaylightSavingTimeStillEndsAtItsMidnight() {
        let calendar = calendar("America/New_York")
        let busy = CalendarModel.busyDays(spans: [(date(calendar, 11, 1, 0, 30), date(calendar, 11, 2))],
                                          from: date(calendar, 10, 30), days: 7, calendar: calendar)
        #expect(busy == days(calendar, 11, [1]))
    }
}
