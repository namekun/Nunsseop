import Foundation
import Testing
@testable import Nunsseop

struct TabSplitTests {
    @Test func twelveTabsWithAllStatusIcons() {
        // Settings and Quit 64, battery 66, weather 50.
        let split = NotchViewModel.tabSplit(count: 12, status: 180)
        // 9 left: 9 × 36 − 6 + 2 = 320; 3 right: 3 × 36 − 6 + 2 + 180 = 284. 8 left ties at 320, and ties keep more on the left.
        #expect(split.left == 9)
        #expect(split.side == 320)
    }

    @Test func twelveTabsWithSettingsAndQuitOnly() {
        let split = NotchViewModel.tabSplit(count: 12, status: 64)
        // 7 left: 248; 5 right: 174 + 2 + 64 = 240.
        #expect(split.left == 7)
        #expect(split.side == 248)
    }

    @Test func homeAloneStaysLeft() {
        let split = NotchViewModel.tabSplit(count: 1, status: 64)
        #expect(split.left == 1)
        #expect(split.side == 64)
    }
}

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
