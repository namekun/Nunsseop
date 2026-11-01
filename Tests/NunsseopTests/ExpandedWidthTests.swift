import Foundation
import Testing
@testable import Nunsseop

@MainActor
struct ExpandedWidthTests {
    @Test func twelveTabsWithoutANotchNeedOneRowAndTheStatusIcons() {
        // 12 × 28 − 2, the 96 for the title, the 12 gap, the 64 of status and 64 of inset.
        #expect(NotchViewModel.fittingWidth(tabCount: 12, status: 64, label: 96) == 570)
    }

    @Test func homeAloneIsNarrow() {
        #expect(NotchViewModel.fittingWidth(tabCount: 1, status: 64) == 166)
    }

    @Test func theSavedWidthWinsWhenItAlreadyFits() {
        #expect(NotchViewModel.widened(780, fitting: 682, limit: 1200) == 780)
    }

    @Test func theFittingWidthWinsWhenTheSavedOneIsTooNarrow() {
        #expect(NotchViewModel.widened(620, fitting: 924, limit: 1200) == 924)
    }

    @Test func theFittingWidthStopsAtThePanelLimit() {
        #expect(NotchViewModel.widened(620, fitting: 924, limit: 920) == 920)
        // A limit below the saved width never narrows it.
        #expect(NotchViewModel.widened(620, fitting: 924, limit: 500) == 620)
    }

    @Test func theHeaderReservesRoomForSettingsAndQuit() {
        // Both are 26 wide with a 6 gap each.
        #expect(NotchViewModel.headerStatusWidth == 64)
    }

    private let statuses: [CGFloat] = [64, 130]
    private let labels: [CGFloat] = [0, 96]

    @Test func aNotchedHeaderKeepsEveryTabLeftOfTheCamera() {
        for notch in [44, 200, 384] as [CGFloat] {
            for width in [540, 620, 699, 1200] as [CGFloat] {
                let layout = HeaderBar.layout(width: width, status: 64, hasNotch: true, notchWidth: notch)
                #expect(layout.camera == notch + 8)
                #expect(layout.strip == layout.side)
                #expect(2 * layout.strip + layout.camera + 12 == width - 2 * NotchViewModel.headerInset)
            }
        }
    }

    @Test func aHeaderWithoutANotchHasRoomForEveryTabAtTheFittingWidth() {
        for count in 1...14 {
            for status in statuses {
                for label in labels {
                    let width = NotchViewModel.fittingWidth(tabCount: count, status: status, label: label)
                    let layout = HeaderBar.layout(width: width, status: status, hasNotch: false, notchWidth: 44)
                    #expect(layout.strip == NotchViewModel.stripWidth(count) + label, "count \(count), status \(status), label \(label)")
                    #expect(layout.camera == 0)
                }
            }
        }
    }

    @Test func aCurrentTabsTitleIsNeverReservedMoreThanTheCap() {
        let label = NotchViewModel.tabLabelWidth(NotchTab.allCases)
        #expect(label <= NotchViewModel.tabTitleCap + 22)
        #expect(NotchViewModel.tabLabelWidth([]) == 22)
    }

    @Test func theFittingWidthStaysInsideThePanelForEveryTabCountOnTheCommonDisplays() {
        // A 14" MacBook Pro's notch, with every tab.
        var g = NotchGeometry()
        g.screenFrame = NSRect(x: 0, y: 0, width: 1512, height: 982)
        // The unclamped fitting width itself has to fit; clamping it to the limit would hide an overflow.
        let label = NotchViewModel.tabLabelWidth(NotchTab.allCases)
        for count in 1...NotchTab.allCases.count {
            let fitting = NotchViewModel.fittingWidth(tabCount: count, status: NotchViewModel.headerStatusWidth, label: label)
            #expect(fitting <= g.maxExpandedWidth, "count \(count)")
            #expect(fitting <= g.panelFrame.width - 40, "count \(count)")
            // Because it fits, widening a narrower saved width reaches it exactly.
            #expect(NotchViewModel.widened(0, fitting: fitting, limit: g.maxExpandedWidth) == fitting, "count \(count)")
        }
    }
}

@MainActor
struct TabAfterCollapseTests {
    private let all: (NotchTab) -> Bool = { _ in true }

    @Test func mirrorIsLeftSoTheCameraCannotStartOnReopen() {
        #expect(NotchViewModel.tabAfterCollapse(.mirror, isVisible: all) == .home)
    }

    @Test func aVisibleTabIsKept() {
        for tab in NotchTab.allCases where tab != .mirror {
            #expect(NotchViewModel.tabAfterCollapse(tab, isVisible: all) == tab)
        }
    }

    @Test func aTabTheSettingsHideIsLeft() {
        let withoutSearch: (NotchTab) -> Bool = { $0 != .search }
        #expect(NotchViewModel.tabAfterCollapse(.search, isVisible: withoutSearch) == .home)
        #expect(NotchViewModel.tabAfterCollapse(.timer, isVisible: withoutSearch) == .timer)
    }

    @Test func mirrorSwitchedOffStillGoesHome() {
        #expect(NotchViewModel.tabAfterCollapse(.mirror, isVisible: { $0 != .mirror }) == .home)
    }

    @Test func homeStaysHome() {
        #expect(NotchViewModel.tabAfterCollapse(.home, isVisible: all) == .home)
    }

    @Test func aHiddenTabIsLeftWithoutClosingToo() {
        #expect(NotchViewModel.visibleTab(.mirror, isVisible: { $0 != .mirror }) == .home)
        // Closing is what resets a visible Mirror, not a settings change.
        #expect(NotchViewModel.visibleTab(.mirror, isVisible: all) == .mirror)
    }
}
