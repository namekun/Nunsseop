import AppKit
import ApplicationServices
import CoreGraphics

/// Built-in display brightness through the DisplayServices private framework.
enum BuiltInBrightness {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    private static let getFn = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetFn.self) }
    private static let setFn = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetFn.self) }

    static var builtInDisplay: CGDirectDisplayID? {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.first { CGDisplayIsBuiltin($0) != 0 }
    }

    static var isAvailable: Bool { getFn != nil && setFn != nil && builtInDisplay != nil }

    static var level: Float? {
        guard let getFn, let display = builtInDisplay else { return nil }
        var value: Float = 0
        return getFn(display, &value) == 0 ? value : nil
    }

    static func set(_ value: Float) {
        guard let setFn, let display = builtInDisplay else { return }
        _ = setFn(display, min(1, max(0, value)))
    }
}

enum MediaKey {
    case volumeUp, volumeDown, mute, brightnessUp, brightnessDown
    case keyboardUp, keyboardDown, keyboardToggle
}

/// Swallows the hardware volume/brightness keys so the system HUD does not
/// appear, and reports them instead. Needs Accessibility permission.
final class MediaKeyInterceptor {
    /// Called on the main queue. `fine` is true when Option+Shift is held.
    var onKey: ((MediaKey, _ fine: Bool) -> Void)?
    /// Keys are only taken while these return true; otherwise the system handles them.
    var handlesVolume: () -> Bool = { false }
    var handlesBrightness: () -> Bool = { false }
    var handlesKeyboard: () -> Bool = { false }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << 14)  // NSEvent.EventType.systemDefined
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<MediaKeyInterceptor>.fromOpaque(info).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    static func decode(data1: Int) -> (code: Int, isDown: Bool) {
        ((data1 & 0xFFFF_0000) >> 16, ((data1 & 0xFF00) >> 8) == 0xA)
    }

    static func key(forCode code: Int, volume: () -> Bool, brightness: () -> Bool, keyboard: () -> Bool) -> MediaKey? {
        switch code {
        case 0 where volume(): return .volumeUp
        case 1 where volume(): return .volumeDown
        case 7 where volume(): return .mute
        case 2 where brightness(): return .brightnessUp
        case 3 where brightness(): return .brightnessDown
        case 21 where keyboard(): return .keyboardUp
        case 22 where keyboard(): return .keyboardDown
        case 23 where keyboard(): return .keyboardToggle
        default: return nil
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }
        let (code, isDown) = Self.decode(data1: ns.data1)
        guard let key = Self.key(forCode: code, volume: handlesVolume, brightness: handlesBrightness, keyboard: handlesKeyboard) else {
            return Unmanaged.passUnretained(event)
        }
        if isDown {
            let fine = ns.modifierFlags.contains([.option, .shift])
            DispatchQueue.main.async { self.onKey?(key, fine) }
        }
        return nil
    }
}
