import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if UpdateMethod.current == .sparkle { SparkleUpdater.shared.start() }
        controller = NotchWindowController()
        controller?.show()
        AlarmRuntime.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AlarmRuntime.shared.stop()
        controller?.prepareToQuit()
    }
}
