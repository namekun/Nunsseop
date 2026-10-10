import Foundation
import Testing
@testable import Nunsseop

@MainActor
@Suite(.serialized)
struct TimerModelTests {
    private static let suiteName = "NunsseopTests.TimerModel"

    private final class ClockBox {
        var now: Date
        var chimes = 0
        var finished: [String] = []
        init(_ now: Date) { self.now = now }
    }

    @MainActor private final class Fixture {
        let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let clock: ClockBox
        let defaults: UserDefaults
        let model: TimerModel

        init() {
            defaults = UserDefaults(suiteName: TimerModelTests.suiteName)!
            defaults.removePersistentDomain(forName: TimerModelTests.suiteName)
            let box = ClockBox(t0)
            clock = box
            model = TimerModel(defaults: defaults, now: { box.now }, chime: { box.chimes += 1 })
            model.onFinished = { box.finished.append($0) }
        }

        func advance(to seconds: TimeInterval) { clock.now = t0.addingTimeInterval(seconds) }
        var chimeCount: Int { clock.chimes }
        var messages: [String] { clock.finished }

        func tearDown() {
            model.reset()
            defaults.removePersistentDomain(forName: TimerModelTests.suiteName)
        }
    }

    @Test func countdownCountsDownPausesAndResumesWhereItStopped() {
        let f = Fixture()
        defer { f.tearDown() }
        f.model.countdownSeconds = 300
        f.model.start()
        #expect(f.model.value(at: f.t0.addingTimeInterval(100)) == 200)

        f.advance(to: 100)
        f.model.pause()
        #expect(f.model.pausedValue == 200)
        #expect(!f.model.isRunning)
        #expect(f.model.isActive)
        #expect(f.model.value(at: f.t0.addingTimeInterval(400)) == 200)

        f.advance(to: 500)
        f.model.start()
        #expect(f.model.value(at: f.t0.addingTimeInterval(600)) == 100)
        #expect(f.model.pausedValue == nil)
    }

    @Test func countdownFinishesOnceThenResets() {
        let f = Fixture()
        defer { f.tearDown() }
        f.model.countdownSeconds = 300
        f.model.start()

        f.advance(to: 299)
        f.model.tick()
        #expect(f.model.isActive)
        #expect(f.messages.isEmpty)

        f.advance(to: 800)
        f.model.tick()
        #expect(f.messages == ["Timer finished"])
        #expect(f.chimeCount == 1)
        #expect(!f.model.isActive)
        #expect(f.model.value(at: f.clock.now) == 300)

        f.model.tick()
        #expect(f.messages.count == 1)
    }

    @Test func valueNeverGoesBelowZero() {
        let f = Fixture()
        defer { f.tearDown() }
        f.model.countdownSeconds = 60
        f.model.start()
        #expect(f.model.value(at: f.t0.addingTimeInterval(1000)) == 0)
    }

    @Test func stopwatchCountsUpAcrossPauses() {
        let f = Fixture()
        defer { f.tearDown() }
        f.model.mode = .stopwatch
        f.model.start()
        #expect(f.model.value(at: f.t0.addingTimeInterval(30)) == 30)

        f.advance(to: 30)
        f.model.pause()
        #expect(f.model.pausedValue == 30)
        #expect(f.model.value(at: f.t0.addingTimeInterval(90)) == 30)

        f.advance(to: 100)
        f.model.start()
        #expect(f.model.value(at: f.t0.addingTimeInterval(110)) == 40)
    }

    @Test func pomodoroAlternatesWorkAndRestAndCountsFinishedWork() {
        let f = Fixture()
        defer { f.tearDown() }
        f.model.mode = .pomodoro
        f.model.start()
        #expect(f.model.anchor == f.t0.addingTimeInterval(25 * 60))

        f.advance(to: 25 * 60)
        f.model.tick()
        #expect(f.model.phase == .rest)
        #expect(f.model.completedPomodoros == 1)
        #expect(f.model.anchor == f.t0.addingTimeInterval(25 * 60 + 5 * 60))
        #expect(f.messages == ["Time for a break"])

        f.advance(to: 30 * 60)
        f.model.tick()
        #expect(f.model.phase == .work)
        #expect(f.model.completedPomodoros == 1)
        #expect(f.model.anchor == f.t0.addingTimeInterval(55 * 60))
        #expect(f.messages == ["Time for a break", "Back to work"])
        #expect(f.chimeCount == 2)
    }

    @Test func switchingModeResetsARunningTimer() {
        let f = Fixture()
        defer { f.tearDown() }
        f.model.start()
        f.model.mode = .pomodoro
        #expect(!f.model.isActive)
        #expect(f.model.phase == .work)
    }

