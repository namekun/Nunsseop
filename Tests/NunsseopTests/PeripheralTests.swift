import Foundation
import Testing
@testable import Nunsseop

@MainActor
struct PrivacyEdgeTests {
    private final class Calls {
        var list: [(camera: Bool, mic: Bool)] = []
    }

    private func monitor() -> (PrivacyMonitor, Calls) {
        let monitor = PrivacyMonitor()
        let calls = Calls()
        monitor.onChange = { calls.list.append(($0, $1)) }
        return (monitor, calls)
    }

    @Test func announcesOnlyWhatJustStarted() {
        let (monitor, calls) = monitor()
        monitor.apply(camera: false, mic: false)
        #expect(calls.list.isEmpty)
        monitor.apply(camera: true, mic: false)
        #expect(calls.list.map(\.camera) == [true] && calls.list.map(\.mic) == [false])
        monitor.apply(camera: true, mic: true)
        #expect(calls.list.count == 2)
        #expect(calls.list[1].camera == false && calls.list[1].mic == true)
        monitor.apply(camera: true, mic: true)
        #expect(calls.list.count == 2)
    }

    @Test func stoppingIsSilentAndRearmsTheEdge() {
        let (monitor, calls) = monitor()
        monitor.apply(camera: true, mic: true)
        monitor.apply(camera: false, mic: true)
        monitor.apply(camera: false, mic: false)
        #expect(calls.list.count == 1)
        #expect(!monitor.cameraInUse && !monitor.micInUse)
        monitor.apply(camera: true, mic: false)
        #expect(calls.list.count == 2)
        #expect(calls.list[1].camera == true && calls.list[1].mic == false)
    }

    @Test func keepingStateOnStopStaysQuietWhenRestarted() {
        let (monitor, calls) = monitor()
        monitor.apply(camera: true, mic: false)
        monitor.stop(clearing: false)
        #expect(monitor.cameraInUse)
        monitor.apply(camera: true, mic: false)
        #expect(calls.list.count == 1)
        monitor.stop()
        #expect(!monitor.cameraInUse && !monitor.micInUse)
    }
}

struct PeripheralBatteryTests {
    private func battery(_ name: String, _ percent: Int) -> PeripheralBattery {
        PeripheralBattery(name: name, percent: percent, kind: .mouse)
    }

    @Test func warnsOnceAtFifteenPercent() {
        var warned: Set<String> = []
        var result = PeripheralMonitor.lowBattery(found: [battery("Mouse", 16)], warned: warned)
        #expect(result.toWarn.isEmpty && result.warned.isEmpty)
        result = PeripheralMonitor.lowBattery(found: [battery("Mouse", 15)], warned: warned)
        #expect(result.toWarn.map(\.name) == ["Mouse"])
        warned = result.warned
        #expect(warned == ["Mouse"])
        result = PeripheralMonitor.lowBattery(found: [battery("Mouse", 14)], warned: warned)
        #expect(result.toWarn.isEmpty)
        #expect(result.warned == ["Mouse"])
    }

    @Test func warnsAgainAfterRecharging() {
        var result = PeripheralMonitor.lowBattery(found: [battery("Mouse", 10)], warned: [])
        result = PeripheralMonitor.lowBattery(found: [battery("Mouse", 40)], warned: result.warned)
        #expect(result.toWarn.isEmpty && result.warned.isEmpty)
        result = PeripheralMonitor.lowBattery(found: [battery("Mouse", 10)], warned: result.warned)
        #expect(result.toWarn.map(\.name) == ["Mouse"])
    }

    @Test func warnsForEachLowDeviceOnce() {
        let result = PeripheralMonitor.lowBattery(found: [battery("A", 5), battery("B", 80), battery("C", 1)], warned: ["A"])
        #expect(result.toWarn.map(\.name) == ["C"])
        #expect(result.warned == ["A", "C"])
    }

    @Test(arguments: [
        ("Magic Trackpad", nil, PeripheralBattery.Kind.trackpad), ("Magic Mouse", nil, .mouse), ("MX Master 3", nil, .mouse),
        ("MX Keys", nil, .keyboard), ("Keychron K2", nil, .keyboard), ("Foo", "Gamepad", .other), ("Foo", "Keyboard", .keyboard),
    ] as [(String, String?, PeripheralBattery.Kind)])
    func classifiesDevices(name: String, type: String?, kind: PeripheralBattery.Kind) {
        #expect(PeripheralMonitor.kind(for: name, type: type) == kind)
    }

    @Test func readsBluetoothMainBattery() {
        let keyboard = PeripheralMonitor.bluetoothBattery(name: "Keychron K2", info: [
            "device_minorType": "Keyboard", "device_batteryLevelMain": "85%",
        ])
        #expect(keyboard == PeripheralBattery(name: "Keychron K2", percent: 85, kind: .keyboard))
        #expect(PeripheralMonitor.bluetoothBattery(name: "Pad", info: ["device_batteryLevelMain": "85"])?.percent == 85)
    }

    @Test func skipsHeadphonesAndDevicesWithoutALevel() {
        #expect(PeripheralMonitor.bluetoothBattery(name: "Buds", info: ["device_minorType": "Headphones", "device_batteryLevelMain": "85%"]) == nil)
        #expect(PeripheralMonitor.bluetoothBattery(name: "Headset", info: ["device_minorType": "Headset", "device_batteryLevelMain": "85%"]) == nil)
        #expect(PeripheralMonitor.bluetoothBattery(name: "Mouse", info: ["device_minorType": "Mouse"]) == nil)
        #expect(PeripheralMonitor.bluetoothBattery(name: "Mouse", info: ["device_batteryLevelMain": "n/a"]) == nil)
    }
}
