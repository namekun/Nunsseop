import AppKit
import Testing
import SwiftUI
@testable import Nunsseop

@MainActor
struct HUDSymbolTests {
    @Test func volumeSymbolsFollowTheLevel() {
        #expect(HUDContent.symbol(for: .volume(0.33, muted: false)) == "speaker.wave.1.fill")
        #expect(HUDContent.symbol(for: .volume(0.34, muted: false)) == "speaker.wave.2.fill")
        #expect(HUDContent.symbol(for: .volume(0.66, muted: false)) == "speaker.wave.2.fill")
        #expect(HUDContent.symbol(for: .volume(0.67, muted: false)) == "speaker.wave.3.fill")
        #expect(HUDContent.symbol(for: .volume(1, muted: false)) == "speaker.wave.3.fill")
    }

    @Test func mutedOrZeroVolumeIsSlashed() {
        #expect(HUDContent.symbol(for: .volume(0.5, muted: true)) == "speaker.slash.fill")
        #expect(HUDContent.symbol(for: .volume(0, muted: false)) == "speaker.slash.fill")
        #expect(HUDContent.symbol(for: .volume(0.01, muted: false)) == "speaker.wave.1.fill")
    }

    @Test func brightnessSwitchesAtHalf() {
        #expect(HUDContent.symbol(for: .brightness(0.49)) == "sun.min.fill")
        #expect(HUDContent.symbol(for: .brightness(0.5)) == "sun.max.fill")
    }

    @Test func keyboardBacklightIsMinOnlyWhenOff() {
        #expect(HUDContent.symbol(for: .keyboard(0)) == "light.min")
        #expect(HUDContent.symbol(for: .keyboard(0.01)) == "light.max")
    }

    @Test func powerShowsABoltOnACAndABatteryOtherwise() {
        #expect(HUDContent.symbol(for: .power(PowerState(percent: 50, isCharging: true, onAC: true))) == "bolt.fill")
        #expect(HUDContent.symbol(for: .power(PowerState(percent: 14, isCharging: false, onAC: false))) == "battery.25percent")
    }

    @Test func headphonesAndNoticesKeepTheirOwnSymbol() {
        #expect(HUDContent.symbol(for: .headphones(HeadphoneBattery(name: "AirPods", levels: []))) == "headphones")
        #expect(HUDContent.symbol(for: .notice(symbol: "calendar", title: "T", detail: nil)) == "calendar")
    }

    @Test func batteryBadgeBandsChangeAtTheirEdges() {
        let bands: [(Int, String)] = [(0, "battery.0percent"), (12, "battery.0percent"), (13, "battery.25percent"),
                                      (37, "battery.25percent"), (38, "battery.50percent"), (62, "battery.50percent"),
                                      (63, "battery.75percent"), (87, "battery.75percent"), (88, "battery.100percent"),
                                      (100, "battery.100percent")]
        for (percent, symbol) in bands {
            #expect(BatteryBadge.symbol(for: percent) == symbol, "\(percent)%")
        }
    }
}

@MainActor
struct HUDLineTests {
    @Test func aNoticeJoinsItsTitleAndDetail() {
        #expect(HUDContent.line(for: .notice(symbol: "x", title: "Title", detail: "Detail")) == "Title  ·  Detail")
    }

    @Test func aNoticeWithoutADetailIsJustTheTitle() {
        #expect(HUDContent.line(for: .notice(symbol: "x", title: "Title", detail: nil)) == "Title")
    }

    @Test func aHeadphoneLineListsEachLevel() {
        let battery = HeadphoneBattery(name: "AirPods", levels: [("Left", 90), ("Case", 60)])
        #expect(HUDContent.line(for: .headphones(battery)) == "AirPods  ·  Left 90%  ·  Case 60%")
    }

    @Test func aHeadphoneWithoutLevelsIsJustItsName() {
        #expect(HUDContent.line(for: .headphones(HeadphoneBattery(name: "Buds", levels: []))) == "Buds")
    }

    @Test func levelHUDsHaveNoText() {
        #expect(HUDContent.line(for: .volume(0.5, muted: false)) == nil)
        #expect(HUDContent.line(for: .brightness(0.5)) == nil)
        #expect(HUDContent.line(for: .keyboard(0.5)) == nil)
        #expect(HUDContent.line(for: .power(PowerState(percent: 5, isCharging: false, onAC: false))) == nil)
    }

