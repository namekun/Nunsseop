import AppKit

/// Whether an app fills a screen to its very top, as a full-screen app or a slideshow does. A window that is only zoomed
/// stops below the menu bar, so it never counts.
enum FullScreenWindows {
    /// Whether one of `windows` (as `CGWindowListCopyWindowInfo` lists them) of another app covers all of `screen`, a frame in
    /// the window list's coordinates.
    nonisolated static func cover(_ screen: CGRect, windows: [[String: Any]], ownPID: pid_t) -> Bool {
        windows.contains { window in
            // Layer 0 is where app windows live; the menu bar, Dock and wallpaper sit on layers of their own.
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = (window[kCGWindowBounds as String] as? NSDictionary)
                      .flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) }) else { return false }
            return bounds.contains(screen)
        }
    }

    /// `frame` (AppKit's, measured up from the bottom of the main screen) in the window list's coordinates, measured down from
    /// the top of the main screen, `mainHeight` tall.
    nonisolated static func windowListRect(_ frame: CGRect, mainHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    /// Whether an app is full screen on the screen with `frame` right now.
    @MainActor static func cover(screenFrame frame: CGRect) -> Bool {
        guard let main = NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        return cover(windowListRect(frame, mainHeight: main.frame.height), windows: windows, ownPID: getpid())
    }
}
