import AppKit
import Testing
@testable import Nunsseop

struct FullScreenWindowsTests {
    /// A 2560 × 1440 monitor without a camera housing, as the window list places it when it is the only screen.
    private let monitor = CGRect(x: 0, y: 0, width: 2560, height: 1440)

    /// One window as `CGWindowListCopyWindowInfo` describes it, numbers boxed the way it boxes them.
    private func window(_ bounds: CGRect, layer: Int = 0, pid: Int32 = 42, alpha: Double = 1) -> [String: Any] {
        [kCGWindowLayer as String: NSNumber(value: layer), kCGWindowOwnerPID as String: NSNumber(value: pid),
         kCGWindowAlpha as String: NSNumber(value: alpha), kCGWindowBounds as String: bounds.dictionaryRepresentation]
    }

    @Test func anAppFillingTheScreenToItsTopCoversIt() {
        #expect(FullScreenWindows.cover(monitor, windows: [window(monitor)], ownPID: 7))
    }

    @Test func aZoomedWindowStopsBelowTheMenuBarAndDoesNot() {
        let zoomed = CGRect(x: 0, y: 25, width: 2560, height: 1415)
        #expect(!FullScreenWindows.cover(monitor, windows: [window(zoomed)], ownPID: 7))
    }

    @Test func nunsseopsOwnWindowsDoNotCount() {
        #expect(!FullScreenWindows.cover(monitor, windows: [window(monitor, pid: 7)], ownPID: 7))
    }

    @Test func theMenuBarDockAndWallpaperLayersDoNotCount() {
        let others = [window(monitor, layer: 24), window(monitor, layer: 20), window(monitor, layer: -2147483623)]
        #expect(!FullScreenWindows.cover(monitor, windows: others, ownPID: 7))
    }

    @Test func anInvisibleWindowDoesNotCount() {
        #expect(!FullScreenWindows.cover(monitor, windows: [window(monitor, alpha: 0)], ownPID: 7))
    }

    @Test func anAppFullScreenOnAnotherScreenDoesNotCoverThisOne() {
        let laptop = CGRect(x: 2560, y: 0, width: 1512, height: 982)
        #expect(!FullScreenWindows.cover(monitor, windows: [window(laptop)], ownPID: 7))
        #expect(FullScreenWindows.cover(laptop, windows: [window(laptop)], ownPID: 7))
    }

    @Test func aScreenFrameTurnsIntoTheWindowListsTopDownCoordinates() {
        // A monitor standing above a 1512 × 982 main screen, a little to its left.
        let above = CGRect(x: -200, y: 982, width: 2560, height: 1440)
        #expect(FullScreenWindows.windowListRect(above, mainHeight: 982) == CGRect(x: -200, y: -1440, width: 2560, height: 1440))
        let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
        #expect(FullScreenWindows.windowListRect(main, mainHeight: 982) == main)
    }
}

struct FullScreenBrowTests {
    private func mayFade(expanded: Bool = false, pointerOver: Bool = false, hud: Bool = false, prompt: Bool = false,
                         live: Bool = false, peek: Bool = false, fullScreen: Bool = false) -> Bool {
        NotchViewModel.browMayFade(expanded: expanded, pointerOver: pointerOver, hud: hud, prompt: prompt, live: live, peek: peek,
                                   fullScreen: fullScreen)
    }

    @Test func musicTimersAndSneakPeeksKeepTheEyebrowUpExceptInAFullScreenApp() {
        #expect(!mayFade(live: true) && !mayFade(peek: true))
        #expect(mayFade(live: true, fullScreen: true) && mayFade(peek: true, fullScreen: true))
    }

    @Test func aHUDAPromptThePointerOrAnOpenNotchKeepItUpEvenInAFullScreenApp() {
        #expect(!mayFade(hud: true, fullScreen: true))
        #expect(!mayFade(prompt: true, fullScreen: true))
        #expect(!mayFade(pointerOver: true, live: true, fullScreen: true))
        #expect(!mayFade(expanded: true, fullScreen: true))
    }

    @Test func withNothingShowingItFadesEitherWay() {
        #expect(mayFade() && mayFade(fullScreen: true))
    }
}
