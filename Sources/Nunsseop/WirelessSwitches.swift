import CoreWLAN
import Foundation

/// The Wi-Fi and Bluetooth power switches, as the Tools tab reads and flips them. A nil reading means
/// this Mac has no such radio (or macOS didn't answer), so the tab shows no switch for it.
/// Every closure may block, so the model calls them off the main thread.
struct WirelessControl: Sendable {
    var wifiPower: @Sendable () -> Bool?
    /// Returns false when macOS refused.
    var setWifiPower: @Sendable (Bool) -> Bool
    var bluetoothPower: @Sendable () -> Bool?
    var setBluetoothPower: @Sendable (Bool) -> Bool

    static let system = WirelessControl(
        wifiPower: { CWWiFiClient.shared().interface()?.powerOn() },
        setWifiPower: { on in
            guard let interface = CWWiFiClient.shared().interface() else { return false }
            return (try? interface.setPower(on)) != nil
        },
        bluetoothPower: { BluetoothPower.get() },
        setBluetoothPower: { BluetoothPower.set($0) })
}

/// Core Bluetooth has no way to switch the radio, so the switching uses the function System Settings itself calls from
/// IOBluetooth (`blueutil` does the same). It is looked up when needed: if a macOS version drops it, the switch does
/// nothing instead of the app failing to start. Calling it makes macOS ask for Bluetooth access the first time, so it
/// only runs when the user flips the switch; reading the state goes through `system_profiler`, which asks for nothing.
enum BluetoothPower {
    private typealias Setter = @convention(c) (Int32) -> Void

    /// Nil when this Mac has no Bluetooth controller or `system_profiler` didn't answer.
    static func get() -> Bool? {
        guard let data = BluetoothProfiler.output() else { return nil }
        return isOn(in: data)
    }

    static func isOn(in data: Data) -> Bool? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]],
              let state = controllers.lazy.compactMap({ ($0["controller_properties"] as? [String: Any])?["controller_state"] as? String }).first
        else { return nil }
        return state == "attrib_on"
    }

    /// Returns false when the function isn't there.
    static func set(_ on: Bool) -> Bool {
        guard let handle = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY),
              let pointer = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState") else { return false }
        unsafeBitCast(pointer, to: Setter.self)(on ? 1 : 0)
        return true
    }
}