    @Test func lengthStepsSnapToWholeMinutes() {
        let f = Fixture()
        defer { f.tearDown() }
        f.model.countdownSeconds = 90
        f.model.adjustLength(byMinutes: 1)
        #expect(f.model.countdownSeconds == 120)
        f.model.countdownSeconds = 90
        f.model.adjustLength(byMinutes: -1)
        #expect(f.model.countdownSeconds == 60)
        f.model.adjustLength(byMinutes: -1)
        #expect(f.model.countdownSeconds == 60)
        f.model.countdownSeconds = TimerModel.maxCountdown
        f.model.adjustLength(byMinutes: 1)
        #expect(f.model.countdownSeconds == TimerModel.maxCountdown)
    }

    @Test func pomodoroLengthsStayWithinTheirLimits() {
        let f = Fixture()
        defer { f.tearDown() }
        f.model.mode = .pomodoro
        f.model.workMinutes = 180
        f.model.adjustLength(byMinutes: 1)
        #expect(f.model.workMinutes == 180)
        f.model.workMinutes = 1
        f.model.adjustLength(byMinutes: -1)
        #expect(f.model.workMinutes == 1)
        f.model.selectPhase(.rest)
        f.model.restMinutes = 60
        f.model.adjustLength(byMinutes: 1)
        #expect(f.model.restMinutes == 60)
        f.model.adjustLength(byMinutes: -1)
        #expect(f.model.restMinutes == 59)
    }

    @Test func lengthCannotBeChangedWhileRunning() {
        let f = Fixture()
        defer { f.tearDown() }
        f.model.countdownSeconds = 300
        f.model.start()
        f.model.adjustLength(byMinutes: 1)
        #expect(f.model.countdownSeconds == 300)
        #expect(!f.model.setLength(from: "10"))
        #expect(f.model.countdownSeconds == 300)
    }

    @Test func typedLengthsAreParsedCappedAndRounded() {
        let f = Fixture()
        defer { f.tearDown() }
        #expect(f.model.setLength(from: "1:30"))
        #expect(f.model.countdownSeconds == 90)
        #expect(f.model.setLength(from: "2000"))
        #expect(f.model.countdownSeconds == TimerModel.maxCountdown)
        #expect(!f.model.setLength(from: "0"))
        #expect(!f.model.setLength(from: "abc"))
        #expect(f.model.countdownSeconds == TimerModel.maxCountdown)

        f.model.mode = .pomodoro
        #expect(f.model.setLength(from: "0:20"))
        #expect(f.model.workMinutes == 1)
        #expect(f.model.setLength(from: "999"))
        #expect(f.model.workMinutes == 180)
        f.model.selectPhase(.rest)
        #expect(f.model.setLength(from: "999"))
        #expect(f.model.restMinutes == 60)
        #expect(f.model.setLength(from: "1:30"))
        #expect(f.model.restMinutes == 2)
    }

    @Test func stopwatchHasNoLengthToEdit() {
        let f = Fixture()
        defer { f.tearDown() }
        f.model.mode = .stopwatch
        #expect(!f.model.canEditLength)
        #expect(!f.model.setLength(from: "5"))
    }

    @Test func lengthsAreSavedAndLoadedAgain() {
        let f = Fixture()
        defer { f.tearDown() }
        f.model.countdownSeconds = 450
        f.model.workMinutes = 40
        f.model.restMinutes = 10
        let again = TimerModel(defaults: f.defaults)
        #expect(again.countdownSeconds == 450)
        #expect(again.workMinutes == 40)
        #expect(again.restMinutes == 10)
    }

    @Test func aFreshProfileGetsTheDefaultLengths() {
        let f = Fixture()
        defer { f.tearDown() }
        #expect(f.model.countdownSeconds == 300)
        #expect(f.model.workMinutes == 25)
        #expect(f.model.restMinutes == 5)
    }

    @Test(arguments: [(3599.9, "59:59"), (3600.0, "1:00:00"), (0.4, "0:00"), (65.0, "1:05"), (3725.0, "1:02:05")])
    func formatsMinutesAndHours(seconds: Double, expected: String) {
        #expect(TimerModel.format(seconds) == expected)
    }

    @Test(arguments: [60, 90, 3600, 5430])
    func lengthTextReadsBackAsTheSameLength(seconds: Int) {
        let text = seconds % 60 == 0 ? "\(seconds / 60)" : TimerModel.format(TimeInterval(seconds))
        #expect(TimerModel.parseLength(text) == seconds)
    }
}
