import Foundation
import Testing
@testable import Nunsseop

struct CallProcessClassificationTests {
    private func process(_ bundleID: String, pid: pid_t = 100, input: Bool = false, output: Bool = false) -> CallMonitor.AudioProcess {
        CallMonitor.AudioProcess(pid: pid, bundleID: bundleID, isRunningInput: input, isRunningOutput: output)
    }

    @Test func callAppWithInputIsActiveAndAlive() {
        let result = CallMonitor.classify([process("us.zoom.CptHost", pid: 7, input: true)], own: 1)
        #expect(result.apps == ["us.zoom.xos": 7])
        #expect(result.alive == ["us.zoom.xos"])
        #expect(result.browsers.isEmpty)
    }

    @Test func callAppPlayingAudioOnlyIsAliveButNotActive() {
        let result = CallMonitor.classify([process("us.zoom.CptHost", output: true)], own: 1)
        #expect(result.apps.isEmpty)
        #expect(result.alive == ["us.zoom.xos"])
    }

    @Test func browserInputStartsATabCheckButOutputOnlyDoesNot() {
        let input = CallMonitor.classify([process("com.google.Chrome.helper", input: true)], own: 1)
        #expect(input.browsers == ["com.google.Chrome"])
        #expect(input.alive == ["com.google.Chrome"])
        #expect(input.apps.isEmpty)
        let output = CallMonitor.classify([process("com.google.Chrome.helper", output: true)], own: 1)
        #expect(output.browsers.isEmpty)
        #expect(output.alive == ["com.google.Chrome"])
    }

    @Test func ignoresOwnProcessOtherAppsAndIdleProcesses() {
        let result = CallMonitor.classify([
            process("us.zoom.xos", pid: 1, input: true),
            process("com.apple.Safari", pid: 2, input: true, output: true),
            process("us.zoom.xos", pid: 3),
        ], own: 1)
        #expect(result.apps.isEmpty && result.browsers.isEmpty && result.alive.isEmpty)
    }

    @Test func firstProcessOfAnAppKeepsTheSlot() {
        let result = CallMonitor.classify([
            process("us.zoom.CptHost", pid: 5, input: true),
            process("us.zoom.xos", pid: 9, input: true),
        ], own: 1)
        #expect(result.apps == ["us.zoom.xos": 5])
    }

    @Test(arguments: [
        ("com.microsoft.teams2.modulehost", "com.microsoft.teams2"),
        ("com.microsoft.teams.helper", "com.microsoft.teams"),
        ("com.tinyspeck.slackmacgap.helper", "com.tinyspeck.slackmacgap"),
        ("com.hnc.Discord.helper", "com.hnc.Discord"),
        ("com.hnc.discord", "com.hnc.Discord"),
        ("net.whatsapp.WhatsApp", "net.whatsapp.WhatsApp"),
        ("desktop.WhatsApp.helper", "desktop.WhatsApp"),
        ("com.apple.avconferenced", "com.apple.FaceTime"),
        ("com.apple.telephonyutilities", "com.apple.FaceTime"),
        ("com.apple.FaceTime", "com.apple.FaceTime"),
        ("com.webex.meetingmanager.helper", "com.webex.meetingmanager"),
        ("Cisco-Systems.Spark.helper", "Cisco-Systems.Spark"),
        ("com.skype.skype", "com.skype.skype"),
    ])
    func mapsCallAppsAndTheirHelpers(process: String, app: String) {
        #expect(CallMonitor.appBundleID(for: process) == app)
    }

    @Test func mapsBrowserHelpersToTheirBrowser() {
        #expect(CallMonitor.browser(for: "com.google.Chrome.helper")?.bundleID == "com.google.Chrome")
        #expect(CallMonitor.browser(for: "com.brave.Browser.helper.Renderer")?.bundleID == "com.brave.Browser")
        #expect(CallMonitor.browser(for: "com.apple.Safari") == nil)
        #expect(CallMonitor.browser(for: "org.mozilla.firefox") == nil)
    }
}
