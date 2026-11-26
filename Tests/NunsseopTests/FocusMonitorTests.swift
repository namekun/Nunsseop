import Foundation
import Testing
@testable import Nunsseop

@MainActor
struct FocusMonitorTests {
    private final class Calls { var list: [Bool] = [] }

    private func monitor() -> (FocusMonitor, Calls) {
        let monitor = FocusMonitor()
        let calls = Calls()
        monitor.onChange = { calls.list.append($0) }
        return (monitor, calls)
    }

    @Test func theFirstReadingIsNotAChange() {
        let (monitor, calls) = monitor()
        monitor.apply(true)
        #expect(monitor.isFocused == true && calls.list.isEmpty)
    }

    @Test func announcesATurnOnAndATurnOffOnce() {
        let (monitor, calls) = monitor()
        monitor.apply(false)
        monitor.apply(true)
        monitor.apply(true)
        monitor.apply(false)
        #expect(calls.list == [true, false])
    }

    @Test func aStatusThatIsNotSharedAnnouncesNothing() {
        let (monitor, calls) = monitor()
        monitor.apply(false)
        monitor.apply(nil)
        monitor.apply(true)
        #expect(calls.list.isEmpty && monitor.isFocused == true)
    }

    @Test func stoppingForgetsTheStateUnlessHiding() {
        let (monitor, calls) = monitor()
        monitor.apply(true)
        monitor.stop(clearing: false)
        #expect(monitor.isFocused == true)
        monitor.apply(true)
        #expect(calls.list.isEmpty)
        monitor.stop()
        #expect(monitor.isFocused == nil)
        monitor.apply(false)
        #expect(calls.list.isEmpty)
    }

    @Test func offMeansNothingIsReadOrAsked() {
        // Never started: no timer, no reading.
        let monitor = FocusMonitor()
        monitor.stop()
        #expect(monitor.isFocused == nil)
        let scratch = ScratchDefaults("focusIndicator")
        defer { scratch.remove() }
        #expect(AppSettings.load("focusIndicator", default: false, from: scratch.defaults) == false)
    }

    @Test func theTextsAreTranslatedIntoEveryLanguage() throws {
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources")
        for language in ["de", "es", "fr", "ja", "ko", "zh-Hans"] {
            let strings = try #require(NSDictionary(contentsOfFile: resources.appendingPathComponent("\(language).lproj/Localizable.strings").path), Comment(rawValue: language))
            for key in ["Focus on", "Focus off", "Show when a Focus turns on or off",
                        "macOS asks to share Focus Status the first time. It only tells whether a Focus is on, not which one, and only while “Share Focus Status” is on in System Settings › Focus."] {
                let text = strings[key] as? String ?? ""
                #expect(!text.isEmpty && text != key, Comment(rawValue: "\(language): \(key)"))
            }
        }
        for language in ["en", "de", "es", "fr", "ja", "ko", "zh-Hans"] {
            let plist = try #require(NSDictionary(contentsOfFile: resources.appendingPathComponent("\(language).lproj/InfoPlist.strings").path), Comment(rawValue: language))
            #expect(!(plist["NSFocusStatusUsageDescription"] as? String ?? "").isEmpty, Comment(rawValue: language))
        }
    }
}
