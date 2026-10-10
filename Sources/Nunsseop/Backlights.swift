import AppKit
import IOKit
import ObjectiveC

/// Keyboard backlight through the CoreBrightness private framework.
enum KeyboardBacklight {
    private static let client: NSObject? = {
        _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)
        return (NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type)?.init()
    }()

    private static let keyboardID: UInt64? = {
        guard let client,
              let ids = client.perform(NSSelectorFromString("copyKeyboardBacklightIDs"))?.takeRetainedValue() as? [NSNumber]
        else { return nil }
        return ids.first?.uint64Value
    }()

    static var isAvailable: Bool { keyboardID != nil }

    static var level: Float? {
        guard let client, let keyboardID else { return nil }
        let selector = NSSelectorFromString("brightnessForKeyboard:")
        guard let imp = class_getMethodImplementation(type(of: client), selector) else { return nil }
        let fn = unsafeBitCast(imp, to: (@convention(c) (AnyObject, Selector, UInt64) -> Float).self)
        return fn(client, selector, keyboardID)
    }

    static func set(_ value: Float) {
        guard let client, let keyboardID else { return }
        let selector = NSSelectorFromString("setBrightness:forKeyboard:")
        guard let imp = class_getMethodImplementation(type(of: client), selector) else { return }
        let fn = unsafeBitCast(imp, to: (@convention(c) (AnyObject, Selector, Float, UInt64) -> Bool).self)
        _ = fn(client, selector, min(1, max(0, value)), keyboardID)
    }
}

/// External display brightness over DDC/CI (VCP code 0x10) on Apple silicon.
/// Calls block for tens of milliseconds, so use them off the main thread.
enum ExternalBrightness {
    private typealias CreateFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias I2CFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    private static let handle = dlopen(nil, RTLD_NOW)
    private static let create = dlsym(handle, "IOAVServiceCreateWithService").map { unsafeBitCast($0, to: CreateFn.self) }
    private static let write = dlsym(handle, "IOAVServiceWriteI2C").map { unsafeBitCast($0, to: I2CFn.self) }
    private static let read = dlsym(handle, "IOAVServiceReadI2C").map { unsafeBitCast($0, to: I2CFn.self) }

    private static let chipAddress: UInt32 = 0x37
    private static let dataAddress: UInt32 = 0x51

    /// AV services of displays that are not built in.
    static func services() -> [CFTypeRef] {
        guard let create else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [CFTypeRef] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            if location == "External", let service = create(kCFAllocatorDefault, entry)?.takeRetainedValue() {
                result.append(service)
            }
        }
        return result
    }

    private static func checksum(_ bytes: [UInt8]) -> UInt8 {
        bytes.reduce(UInt8(0x6E) ^ UInt8(dataAddress)) { $0 ^ $1 }
    }

    /// Current and maximum brightness, or nil if the display does not answer.
    static func level(of service: CFTypeRef) -> (current: Int, max: Int)? {
        guard let write, let read else { return nil }
        var request = requestPacket()
        var reply = [UInt8](repeating: 0, count: 12)
        for _ in 0..<3 {
            usleep(10_000)
            let wrote = request.withUnsafeMutableBytes { write(service, chipAddress, dataAddress, $0.baseAddress!, UInt32($0.count)) }
            usleep(50_000)
            let got = reply.withUnsafeMutableBytes { read(service, chipAddress, dataAddress, $0.baseAddress!, UInt32($0.count)) }
            if wrote == kIOReturnSuccess, got == kIOReturnSuccess, let level = parseLevel(reply) { return level }
        }
        return nil
    }

    static func requestPacket() -> [UInt8] {
        let request: [UInt8] = [0x82, 0x01, 0x10]
        return request + [checksum(request)]
    }

    /// Nil unless the reply answers the brightness (0x10) request.
    static func parseLevel(_ reply: [UInt8]) -> (current: Int, max: Int)? {
        guard reply.count >= 10, reply[2] == 0x02, reply[3] == 0x00, reply[4] == 0x10 else { return nil }
        let maximum = Int(reply[6]) << 8 | Int(reply[7])
        return (Int(reply[8]) << 8 | Int(reply[9]), maximum > 0 ? maximum : 100)
    }

    static func setPacket(_ value: Int) -> [UInt8] {
        let clamped = UInt16(max(0, min(0xFFFF, value)))
        let packet: [UInt8] = [0x84, 0x03, 0x10, UInt8(clamped >> 8), UInt8(clamped & 0xFF)]
        return packet + [checksum(packet)]
    }

    static func set(_ value: Int, on service: CFTypeRef) {
        guard let write else { return }
        var packet = setPacket(value)
        for _ in 0..<2 {
            usleep(10_000)
            _ = packet.withUnsafeMutableBytes { write(service, chipAddress, dataAddress, $0.baseAddress!, UInt32($0.count)) }
        }
    }
}
