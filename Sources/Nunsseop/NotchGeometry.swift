import AppKit
import IOKit

struct NotchGeometry: Equatable {
    var screenFrame: NSRect
    var collapsedSize: CGSize
    var hasNotch: Bool
    /// On a display with a Dynamic Island, its width. The system draws there, so the eyebrow rests beside it.
    var islandWidth: CGFloat?

    /// Without a camera housing the eyebrow floats this far below the top edge and stays inside the menu bar.
    var topInset: CGFloat { hasNotch ? 0 : 3 }

    /// True while a MacBook's lid is closed (clamshell mode with an external display).
    static var lidIsClosed: Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return (value as? Bool) ?? false
    }

    /// The display named in settings if it is connected; otherwise the one with the pointer, then the built-in display
    /// with a camera housing, then the main screen.
    /// With no pointer, no screen is picked for holding it.
    static func pickScreen(preferredName: String = "", pointer: NSPoint? = NSEvent.mouseLocation) -> NSScreen? {
        let screens = NSScreen.screens
        let candidates = screens.map { screen in
            ScreenCandidate(name: screen.localizedName, hasNotch: screen.safeAreaInsets.top > 0, isMain: screen == NSScreen.main,
                            hasPointer: pointer.map { holdsPointer(screen.frame, $0) } ?? false,
                            isBuiltin: (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
                                .map { CGDisplayIsBuiltin($0) != 0 } ?? false)
        }
        return pick(candidates, preferredName: preferredName, lidClosed: lidIsClosed).map { screens[$0] }
    }

    /// Whether the pointer is on the screen with this frame. At the very top the pointer sits on the frame's top edge, which
    /// `contains` leaves out.
    static func holdsPointer(_ frame: NSRect, _ point: NSPoint) -> Bool { NSMouseInRect(point, frame, false) }

    /// Whether the pointer is off the notch's screen and on another one; on no screen at all, it has not left.
    static func pointerLeft(_ current: NSRect, for point: NSPoint, among screens: [NSRect]) -> Bool {
        !holdsPointer(current, point) && screens.contains { holdsPointer($0, point) }
    }

    struct ScreenCandidate: Equatable {
        var name: String
        var hasNotch: Bool
        var isMain: Bool
        var hasPointer = false
        var isBuiltin: Bool
    }

    /// The index of the screen to use. With the lid closed the built-in display is passed over: it can stay listed, camera housing
    /// and all, for a moment after the lid closes.
    static func pick(_ screens: [ScreenCandidate], preferredName: String, lidClosed: Bool) -> Int? {
        let usable = screens.indices.filter { !(lidClosed && screens[$0].isBuiltin) }
        if !preferredName.isEmpty, let match = usable.first(where: { screens[$0].name == preferredName }) { return match }
        return usable.first { screens[$0].hasPointer } ?? usable.first { screens[$0].hasNotch } ?? usable.first { screens[$0].isMain }
            ?? usable.first ?? screens.indices.first
    }

    /// Width of the collapsed eyebrow on a display without a camera housing.
    static let browWidth: CGFloat = 44

    /// The PROLED MacBook Pros, from AppleDB ahead of their release: Apple's own list doesn't have them yet. An id that turns
    /// out wrong leaves that Mac treated like any other with a notch.
    static let dynamicIslandModels: Set<String> = ["Mac17,10", "Mac17,11", "Mac17,12", "Mac17,13"]
    static func hasDynamicIsland(model: String) -> Bool { dynamicIslandModels.contains(model) }

    /// Used until a Mac with an island has been measured.
    static let estimatedIslandWidth: CGFloat = 200

    /// The gap between the menu bar's halves when that gap looks like an island, otherwise the estimate.
    static func islandWidth(frame: NSRect, safeTop: CGFloat, leftAuxWidth: CGFloat?, rightAuxWidth: CGFloat?) -> CGFloat {
        guard safeTop > 0, let leftAuxWidth, let rightAuxWidth else { return estimatedIslandWidth }
        let gap = frame.width - leftAuxWidth - rightAuxWidth
        return (100...400).contains(gap) ? gap : estimatedIslandWidth
    }

    /// How far right of the middle the collapsed shape rests.
    var restShift: CGFloat { islandWidth.map { $0 / 2 + 8 + collapsedSize.width / 2 } ?? 0 }

    /// Used only when no screen is attached at launch; the next screen change relayouts.
    init() {
        screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        collapsedSize = CGSize(width: Self.browWidth, height: 18)
        hasNotch = false
    }

    /// Debug builds can pretend a display has a notch of this width with `--fake-notch <points>`.
    private static let fakeNotchWidth: CGFloat = {
        #if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "--fake-notch"), i + 1 < CommandLine.arguments.count,
           let width = Double(CommandLine.arguments[i + 1]) { return width }
        #endif
        return 0
    }()

    /// Debug builds can pretend any display has an island with `--fake-island`.
    private static let fakesIsland: Bool = {
        #if DEBUG
        return CommandLine.arguments.contains("--fake-island")
        #else
        return false
        #endif
    }()

    /// This Mac's model identifier, such as "Mac15,6".
    static let modelIdentifier: String = {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "" }
        return String(cString: bytes)
    }()

    private static func isBuiltin(_ screen: NSScreen) -> Bool {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID).map { CGDisplayIsBuiltin($0) != 0 } ?? false
    }

    init(screen: NSScreen) {
        screenFrame = screen.frame
        let safeTop = screen.safeAreaInsets.top
        let left = screen.auxiliaryTopLeftArea?.width, right = screen.auxiliaryTopRightArea?.width
        if Self.fakesIsland || (Self.isBuiltin(screen) && Self.hasDynamicIsland(model: Self.modelIdentifier)) {
            islandWidth = Self.islandWidth(frame: screen.frame, safeTop: safeTop, leftAuxWidth: left, rightAuxWidth: right)
        }
        (collapsedSize, hasNotch) = Self.collapsedSize(
            frame: screen.frame, visibleFrame: screen.visibleFrame, safeTop: safeTop, leftAuxWidth: left, rightAuxWidth: right,
            fakeNotchWidth: Self.fakeNotchWidth, island: islandWidth)
    }

    /// What `--print-screen-info` prints, for someone with a Mac we don't have to send us.
    struct ScreenFacts {
        var name: String
        var isBuiltin: Bool
        var frame: NSRect
        var visibleFrame: NSRect
        var scale: CGFloat
        var safeTop: CGFloat
        var leftAuxWidth: CGFloat?
        var rightAuxWidth: CGFloat?
    }

    static func screenReport(model: String, system: String, screens: [ScreenFacts]) -> String {
        let number = { (value: CGFloat) in value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value) }
        let box = { (rect: NSRect) in [rect.minX, rect.minY, rect.width, rect.height].map(number).joined(separator: " ") }
        var lines = ["model: \(model)", "macOS: \(system)", "dynamic island: \(hasDynamicIsland(model: model) ? "yes" : "no")"]
        for screen in screens {
            lines += ["\(screen.name)\(screen.isBuiltin ? " (built-in)" : "")", "  frame: \(box(screen.frame))", "  visible: \(box(screen.visibleFrame))",
                      "  scale: \(number(screen.scale))", "  safe area top: \(number(screen.safeTop))",
                      "  left of camera: \(screen.leftAuxWidth.map(number) ?? "none")",
                      "  right of camera: \(screen.rightAuxWidth.map(number) ?? "none")"]
        }
        return lines.joined(separator: "\n")
    }

    static func screenReport() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return screenReport(model: modelIdentifier, system: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
                            screens: NSScreen.screens.map { screen in
            ScreenFacts(name: screen.localizedName, isBuiltin: isBuiltin(screen), frame: screen.frame, visibleFrame: screen.visibleFrame,
                        scale: screen.backingScaleFactor, safeTop: screen.safeAreaInsets.top,
                        leftAuxWidth: screen.auxiliaryTopLeftArea?.width, rightAuxWidth: screen.auxiliaryTopRightArea?.width)
        })
    }

    /// The closed shape's size for a display, and whether it has a camera housing.
    static func collapsedSize(frame: NSRect, visibleFrame: NSRect, safeTop: CGFloat, leftAuxWidth: CGFloat?,
                              rightAuxWidth: CGFloat?, fakeNotchWidth: CGFloat, island: CGFloat? = nil) -> (size: CGSize, hasNotch: Bool) {
        if island == nil, safeTop > 0, let leftAuxWidth, let rightAuxWidth {
            // The shape's top corners flare outward, so widen it to keep the body as wide as the housing.
            return (CGSize(width: frame.width - leftAuxWidth - rightAuxWidth + 12, height: safeTop), true)
        } else if island == nil, fakeNotchWidth > 0 {
            return (CGSize(width: fakeNotchWidth, height: 32), true)
        } else {
            let menuBarHeight = frame.maxY - visibleFrame.maxY
            return (CGSize(width: browWidth, height: max((menuBarHeight > 0 ? menuBarHeight : 24) - 6, 16)), false)
        }
    }

    /// Widest the expanded shape may grow to fit every tab.
    var maxExpandedWidth: CGFloat { max(AppSettings.expandedWidthRange.upperBound, min(screenFrame.width - 80, 1200)) }

    /// The panel is sized for the largest allowed shape; only the drawn shape changes.
    var panelFrame: NSRect {
        let size = CGSize(width: maxExpandedWidth + 40,
                          height: AppSettings.expandedHeightRange.upperBound + 20)
        return NSRect(x: screenFrame.midX - size.width / 2,
                      y: screenFrame.maxY - size.height,
                      width: size.width, height: size.height)
    }

    /// The expanded shape sits against the top edge even where the collapsed eyebrow floats, so it passes `inset: 0`.
    func shapeRect(size: CGSize, inset: CGFloat? = nil) -> NSRect {
        NSRect(x: screenFrame.midX - size.width / 2,
               y: screenFrame.maxY - (inset ?? topInset) - size.height,
               width: size.width, height: size.height)
    }
}
