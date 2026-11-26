import AppKit
import CoreAudio
import IOKit.pwr_mgt
import SwiftUI

/// Output device switching, microphone mute, keep-awake, drive ejection, color picking and text capture.
@MainActor
final class ToolsModel: ObservableObject {
    struct AudioDevice: Identifiable, Hashable {
        let id: AudioDeviceID
        let name: String
    }

    struct Drive: Identifiable, Hashable {
        let id: URL
        let name: String
    }

    @Published private(set) var outputs: [AudioDevice] = []
    @Published private(set) var currentOutput: AudioDeviceID = 0
    @Published private(set) var micMuted = false
    @Published private(set) var keepAwake = false
    /// Nil when this Mac has no such radio.
    @Published private(set) var wifiOn: Bool?
    @Published private(set) var bluetoothOn: Bool?
    @Published private(set) var drives: [Drive] = []
    @Published private(set) var ejectError: String?
    /// Hex codes of recently picked colors, newest first.
    @Published private(set) var pickedColors: [String] = []
    @Published private(set) var isCapturingText = false
    /// Confirms a copy in the notch: symbol, title, detail.
    var onNotice: ((String, String, String?) -> Void)?

    private var assertionID: IOPMAssertionID = 0
    private var observers: [NSObjectProtocol] = []
    private let mountedDrives: () -> [Drive]
    private let wireless: WirelessControl
    private let bluetoothSettle: TimeInterval

    init(mountedDrives: @escaping () -> [Drive] = ToolsModel.externalDrives, wireless: WirelessControl = .system,
         bluetoothSettle: TimeInterval = 2) {
        self.mountedDrives = mountedDrives
        self.wireless = wireless
        self.bluetoothSettle = bluetoothSettle
    }

