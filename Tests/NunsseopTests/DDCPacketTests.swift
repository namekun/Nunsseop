import IOKit.ps
import Testing
@testable import Nunsseop

struct DDCPacketTests {
    // Checksums are 0x6E ^ 0x51 ^ every byte of the packet.
    @Test func requestAsksForBrightness() {
        #expect(ExternalBrightness.requestPacket() == [0x82, 0x01, 0x10, 0xAC])
    }

    @Test func setPacketCarriesValueAndChecksum() {
        #expect(ExternalBrightness.setPacket(50) == [0x84, 0x03, 0x10, 0x00, 0x32, 0x9A])
        #expect(ExternalBrightness.setPacket(100) == [0x84, 0x03, 0x10, 0x00, 0x64, 0xCC])
    }

    @Test func setPacketClampsToSixteenBits() {
        #expect(ExternalBrightness.setPacket(70000) == [0x84, 0x03, 0x10, 0xFF, 0xFF, 0xA8])
        #expect(ExternalBrightness.setPacket(-5) == [0x84, 0x03, 0x10, 0x00, 0x00, 0xA8])
    }

    private func reply(maxHigh: UInt8 = 0x00, maxLow: UInt8 = 0x64, header: [UInt8] = [0x02, 0x00, 0x10]) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 12)
        bytes.replaceSubrange(2..<5, with: header)
        bytes[6] = maxHigh
        bytes[7] = maxLow
        bytes[8] = 0x00
        bytes[9] = 0x32
        return bytes
    }

    @Test func parsesCurrentAndMaximum() {
        let level = ExternalBrightness.parseLevel(reply())
        #expect(level?.current == 50)
        #expect(level?.max == 100)
        let wide = ExternalBrightness.parseLevel(reply(maxHigh: 0x01, maxLow: 0x2C))
        #expect(wide?.max == 300)
    }

    @Test func missingMaximumFallsBackToHundred() {
        #expect(ExternalBrightness.parseLevel(reply(maxHigh: 0, maxLow: 0))?.max == 100)
    }

    @Test func ignoresRepliesToOtherRequests() {
        #expect(ExternalBrightness.parseLevel(reply(header: [0x00, 0x00, 0x10])) == nil)
        #expect(ExternalBrightness.parseLevel(reply(header: [0x02, 0x01, 0x10])) == nil)
        #expect(ExternalBrightness.parseLevel(reply(header: [0x02, 0x00, 0x12])) == nil)
        #expect(ExternalBrightness.parseLevel([0x02, 0x00, 0x10]) == nil)
    }
}

struct PowerStateTests {
    private func description(current: Int?, max: Int?, charging: Bool = false, state: String = kIOPSBatteryPowerValue,
                             type: String = kIOPSInternalBatteryType) -> [String: Any] {
        var desc: [String: Any] = [kIOPSTypeKey: type, kIOPSIsChargingKey: charging, kIOPSPowerSourceStateKey: state]
        if let current { desc[kIOPSCurrentCapacityKey] = current }
        if let max { desc[kIOPSMaxCapacityKey] = max }
        return desc
    }

    @Test func scalesCapacityToPercent() {
        #expect(PowerMonitor.state(from: description(current: 4000, max: 5000, charging: true, state: kIOPSACPowerValue))
            == PowerState(percent: 80, isCharging: true, onAC: true))
        #expect(PowerMonitor.state(from: description(current: 55, max: 100))
            == PowerState(percent: 55, isCharging: false, onAC: false))
    }

    @Test func zeroOrMissingMaximumUsesCurrentAsPercent() {
        #expect(PowerMonitor.state(from: description(current: 42, max: 0))?.percent == 42)
        #expect(PowerMonitor.state(from: description(current: 42, max: nil))?.percent == 42)
    }

    @Test func onlyTheInternalBatteryCounts() {
        #expect(PowerMonitor.state(from: description(current: 50, max: 100, type: "UPS")) == nil)
        #expect(PowerMonitor.state(from: [:]) == nil)
    }
}
