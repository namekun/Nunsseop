import Foundation
import Testing
@testable import Nunsseop

struct SneakPeekFilterTests {
    let launch = Date(timeIntervalSinceReferenceDate: 0)

    /// Feeds the keys in order and returns which of them peeked.
    private func peeks(_ events: [(String, TimeInterval)]) -> [Bool] {
        var filter = SneakPeekFilter(launchedAt: launch)
        return events.map { filter.shouldPeek($0.0, at: launch + $0.1) }
    }

    @Test func trackLoadedAtLaunchIsSkipped() {
        #expect(peeks([("song A|false", 1), ("song A|false", 2)]) == [false, false])
    }

    @Test func laterChangesPeek() {
        #expect(peeks([("song A|false", 1), ("song A|true", 2), ("song B|true", 60), ("song B|true", 61)])
                == [false, true, true, false])
    }

    @Test func firstTrackLongAfterLaunchPeeks() {
        #expect(peeks([("song A|true", 120)]) == [true])
    }
}

struct InlinePeekWidthTests {
    @Test func theLongestLineDecides() {
        let short = NotchViewModel.peekLineWidth(lines: ["Hi"])
        let long = NotchViewModel.peekLineWidth(lines: ["Hi", "A much longer line of lyrics than the first"])
        #expect(long > short)
        #expect(long == NotchViewModel.peekLineWidth(lines: ["A much longer line of lyrics than the first"]))
    }

    @Test func roomForTheSymbolAndPaddingWithoutText() {
        // The play symbol (8), its gap (6) and 10 on each side.
        #expect(NotchViewModel.peekLineWidth(lines: [""]) == 34)
    }
}

struct IdleEarWidthTests {
    @Test func aLongerValueTakesMoreRoom() {
        let short = NotchViewModel.idleEarWidth(for: IdleValue(symbol: "bolt.fill", tint: nil, text: "1"))
        let long = NotchViewModel.idleEarWidth(for: IdleValue(symbol: "bolt.fill", tint: nil, text: "12"))
        #expect(long > short)
    }

    /// Lays the closed shape out the way NotchView draws it, in points from the camera's centre.
    private func layout(left: IdleValue?, right: IdleValue?, hidesLeftEar: Bool = false) throws
        -> (wall: ClosedRange<CGFloat>, stroke: ClosedRange<CGFloat>, left: ClosedRange<CGFloat>?, right: ClosedRange<CGFloat>?) {
        let notch: CGFloat = 44, margin = NotchViewModel.idleFittedMargin
        let sides = try #require(NotchViewModel.idleFittedSides(left: left, right: right))
        let width = notch + sides.left + sides.right
        let shift = NotchViewModel.collapsedShift(fitted: sides, hidesLeftEar: hidesLeftEar, width: width, notch: notch)
        let wall = -width / 2 + shift
        let brow = wall + NotchViewModel.browLead(width: width, notch: notch, shift: shift)
        let start = wall + NotchViewModel.idleLead(browLead: brow - wall, shift: shift, notch: notch) + margin
        let size = { (value: IdleValue) in NotchViewModel.idleEarWidth(for: value) - 8 }
        return (wall...(wall + width), (brow + margin)...(brow + notch - margin),
                left.map { start...(start + size($0)) },
                right.map { (wall + width - margin - size($0))...(wall + width - margin) })
    }

    @Test func fittedValuesSitBesideTheEyebrowOverTheCamera() throws {
        let short = IdleValue(symbol: "hand.raised.fill", tint: nil, text: "1")
        let long = IdleValue(symbol: "battery.100", tint: nil, text: "100%")
        for (l, r) in [(short, nil), (nil, short), (long, nil), (nil, long), (short, short), (short, long), (long, short), (long, long)] as [(IdleValue?, IdleValue?)] {
            let laid = try layout(left: l, right: r)
            // The eyebrow stays over the camera.
            #expect(abs(laid.stroke.lowerBound + laid.stroke.upperBound) < 0.01)
            // Each value is 8 from the stroke and 10 from its wall; the bare side keeps the eyebrow's own 10.
            if let left = laid.left {
                #expect(abs(laid.stroke.lowerBound - left.upperBound - 8) < 0.01)
                #expect(abs(left.lowerBound - laid.wall.lowerBound - 10) < 0.01)
            } else {
                #expect(abs(laid.stroke.lowerBound - laid.wall.lowerBound - 10) < 0.01)
            }
            if let right = laid.right {
                #expect(abs(right.lowerBound - laid.stroke.upperBound - 8) < 0.01)
                #expect(abs(laid.wall.upperBound - right.upperBound - 10) < 0.01)
            } else {
                #expect(abs(laid.wall.upperBound - laid.stroke.upperBound - 10) < 0.01)
            }
        }
    }

    @Test func withTheLeftEarHiddenBothValuesFollowTheEyebrow() throws {
        let short = IdleValue(symbol: "hand.raised.fill", tint: nil, text: "1")
        let long = IdleValue(symbol: "battery.100", tint: nil, text: "100%")
        for (l, r) in [(short, short), (short, long), (long, short)] {
            let laid = try layout(left: l, right: r, hidesLeftEar: true)
            let left = try #require(laid.left), right = try #require(laid.right)
            // Nothing left of the camera: the shape starts where the eyebrow does.
            #expect(abs(laid.wall.lowerBound - (laid.stroke.lowerBound - 10)) < 0.01)
            #expect(abs(left.lowerBound - laid.stroke.upperBound - 8) < 0.01)
            #expect(right.lowerBound - left.upperBound >= 8 - 0.01)
            #expect(abs(laid.wall.upperBound - right.upperBound - 10) < 0.01)
        }
    }

    @Test func shiftKeepsTheOldRulesWithoutFittedValues() {
        #expect(NotchViewModel.collapsedShift(fitted: nil, hidesLeftEar: false, width: 244, notch: 44) == 0)
        #expect(NotchViewModel.collapsedShift(fitted: nil, hidesLeftEar: true, width: 244, notch: 44) == 100)
        #expect(NotchViewModel.browLead(width: 244, notch: 44, shift: 0) == 100)
        #expect(NotchViewModel.browLead(width: 244, notch: 44, shift: 100) == 0)
        // A single side ignores the menus and keeps the eyebrow over the camera.
        #expect(NotchViewModel.collapsedShift(fitted: (0, 30), hidesLeftEar: true, width: 74, notch: 44) == 15)
        #expect(NotchViewModel.collapsedShift(fitted: (30, 0), hidesLeftEar: true, width: 74, notch: 44) == -15)
    }

    @MainActor @Test func aNewDayResizesTheShapeForTheDate() async {
        var fired = false
        let watching = NotchViewModel.dayChanges.sink { fired = true }
        NotificationCenter.default.post(name: .NSCalendarDayChanged, object: nil)
        await eventually { fired }
        watching.cancel()
        #expect(fired)
    }

    @Test func roomForThePaddingWithNothingToShow() {
        // 10 from the wall and 8 to the stroke, which leaves 10 of its frame empty.
        #expect(NotchViewModel.idleEarWidth(for: IdleValue(symbol: nil, tint: nil, text: "")) == 8)
    }
}