    func start() {
        refreshAudio()
        refreshDrives()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshDrives() }
            })
        }
    }

    // MARK: Audio

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID {
        var address = address(selector)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    func refreshAudio() {
        var address = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids)
        outputs = ids.compactMap { id in
            var streams = Self.address(kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput)
            var streamSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize)
            // The per-app volume devices are only for this app.
            guard streamSize > 0, !AppVolumeModel.isOwnDevice(id) else { return nil }
            var nameAddress = Self.address(kAudioObjectPropertyName)
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name)
            return AudioDevice(id: id, name: name?.takeRetainedValue() as String? ?? "Audio device")
        }
        currentOutput = Self.defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        micMuted = inputIsMuted
    }

    func selectOutput(_ device: AudioDevice) {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = device.id
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                   UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        refreshAudio()
    }

    private var inputIsMuted: Bool {
        let input = Self.defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        var mute = Self.address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput)
        if AudioObjectHasProperty(input, &mute) {
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(input, &mute, 0, nil, &size, &value)
            if value != 0 { return true }
        }
        return Self.volumeMute(for: input)?.isMuted ?? false
    }

    /// Uses the device's mute switch when it has one, otherwise drops input volume to zero.
    func toggleMic() {
        let input = Self.defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        let muting = !inputIsMuted
        var mute = Self.address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput)
        var settable: DarwinBoolean = false
        if AudioObjectHasProperty(input, &mute),
           AudioObjectIsPropertySettable(input, &mute, &settable) == noErr, settable.boolValue {
            var value: UInt32 = muting ? 1 : 0
            AudioObjectSetPropertyData(input, &mute, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        } else if let fallback = Self.volumeMute(for: input) {
            if muting { fallback.mute() } else { fallback.unmute() }
        }
        micMuted = inputIsMuted
    }

    /// The zero-volume mute for inputs without a mute switch. The volume before muting is kept in
    /// UserDefaults by device, so the mute lasts across relaunches until the user unmutes.
    struct VolumeMute {
        var volume: () -> Float32?
        /// Returns false when the device refused the volume.
        var setVolume: (Float32) -> Bool
        var saved: () -> Float32?
        var setSaved: (Float32?) -> Void

        var isMuted: Bool { volume() == 0 && saved() != nil }

        func mute() {
            guard let current = volume() else { return }
            let previous = saved()
            // A volume already at zero under a saved one is this mute, so keep the volume saved before it.
            if current > 0 || previous == nil { setSaved(current) }
            if !setVolume(0) { setSaved(previous) }
        }

        func unmute() {
            // If the user raised the volume meanwhile, it stays; only the saved value goes.
            if let restore = saved(), volume() == 0, !setVolume(restore) { return }
            setSaved(nil)
        }
    }

    private static func volumeMute(for device: AudioDeviceID) -> VolumeMute? {
        guard let uid = uid(of: device) else { return nil }
        return VolumeMute(volume: { inputVolume(of: device) },
                          setVolume: { setInputVolume($0, of: device) },
                          saved: { savedInputVolume(for: uid) },
                          setSaved: { setSavedInputVolume($0, for: uid) })
    }

    private static let savedInputVolumesKey = "savedInputVolumes"

    static func savedInputVolumes(_ defaults: UserDefaults = .standard) -> [String: Float32] {
        (defaults.dictionary(forKey: savedInputVolumesKey) as? [String: NSNumber] ?? [:]).mapValues(\.floatValue)
    }

    static func savedInputVolume(for uid: String, defaults: UserDefaults = .standard) -> Float32? {
        savedInputVolumes(defaults)[uid]
    }

    static func setSavedInputVolume(_ volume: Float32?, for uid: String, defaults: UserDefaults = .standard) {
        var saved = savedInputVolumes(defaults)
        saved[uid] = volume
        if saved.isEmpty {
            defaults.removeObject(forKey: savedInputVolumesKey)
        } else {
            defaults.set(saved.mapValues { NSNumber(value: $0) }, forKey: savedInputVolumesKey)
        }
    }

    private static func uid(of device: AudioDeviceID) -> String? {
        var address = address(kAudioDevicePropertyDeviceUID)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard device != 0, AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }

    private static func inputVolume(of device: AudioDeviceID) -> Float32? {
        var address = address(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeInput)
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else { return nil }
        return volume
    }

    private static func setInputVolume(_ volume: Float32, of device: AudioDeviceID) -> Bool {
        var address = address(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeInput)
        var volume = volume
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume) == noErr
    }

    // MARK: Wi-Fi and Bluetooth

    /// Read when the Tools tab opens and after each switch; nothing watches them in between. Off the main thread:
    /// Bluetooth is read through `system_profiler`, which takes about a second.
    func refreshWireless() {
        let control = wireless
        DispatchQueue.global(qos: .userInitiated).async {
            let (wifi, bluetooth) = (control.wifiPower(), control.bluetoothPower())
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.wifiOn = wifi; self.bluetoothOn = bluetooth }
            }
        }
    }

    func setWifi(_ on: Bool) {
        guard wifiOn != nil else { return }
        wifiOn = on
        let set = wireless.setWifiPower
        flip(settle: 0) { set(on) }
    }

    func setBluetooth(_ on: Bool) {
        guard bluetoothOn != nil else { return }
        bluetoothOn = on
        let set = wireless.setBluetoothPower
        flip(settle: bluetoothSettle) { set(on) }
    }

    /// Flips a radio off the main thread (macOS can take a moment). The switch shows the new state at once, and
    /// `settle` seconds after the flip it shows what the radio really is, which puts it back when macOS refused
    /// (Bluetooth can refuse without saying so, when its access was denied).
    private func flip(settle: TimeInterval, _ work: @escaping @Sendable () -> Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            let accepted = work()
            guard !accepted || settle > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + (accepted ? settle : 0)) {
                MainActor.assumeIsolated { self.refreshWireless() }
            }
        }
    }

    // MARK: Keep awake

    func toggleKeepAwake() {
        if keepAwake {
            IOPMAssertionRelease(assertionID)
            keepAwake = false
        } else {
            let ok = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Nunsseop keep awake" as CFString, &assertionID)
            keepAwake = ok == kIOReturnSuccess
        }
    }

    // MARK: Color picker

    func pickColor() {
        NSColorSampler().show { [weak self] color in
            guard let color = color?.usingColorSpace(.sRGB) else { return }
            let channel = { (value: CGFloat) in Int((min(1, max(0, value)) * 255).rounded()) }
            let hex = String(format: "#%02X%02X%02X", channel(color.redComponent), channel(color.greenComponent),
                             channel(color.blueComponent))
            Task { @MainActor in self?.copyColor(hex) }
        }
    }

    func copyColor(_ hex: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hex, forType: .string)
        pickedColors.removeAll { $0 == hex }
        pickedColors.insert(hex, at: 0)
        if pickedColors.count > 5 { pickedColors.removeLast(pickedColors.count - 5) }
        onNotice?("eyedropper", String(localized: "Copied \(hex)"), nil)
    }

    // MARK: Text capture

    /// Lets the user select a screen region, reads its text and copies it. Cancelling does nothing.
    func captureText() {
        guard !isCapturingText else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nunsseop-text-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.global(qos: .userInitiated).async {
                let captured = FileManager.default.fileExists(atPath: url.path)
                let text = captured ? TextRecognizer.recognize(imageAt: url) : ""
                try? FileManager.default.removeItem(at: url)
                DispatchQueue.main.async { self?.finishCapture(text, captured: captured) }
            }
        }
        do {
            try process.run()
            isCapturingText = true
        } catch {
            return
        }
    }

    private func finishCapture(_ text: String, captured: Bool) {
        isCapturingText = false
        guard captured else { return }
        guard !text.isEmpty else {
            // Without Screen Recording, other apps' windows come out blank, so nothing is read.
            if ScreenRecorder.hasPermission {
                onNotice?("text.viewfinder", String(localized: "No text found"), nil)
            } else {
                onNotice?("text.viewfinder", String(localized: "No text found"),
                          String(localized: "Allow Screen Recording to read other apps’ windows"))
                CGRequestScreenCaptureAccess()
            }
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        onNotice?("text.viewfinder", String(localized: "Text copied"), flat.count > 40 ? flat.prefix(40) + "…" : flat)
    }

    // MARK: Drives

    func refreshDrives() {
        drives = mountedDrives()
    }

    nonisolated static func externalDrives() -> [Drive] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsEjectable == true || (values.volumeIsRemovable == true && values.volumeIsInternal != true)
            else { return nil }
            return Drive(id: url, name: values.volumeName ?? url.lastPathComponent)
        }
    }

    func eject(_ drive: Drive) {
        ejectError = nil
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: drive.id)
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async { self.ejectError = message }
            }
        }
    }
}

