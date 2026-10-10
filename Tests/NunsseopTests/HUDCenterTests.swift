import Testing
@testable import Nunsseop

struct HUDPowerEventTests {
    private func state(_ percent: Int, onAC: Bool, charging: Bool? = nil) -> PowerState {
        PowerState(percent: percent, isCharging: charging ?? onAC, onAC: onAC)
    }

    private func event(from previous: PowerState?, to next: PowerState, chargingHUD: Bool = true,
                       alerts: Bool = true) -> (event: HUDEvent, duration: Double)? {
        HUDCenter.powerEvent(previous: previous, state: next, chargingHUD: chargingHUD, batteryAlerts: alerts)
    }

    private let batteryLow = HUDEvent.notice(symbol: "battery.25percent", title: "Battery low", detail: "20%")
    private let fullyCharged = HUDEvent.notice(symbol: "battery.100percent.bolt", title: "Fully charged", detail: nil)

    @Test func pluggingInAndUnpluggingShowTheChargingHUD() {
        let plugged = state(60, onAC: true)
        let result = event(from: state(60, onAC: false), to: plugged)
        #expect(result?.event == .power(plugged))
        #expect(result?.duration == 2.5)

        let unplugged = state(60, onAC: false)
        #expect(event(from: plugged, to: unplugged)?.event == .power(unplugged))
    }

    @Test func pluggingInWithTheChargingHUDOffShowsNothingBelowFull() {
        #expect(event(from: state(60, onAC: false), to: state(60, onAC: true), chargingHUD: false) == nil)
    }

    @Test func crossingTwentyPercentOnBatteryWarnsOnce() {
        let result = event(from: state(21, onAC: false), to: state(20, onAC: false))
        #expect(result?.event == batteryLow)
        #expect(result?.duration == 5)
        #expect(event(from: state(20, onAC: false), to: state(19, onAC: false)) == nil)
        #expect(event(from: state(30, onAC: false), to: state(25, onAC: false)) == nil)
    }

    @Test func theLowBatteryWarningCanBeTurnedOff() {
        #expect(event(from: state(21, onAC: false), to: state(20, onAC: false), alerts: false) == nil)
    }

    @Test func noLowBatteryWarningWhileCharging() {
        #expect(event(from: state(21, onAC: true), to: state(19, onAC: true)) == nil)
    }

    @Test func aWarningIsGivenWhenTheDropComesInOneBigStep() {
        #expect(event(from: state(25, onAC: false), to: state(18, onAC: false))?.event
                == .notice(symbol: "battery.25percent", title: "Battery low", detail: "18%"))
    }

    @Test func reachingFullOnPowerAnnouncesItOnce() {
        let result = event(from: state(99, onAC: true), to: state(100, onAC: true))
        #expect(result?.event == fullyCharged)
        #expect(result?.duration == 4)
        #expect(event(from: state(100, onAC: true), to: state(100, onAC: true, charging: false)) == nil)
    }

    @Test func noFullChargeNoticeOffPowerOrWithAlertsOff() {
        #expect(event(from: state(99, onAC: false), to: state(100, onAC: false)) == nil)
        #expect(event(from: state(99, onAC: true), to: state(100, onAC: true), alerts: false) == nil)
    }

    @Test func unpluggingAtLowChargeWithTheChargingHUDOffGivesNoWarning() {
        #expect(event(from: state(15, onAC: true), to: state(15, onAC: false), chargingHUD: false) == nil)
    }

    @Test func theChargingHUDTakesThePlaceOfTheBatteryNoticeWhenPowerChanges() {
        let unplugged = state(20, onAC: false)
        #expect(event(from: state(21, onAC: true), to: unplugged)?.event == .power(unplugged))
        #expect(event(from: state(21, onAC: true), to: unplugged, chargingHUD: false)?.event == batteryLow)
    }

    @Test func withoutAnEarlierReadingOnlyTheChargingHUDCanShow() {
        #expect(event(from: nil, to: state(15, onAC: false), chargingHUD: false) == nil)
    }
}

struct HUDKeyboardLevelTests {
    @Test func upAndDownStepWithinZeroAndOne() {
        #expect(HUDCenter.keyboardLevel(for: .keyboardUp, level: 0.5, last: 0.5, step: 1.0 / 16) == 0.5625)
        #expect(HUDCenter.keyboardLevel(for: .keyboardUp, level: 0.5, last: 0.5, step: 1.0 / 64) == 0.515625)
        #expect(HUDCenter.keyboardLevel(for: .keyboardUp, level: 0.98, last: 0.5, step: 1.0 / 16) == 1)
        #expect(HUDCenter.keyboardLevel(for: .keyboardDown, level: 0.03, last: 0.5, step: 1.0 / 16) == 0)
        #expect(HUDCenter.keyboardLevel(for: .keyboardDown, level: 0.5, last: 0.5, step: 1.0 / 16) == 0.4375)
    }

    @Test func theToggleSwitchesOffAndRestoresTheLastLevel() {
        #expect(HUDCenter.keyboardLevel(for: .keyboardToggle, level: 0.8, last: 0.5, step: 1.0 / 16) == 0)
        #expect(HUDCenter.keyboardLevel(for: .keyboardToggle, level: 0, last: 0.8, step: 1.0 / 16) == 0.8)
    }
}

struct HUDExternalBrightnessTargetTests {
    @Test(arguments: [(0, 1, true), (1, 1, true), (2, 1, false), (1, 2, false), (0, 0, false), (1, 0, false), (3, 2, false)])
    func onlyOneAnsweringDisplayWithAtMostOneExternalScreenIsDriven(screens: Int, ddc: Int, driven: Bool) {
        let displays = Array(100..<(100 + ddc))
        let target = HUDCenter.externalBrightnessTarget(externalScreenCount: screens, ddcDisplays: displays)
        #expect((target != nil) == driven)
        if driven { #expect(target == 100) }
    }
}
