import Foundation
import Testing
@testable import Nunsseop

/// A Mac's two radios, kept in memory. `accepts` false makes macOS refuse a switch.
private final class FakeRadios: @unchecked Sendable {
    private let lock = NSLock()
    private var wifi: Bool?
    private var bluetooth: Bool?
    private var accepts: Bool

    init(wifi: Bool? = true, bluetooth: Bool? = false, accepts: Bool = true) {
        self.wifi = wifi
        self.bluetooth = bluetooth
        self.accepts = accepts
    }

    var state: (wifi: Bool?, bluetooth: Bool?) { lock.withLock { (wifi, bluetooth) } }

    var control: WirelessControl {
        WirelessControl(
            wifiPower: { self.lock.withLock { self.wifi } },
            setWifiPower: { on in self.lock.withLock { if self.accepts { self.wifi = on }; return self.accepts } },
            bluetoothPower: { self.lock.withLock { self.bluetooth } },
            setBluetoothPower: { on in self.lock.withLock { if self.accepts { self.bluetooth = on }; return self.accepts } })
    }
}

@MainActor
struct ToolsWirelessTests {
    @Test func bluetoothIsOnWhenTheControllerSaysSo() {
        func json(_ state: String) -> Data {
            Data(#"{"SPBluetoothDataType":[{"controller_properties":{"controller_state":"\#(state)"}}]}"#.utf8)
        }
        #expect(BluetoothPower.isOn(in: json("attrib_on")) == true)
        #expect(BluetoothPower.isOn(in: json("attrib_off")) == false)
        #expect(BluetoothPower.isOn(in: Data(#"{"SPBluetoothDataType":[{}]}"#.utf8)) == nil)
        #expect(BluetoothPower.isOn(in: Data("not json".utf8)) == nil)
    }

    @Test func aBluetoothSwitchThatTheRadioIgnoredGoesBackAfterTheSettleTime() async {
        let radios = FakeRadios(wifi: true, bluetooth: false)
        let tools = ToolsModel(mountedDrives: { [] }, wireless: WirelessControl(
            wifiPower: { true }, setWifiPower: { _ in true },
            bluetoothPower: { radios.state.bluetooth },
            setBluetoothPower: { _ in true }),  // accepted, but access was denied: the radio stays as it was
            bluetoothSettle: 0.05)
        tools.refreshWireless()
        await eventually { tools.bluetoothOn != nil }
        tools.setBluetooth(true)
        #expect(tools.bluetoothOn == true)
        await eventually { tools.bluetoothOn == false }
        #expect(tools.bluetoothOn == false)
    }

    private func model(_ radios: FakeRadios) -> ToolsModel {
        ToolsModel(mountedDrives: { [] }, wireless: radios.control, bluetoothSettle: 0.05)
    }

    @Test func nothingIsReadUntilTheTabAsks() async {
        let tools = model(FakeRadios())
        #expect(tools.wifiOn == nil)
        #expect(tools.bluetoothOn == nil)
        tools.refreshWireless()
        await eventually { tools.wifiOn != nil && tools.bluetoothOn != nil }
        #expect(tools.wifiOn == true)
        #expect(tools.bluetoothOn == false)
    }

    @Test func aSwitchShowsAtOnceAndReachesTheRadio() async {
        let radios = FakeRadios(wifi: true, bluetooth: false)
        let tools = model(radios)
        tools.refreshWireless()
        await eventually { tools.wifiOn != nil }
        tools.setWifi(false)
        tools.setBluetooth(true)
        #expect(tools.wifiOn == false)
        #expect(tools.bluetoothOn == true)
        await eventually { radios.state.wifi == false && radios.state.bluetooth == true }
        #expect(radios.state.wifi == false)
        #expect(radios.state.bluetooth == true)
    }

    @Test func aRefusedSwitchGoesBackToWhatTheRadioIs() async {
        let radios = FakeRadios(wifi: true, bluetooth: false, accepts: false)
        let tools = model(radios)
        tools.refreshWireless()
        await eventually { tools.wifiOn != nil }
        tools.setWifi(false)
        #expect(tools.wifiOn == false)
        await eventually { tools.wifiOn == true }
        #expect(tools.wifiOn == true)
    }

    @Test func aMacWithoutTheRadioHasNoSwitchAndNothingIsSent() async {
        let radios = FakeRadios(wifi: nil, bluetooth: nil)
        let tools = model(radios)
        tools.refreshWireless()
        await eventually(within: 0.3) { false }
        #expect(tools.wifiOn == nil)
        #expect(tools.bluetoothOn == nil)
        tools.setWifi(true)
        tools.setBluetooth(true)
        #expect(tools.wifiOn == nil)
        #expect(tools.bluetoothOn == nil)
        #expect(radios.state.wifi == nil)
    }
}
