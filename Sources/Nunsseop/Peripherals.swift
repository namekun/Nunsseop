import AppKit
import CoreAudio
import CoreMediaIO
import IOKit
import os

struct PeripheralBattery: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let percent: Int
    let kind: Kind

    enum Kind { case mouse, keyboard, trackpad, other }

    var symbol: String {
        switch kind {
        case .mouse: return "computermouse.fill"
        case .keyboard: return "keyboard.fill"
        case .trackpad: return "rectangle.and.hand.point.up.left.fill"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }
}

/// Battery levels of connected mice, keyboards and trackpads.
@MainActor
final class PeripheralMonitor: ObservableObject {
    @Published private(set) var devices: [PeripheralBattery] = []
    var onLow: ((PeripheralBattery) -> Void)?

    private var timer: Timer?
    private var warned: Set<String> = []
    private var reading = false

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = 30
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard !reading else { return }
        reading = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let found = Self.read()
            DispatchQueue.main.async {
                guard let self else { return }
                self.reading = false
                self.devices = found
                let (toWarn, warned) = Self.lowBattery(found: found, warned: self.warned)
                self.warned = warned
                toWarn.forEach { self.onLow?($0) }
            }
        }
    }

    /// The devices to warn about now, and the set of devices already warned about and still low.
    nonisolated static func lowBattery(found: [PeripheralBattery], warned: Set<String>)
        -> (toWarn: [PeripheralBattery], warned: Set<String>) {
        let toWarn = found.filter { $0.percent <= 15 && !warned.contains($0.name) }
        let still = warned.union(toWarn.map(\.name))
        return (toWarn, still.filter { name in found.contains { $0.name == name && $0.percent <= 15 } })
    }

    nonisolated static func kind(for name: String, type: String?) -> PeripheralBattery.Kind {
        let text = (name + " " + (type ?? "")).lowercased()
        if text.contains("trackpad") { return .trackpad }
        if text.contains("mouse") || text.contains("mx master") || text.contains("mx vertical") || text.contains("mx anywhere") { return .mouse }
        if text.contains("keyboard") || text.contains("keys") || text.contains("keychron") { return .keyboard }
        return .other
    }

    /// Headphones have their own reading; everything else reports one main level.
    nonisolated static func bluetoothBattery(name: String, info: [String: Any]) -> PeripheralBattery? {
        let type = info["device_minorType"] as? String
        guard type != "Headphones", type != "Headset",
              let text = info["device_batteryLevelMain"] as? String,
              let percent = Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "%"))) else { return nil }
        return PeripheralBattery(name: name, percent: percent, kind: kind(for: name, type: type))
    }

    /// Apple devices report through IORegistry; others through system_profiler.
    nonisolated static func read() -> [PeripheralBattery] {
        var result: [String: PeripheralBattery] = [:]
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS {
            while case let entry = IOIteratorNext(iterator), entry != 0 {
                defer { IOObjectRelease(entry) }
                func property(_ key: String) -> Any? {
                    IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
                }
                guard let percent = property("BatteryPercent") as? Int, let name = property("Product") as? String else { continue }
                result[name] = PeripheralBattery(name: name, percent: percent, kind: kind(for: name, type: nil))
            }
            IOObjectRelease(iterator)
        }
        for (name, info) in BluetoothProfiler.connectedDevices() ?? [] where result[name] == nil {
            if let battery = bluetoothBattery(name: name, info: info) { result[name] = battery }
        }
        return result.values.sorted { $0.name < $1.name }
    }
}

/// Watches whether any app is using a camera or microphone.
@MainActor
final class PrivacyMonitor: ObservableObject {
    @Published private(set) var cameraInUse = false
    @Published private(set) var micInUse = false
    var onChange: ((_ camera: Bool, _ mic: Bool) -> Void)?

    private var timer: Timer?
    private var checking = false

    func start() {
        guard timer == nil else { return }
        // Lets CoreMediaIO see screen-capture and external devices too.
        var allow: UInt32 = 1
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &allow)
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer?.tolerance = 0.2
    }

    /// `clearing: false` keeps the last state, so starting again during a call that was already announced stays quiet.
    func stop(clearing: Bool = true) {
        timer?.invalidate()
        timer = nil
        guard clearing else { return }
        cameraInUse = false
        micInUse = false
    }

    /// Reads the devices off the main thread; the result is dropped if monitoring stopped meanwhile.
    private func check() {
        guard !checking else { return }
        checking = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let camera = Self.anyCameraRunning()
            let mic = Self.anyMicRunning()
            DispatchQueue.main.async {
                guard let self else { return }
                self.checking = false
                if self.timer != nil { self.apply(camera: camera, mic: mic) }
            }
        }
    }

    func apply(camera: Bool, mic: Bool) {
        guard camera != cameraInUse || mic != micInUse else { return }
        let startedCamera = camera && !cameraInUse
        let startedMic = mic && !micInUse
        cameraInUse = camera
        micInUse = mic
        if startedCamera || startedMic { onChange?(startedCamera, startedMic) }
    }

    nonisolated private static func anyCameraRunning() -> Bool {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == 0, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices)
        for device in devices {
            var running = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                                    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                                                    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var value: UInt32 = 0
            var valueSize: UInt32 = 0
            if CMIOObjectGetPropertyData(device, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size), &valueSize, &value) == 0, value != 0 {
                return true
            }
        }
        return false
    }

    /// The last microphone reading and the uptime it was taken at. The privacy and call monitors
    /// both poll every 2 s, so a reading under a second old is reused instead of asking CoreAudio again;
    /// how often that saves a read depends on how their timers line up.
    nonisolated private static let micReading = OSAllocatedUnfairLock<(at: TimeInterval, running: Bool)?>(initialState: nil)

    nonisolated static func anyMicRunning() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if let reading = micReading.withLock({ $0 }), now - reading.at < 1 { return reading.running }
        let running = readMicRunning()
        micReading.withLock { $0 = (now, running) }
        return running
    }

    nonisolated private static func readMicRunning() -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids)
        for id in ids {
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput,
                                                     mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize)
            // A per-app volume device takes input from its tap, not a microphone.
            guard streamSize > 0, !AppVolumeModel.isOwnDevice(id) else { continue }
            var running = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                     mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var value: UInt32 = 0
            var valueSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(id, &running, 0, nil, &valueSize, &value) == noErr, value != 0 { return true }
        }
        return false
    }
}