struct ToolsTab: View {
    @ObservedObject var tools: ToolsModel
    @ObservedObject var recorder: ScreenRecorder
    let recordAudio: Bool
    /// Set while per-app volume is turned on.
    let appVolume: AppVolumeModel?

    var body: some View {
        VStack(spacing: 0) {
            PanelColumns([0, 1, 2, 3]) { column in
                switch column {
                case 0: output
                case 1: microphone
                case 2: wifi
                default: bluetooth
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            PanelHLine()
            PanelColumns([0, 1, 2, 3]) { column in
                switch column {
                case 0: keepAwake
                case 1: record
                case 2: capture
                default: drives
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .overlay(alignment: .topLeading) {
            if let appVolume { AppVolumeOverlay(model: appVolume) }
        }
        .foregroundStyle(.white)
        // The lists are read when the tab opens: a device or a drive that came after the app started is there too.
        .onAppear {
            tools.refreshAudio()
            tools.refreshWireless()
            tools.refreshDrives()
        }
    }

    private var output: some View {
        ToolPanel(symbol: "hifispeaker.fill", title: String(localized: "Output")) {
            if let appVolume { AppVolumeButton(model: appVolume) }
        } content: {
            Menu {
                ForEach(tools.outputs) { device in
                    Button {
                        tools.selectOutput(device)
                    } label: {
                        if device.id == tools.currentOutput { Label(device.name, systemImage: "checkmark") } else { Text(device.name) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text.panel(tools.outputs.first { $0.id == tools.currentOutput }?.name ?? "—", size: 14, weight: .semibold).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)).foregroundStyle(PanelInk.secondary)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
    }

    private var microphone: some View {
        ToolPanel(symbol: tools.micMuted ? "mic.slash.fill" : "mic.fill", title: String(localized: "Microphone")) {
            PanelOnOff(isOn: Binding(get: { !tools.micMuted }, set: { _ in tools.toggleMic() }), title: "Microphone")
        }
    }

    private var wifi: some View {
        ToolPanel(symbol: tools.wifiOn == false ? "wifi.slash" : "wifi", title: String(localized: "Wi-Fi")) {
            radioSwitch(tools.wifiOn, title: "Wi-Fi") { tools.setWifi($0) }
        }
    }

    private var bluetooth: some View {
        ToolPanel(symbol: "dot.radiowaves.left.and.right", title: String(localized: "Bluetooth")) {
            radioSwitch(tools.bluetoothOn, title: "Bluetooth") { tools.setBluetooth($0) }
        }
    }

    /// The switch, or a dash when this Mac has no such radio.
    @ViewBuilder
    private func radioSwitch(_ isOn: Bool?, title: LocalizedStringKey, set: @escaping (Bool) -> Void) -> some View {
        if let isOn {
            PanelOnOff(isOn: Binding(get: { isOn }, set: set), title: title)
        } else {
            Text.panel("—", size: 14, weight: .semibold)
        }
    }

    private var keepAwake: some View {
        ToolPanel(symbol: tools.keepAwake ? "cup.and.saucer.fill" : "moon.zzz.fill", title: String(localized: "Keep awake")) {
            PanelOnOff(isOn: Binding(get: { tools.keepAwake }, set: { _ in tools.toggleKeepAwake() }), title: "Keep awake")
        }
    }

    private var record: some View {
        ToolPanel(symbol: recorder.isRecording ? "stop.circle.fill" : "record.circle", title: String(localized: "Record screen")) {
            if let started = recorder.startedAt {
                HStack(spacing: 8) {
                    PanelAction(title: "Stop", symbol: "stop.fill", style: .primary) { recorder.toggle(withAudio: recordAudio) }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text.panel(TimerModel.format(context.date.timeIntervalSince(started)), size: 14, weight: .semibold, mono: true)
                    }
                }
            } else {
                PanelAction(title: ScreenRecorder.hasPermission ? "Start" : "Needs permission", symbol: "record.circle") {
                    recorder.toggle(withAudio: recordAudio)
                }
            }
        }
    }

    /// Color picker and text capture, with the recently picked colors.
    private var capture: some View {
        ToolPanel(symbol: "viewfinder", title: String(localized: "Capture")) {
            HStack(spacing: 2) {
                PanelIconButton(symbol: "eyedropper", title: String(localized: "Pick a color from the screen"), size: 13) { tools.pickColor() }
                PanelIconButton(symbol: "text.viewfinder", title: String(localized: "Capture text from the screen"), size: 13,
                                hot: tools.isCapturingText) { tools.captureText() }
                // Only as many swatches as fit, newest first.
                ViewThatFits(in: .horizontal) {
                    ForEach((0...tools.pickedColors.count).reversed(), id: \.self) { count in
                        HStack(spacing: 0) {
                            if count > 0 { PanelVLine().frame(height: 14).padding(.horizontal, 4) }
                            ForEach(tools.pickedColors.prefix(count), id: \.self) { hex in
                                Button { tools.copyColor(hex) } label: {
                                    Circle().fill(Color(hex: hex))
                                        .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1))
                                        .frame(width: 14, height: 14)
                                        .frame(width: 24, height: 24)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help(Text(hex))
                                .accessibilityLabel(Text(hex))
                            }
                        }
                    }
                }
            }
        }
    }

    private var drives: some View {
        ToolPanel(symbol: "externaldrive.fill", title: String(localized: "Drives"), height: nil) {
            if tools.drives.isEmpty {
                Text("No external drives").font(.system(size: 12)).foregroundStyle(PanelInk.hint).frame(height: 26, alignment: .leading)
            } else {
                // Many mounted volumes scroll instead of running past the notch.
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(tools.drives) { drive in
                            HStack(spacing: 4) {
                                Text.panel(drive.name, size: tools.drives.count == 1 ? 14 : 12, weight: .semibold).lineLimit(1)
                                Spacer(minLength: 0)
                                PanelIconButton(symbol: "eject.fill", title: String(localized: "Eject"), size: 11) { tools.eject(drive) }
                            }
                            .frame(height: 26)
                        }
                    }
                }
                .panelFadeBottom(tools.drives.count > 2 ? 12 : 0)
            }
            if let error = tools.ejectError {
                Text.panel(error, size: 10, opacity: 1).foregroundStyle(PanelInk.waiting).lineLimit(2)
            }
        }
    }
}

/// One cell of the grid: an icon and a label on top, what it shows or does under them, and `trailing` at the end of the label's line.
private struct ToolPanel<Trailing: View, Content: View>: View {
    let symbol: String
    let title: String
    /// The content's height; nil lets it take what the cell has left.
    var height: CGFloat? = 26
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    init(symbol: String, title: String, height: CGFloat? = 26, @ViewBuilder trailing: () -> Trailing = { EmptyView() },
         @ViewBuilder content: () -> Content) {
        self.symbol = symbol
        self.title = title
        self.height = height
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                PanelCaption(title, symbol: symbol)
                Spacer(minLength: 0)
                trailing
            }
            .frame(height: 24)
            if let height {
                content.frame(height: height, alignment: .leading)
            } else {
                content.frame(maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }
}

private extension Color {
    /// From "#RRGGBB".
    init(hex: String) {
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

/// Opens the app volume list from the Output cell.
private struct AppVolumeButton: View {
    @ObservedObject var model: AppVolumeModel

    var body: some View {
        PanelIconButton(symbol: "slider.horizontal.3", title: String(localized: "App volume"), hot: model.isShowingList || model.apps.contains { $0.volume < 1 }) {
            model.isShowingList.toggle()
        }
    }
}

/// The apps playing sound, each with a volume slider, laid over the left of the Tools tab.
private struct AppVolumeOverlay: View {
    @ObservedObject var model: AppVolumeModel
    private static let rowHeight: CGFloat = 24
    private static let rowSpacing: CGFloat = 0

    var body: some View {
        if model.isShowingList {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    PanelCaption(String(localized: "App volume"), symbol: "slider.horizontal.3")
                    Spacer()
                    PanelIconButton(symbol: "xmark", title: String(localized: "Close"), size: 10) { model.isShowingList = false }
                }
                if model.needsPermission {
                    Text("Nunsseop needs permission to record system audio to change an app’s volume.")
                        .font(.system(size: 11)).foregroundStyle(PanelInk.waiting).fixedSize(horizontal: false, vertical: true)
                    PanelAction(title: "Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } else if model.mayNeedPermission {
                    Text("No sound has come through yet. If the app is playing, Nunsseop may need permission to record system audio.")
                        .font(.system(size: 11)).foregroundStyle(PanelInk.hint).fixedSize(horizontal: false, vertical: true)
                } else if model.apps.isEmpty {
                    Text("No apps are playing sound").font(.system(size: 12)).foregroundStyle(PanelInk.hint)
                }
                if !model.apps.isEmpty {
                    // Four rows show; more scroll.
                    let shown = CGFloat(min(model.apps.count, 4))
                    ScrollView(.vertical) {
                        VStack(spacing: Self.rowSpacing) {
                            ForEach(model.apps) { app in row(app) }
                        }
                    }
                    .scrollIndicators(model.apps.count > 4 ? .automatic : .never)
                    .frame(maxHeight: shown * Self.rowHeight + (shown - 1) * Self.rowSpacing)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(width: 280, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.08)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(PanelInk.hair, lineWidth: 0.75))
        }
    }

    private func row(_ app: AppVolumeModel.App) -> some View {
        HStack(spacing: 6) {
            Image(nsImage: app.icon).resizable().frame(width: 16, height: 16).accessibilityHidden(true)
            Text.panel(app.name, size: 12).lineLimit(1).frame(width: 74, alignment: .leading)
            Slider(value: Binding(get: { app.volume }, set: { model.setVolume($0, for: app.id) }), in: 0...1) { editing in
                if !editing { model.finishEditing(app.id) }
            }
            .controlSize(.mini)
            .accessibilityLabel(Text(verbatim: app.name))
            Text.panel("\(Int((app.volume * 100).rounded()))%", size: 11, opacity: 0.65, mono: true)
                .frame(width: 32, alignment: .trailing)
        }
        .frame(height: Self.rowHeight)
    }
}