    @Test func compactValueSlotsHoldTheBarAndThePercent() {
        #expect(HUDContent.compactValueWidth(for: .volume(0.5, muted: false)) == 110)
        #expect(HUDContent.compactValueWidth(for: .brightness(0.5)) == 110)
        #expect(HUDContent.compactValueWidth(for: .keyboard(0.5)) == 110)
        #expect(HUDContent.compactValueWidth(for: .power(PowerState(percent: 5, isCharging: false, onAC: false))) == 36)
    }

    @Test func textHUDsHaveNoCompactValue() {
        #expect(HUDContent.compactValueWidth(for: .notice(symbol: "x", title: "T", detail: nil)) == nil)
        #expect(HUDContent.compactValueWidth(for: .headphones(HeadphoneBattery(name: "AirPods", levels: []))) == nil)
    }
}

/// The one-row HUD reserves fixed slots for its symbol and value; what is drawn has to fit them.
/// These measure real fonts and SF Symbols, so they depend on the system's own, deliberately.
@MainActor
struct HUDSlotTests {
    private func symbolWidth(_ name: String) throws -> CGFloat {
        let image = try #require(NSImage(systemSymbolName: name, accessibilityDescription: nil))
        return try #require(image.withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))).size.width
    }

    @Test func everySymbolBesideNoticeTextFitsTheSymbolSlot() throws {
        let symbols = ["bolt.fill", "headphones", "calendar", "video.fill",
                       "mic.fill", "sparkles", "timer", "camera.viewfinder", "checkmark.circle.fill",
                       "tray.and.arrow.down.fill", "capslock.fill", "record.circle", "arrow.down.circle"]
        for name in symbols {
            #expect(try symbolWidth(name) <= HUDContent.lineSymbolWidth, "\(name)")
        }
    }

    @Test func theLevelSymbolsOverhangTheSlotByAtMostAPointIntoTheSidePadding() throws {
        // speaker.wave.3.fill is 21 wide against the 20 slot; the 18 of padding beside it absorbs that. The batteries are 20 on a
        // 1x display and 21 on a Retina one, all of it side bearing (see HUDLineRenderTests).
        let symbols = ["speaker.slash.fill", "speaker.wave.1.fill", "speaker.wave.2.fill", "speaker.wave.3.fill",
                       "sun.min.fill", "sun.max.fill", "light.min", "light.max", "battery.0percent", "battery.25percent",
                       "battery.50percent", "battery.75percent", "battery.100percent", "battery.100percent.bolt"]
        for name in symbols {
            #expect(try symbolWidth(name) <= HUDContent.lineSymbolWidth + 1, "\(name)")
        }
    }

    @Test func aFullPercentFitsThePowerValueSlot() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let width = ceil(("100%" as NSString).size(withAttributes: [.font: font]).width)
        #expect(width <= HUDContent.compactValueWidth(for: .power(PowerState(percent: 100, isCharging: false, onAC: true)))!)
    }
}

/// What the one-line power HUD draws, measured in pixels: the battery's ink stays in its slot whatever the display's scale.
@MainActor
struct HUDLineRenderTests {
    /// The columns, in points from the row's left edge, where anything light is drawn, merged into runs.
    private func inkRuns(_ event: HUDEvent) -> [ClosedRange<CGFloat>] {
        let view = HUDContent(event: event, height: 32, earWidth: 100, singleLine: true)
            .frame(width: 100, height: 32, alignment: .leading)
            .background(Color.black)
        let rep = EarRender.pixels(view, width: 100, height: 32)
        var runs: [ClosedRange<CGFloat>] = []
        for x in 0..<rep.pixelsWide {
            let lit = (0..<rep.pixelsHigh).contains { y in
                guard let c = rep.colorAt(x: x, y: y) else { return false }
                return c.redComponent + c.greenComponent + c.blueComponent > 0.6
            }
            guard lit else { continue }
            let left = CGFloat(x) / 2, right = CGFloat(x + 1) / 2
            if let last = runs.last, left - last.upperBound <= 1 {
                runs[runs.count - 1] = last.lowerBound...right
            } else {
                runs.append(left...right)
            }
        }
        return runs
    }

    @Test func theBatteryIsDrawnInsideItsSlotAndApartFromThePercent() throws {
        for percent in [5, 30, 55, 80, 100] {
            let runs = inkRuns(.power(PowerState(percent: percent, isCharging: false, onAC: false)))
            let battery = try #require(runs.first, "\(percent)%")
            // Ink at the row's very edge has been cut off there.
            #expect(battery.lowerBound > 0 && battery.upperBound <= HUDContent.lineSymbolWidth, "\(percent)%: \(battery)")
            #expect(runs.count > 1 && runs[1].lowerBound - battery.upperBound >= HUDContent.lineGap, "\(percent)%: \(runs)")
        }
    }
}
