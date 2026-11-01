import Foundation
import Testing
@testable import Nunsseop

struct DisplayCollapsedSizeTests {
    private let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)

    private func size(frame: NSRect? = nil, menuBar: CGFloat = 0, safeTop: CGFloat = 0, left: CGFloat? = nil,
                      right: CGFloat? = nil, fake: CGFloat = 0) -> (size: CGSize, hasNotch: Bool) {
        let frame = frame ?? screen
        let visible = NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - menuBar)
        return NotchGeometry.collapsedSize(frame: frame, visibleFrame: visible, safeTop: safeTop,
                                           leftAuxWidth: left, rightAuxWidth: right, fakeNotchWidth: fake)
    }

    @Test func aCameraHousingTakesTheWidthBetweenTheMenuBarHalvesAndTheSafeAreaHeight() {
        let notched = size(menuBar: 32, safeTop: 32, left: 570, right: 570)
        // 1512 - 570 - 570, plus 12 for the flared top corners.
        #expect(notched.size == CGSize(width: 384, height: 32))
        #expect(notched.hasNotch)
    }

    @Test func aSafeAreaWithoutBothMenuBarHalvesIsNotANotch() {
        #expect(size(menuBar: 37, safeTop: 32, left: nil, right: nil).hasNotch == false)
        #expect(size(menuBar: 37, safeTop: 32, left: 570, right: nil).hasNotch == false)
        #expect(size(menuBar: 37, safeTop: 32, left: nil, right: 570).hasNotch == false)
        // No safe area at all, even with both halves reported.
        #expect(size(menuBar: 24, safeTop: 0, left: 570, right: 570).hasNotch == false)
    }

    @Test func theEyebrowIsSixShorterThanTheMenuBar() {
        #expect(size(menuBar: 24).size == CGSize(width: NotchGeometry.browWidth, height: 18))
        #expect(size(menuBar: 37).size.height == 31)
        #expect(size(menuBar: 28).size.height == 22)
    }

    @Test func theEyebrowHasAFloorOfSixteen() {
        #expect(size(menuBar: 20).size.height == 16)
        #expect(size(menuBar: 22).size.height == 16)
        #expect(size(menuBar: 23).size.height == 17)
    }

    @Test func anAutoHiddenMenuBarFallsBackToA24PointBar() {
        // visibleFrame reaches the top, so the bar measures 0: it counts as 24, which gives 18 and not the floor of 16.
        #expect(size(menuBar: 0).size.height == 18)
        #expect(size(menuBar: 0).hasNotch == false)
    }

    @Test func theMenuBarIsMeasuredFromTheDisplaysOwnTopEdge() {
        // A second display placed above and right of the first.
        let second = NSRect(x: 1512, y: 982, width: 1920, height: 1080)
        #expect(size(frame: second, menuBar: 37).size.height == 31)
    }

    @Test func aFakeNotchOnlyAppliesWithoutARealOne() {
        let fake = size(menuBar: 24, fake: 200)
        #expect(fake.size == CGSize(width: 200, height: 32))
        #expect(fake.hasNotch)
        let real = size(menuBar: 32, safeTop: 32, left: 570, right: 570, fake: 200)
        #expect(real.size.width == 384)
    }
}

struct NotchGeometryTests {
    /// A display placed to the right of the main one, so nothing is at x = 0.
    private func geometry(width: CGFloat = 1512, hasNotch: Bool = true) -> NotchGeometry {
        var g = NotchGeometry()
        g.screenFrame = NSRect(x: 1440, y: 0, width: width, height: 982)
        g.hasNotch = hasNotch
        return g
    }

    @Test func theExpandedShapeMayGrowToTheScreenMinus80UpTo1200() {
        for (width, expected): (CGFloat, CGFloat) in [(1000, 920), (1280, 1200), (1512, 1200), (3840, 1200), (700, 780), (860, 780)] {
            #expect(geometry(width: width).maxExpandedWidth == expected)
        }
    }

    @Test func theWidestShapeNeverFallsBelowTheSettingsLimit() {
        #expect(geometry(width: 500).maxExpandedWidth == CGFloat(AppSettings.expandedWidthRange.upperBound))
    }

    @Test func thePanelIsCentredOnTheScreenAndFlushWithItsTop() {
        let g = geometry()
        let panel = g.panelFrame
        #expect(panel.size == CGSize(width: 1240, height: 280))
        #expect(panel.midX == 2196)
        #expect(panel.maxY == 982)
    }

    @Test func thePanelIsAlwaysWideEnoughForTheLargestShape() {
        for width in [700, 1000, 1280, 1512, 3840] as [CGFloat] {
            let g = geometry(width: width)
            #expect(g.panelFrame.width == g.maxExpandedWidth + 40)
            #expect(g.panelFrame.width >= CGFloat(AppSettings.expandedWidthRange.upperBound))
            #expect(g.panelFrame.height >= CGFloat(AppSettings.expandedHeightRange.upperBound))
        }
    }

    @Test func aNotchedShapeIsFlushWithTheTopEdge() {
        let g = geometry()
        #expect(g.topInset == 0)
        let rect = g.shapeRect(size: CGSize(width: 200, height: 32))
        #expect(rect.maxY == 982)
        #expect(rect.midX == 2196)
        #expect(rect.size == CGSize(width: 200, height: 32))
    }

    @Test func aFloatingEyebrowSitsThreePointsBelowTheTopEdge() {
        let g = geometry(hasNotch: false)
        #expect(g.topInset == 3)
        #expect(g.shapeRect(size: CGSize(width: 44, height: 18)).maxY == 979)
    }

    @Test func theExpandedShapeIgnoresTheInsetAndSitsAgainstTheTop() {
        let g = geometry(hasNotch: false)
        #expect(g.shapeRect(size: CGSize(width: 620, height: 196), inset: 0).maxY == 982)
    }

    @Test func theDefaultGeometryIsAnEyebrowOnA1440By900Screen() {
        let g = NotchGeometry()
        #expect(g.screenFrame == NSRect(x: 0, y: 0, width: 1440, height: 900))
        #expect(g.collapsedSize == CGSize(width: 44, height: 18))
        #expect(!g.hasNotch)
    }
}

struct PickScreenTests {
    private let builtin = NotchGeometry.ScreenCandidate(name: "Built-in Retina Display", hasNotch: true, isMain: false, isBuiltin: true)
    private let external = NotchGeometry.ScreenCandidate(name: "Q27G2SG4B+", hasNotch: false, isMain: true, isBuiltin: false)
    private let second = NotchGeometry.ScreenCandidate(name: "DELL U2720Q", hasNotch: false, isMain: false, isBuiltin: false)

    @Test func withTheLidOpenTheBuiltInDisplayWithItsCameraHousingWins() {
        #expect(NotchGeometry.pick([external, builtin], preferredName: "", lidClosed: false) == 1)
    }

    @Test func withTheLidClosedTheBuiltInDisplayStillListedIsPassedOver() {
        // Right after the lid closes the built-in display can still be listed with its camera housing.
        #expect(NotchGeometry.pick([external, builtin], preferredName: "", lidClosed: true) == 0)
        #expect(NotchGeometry.pick([builtin, second, external], preferredName: "", lidClosed: true) == 2)
    }

    @Test func theDisplayNamedInSettingsWinsUnlessItIsTheClosedBuiltInOne() {
        #expect(NotchGeometry.pick([builtin, external, second], preferredName: "DELL U2720Q", lidClosed: false) == 2)
        #expect(NotchGeometry.pick([builtin, external], preferredName: "Built-in Retina Display", lidClosed: true) == 1)
        #expect(NotchGeometry.pick([builtin, external], preferredName: "Gone", lidClosed: false) == 0)
    }

    @Test func theScreenWithThePointerWinsUnlessADisplayIsNamedInSettings() {
        var pointed = second
        pointed.hasPointer = true
        #expect(NotchGeometry.pick([builtin, external, pointed], preferredName: "", lidClosed: false) == 2)
        #expect(NotchGeometry.pick([builtin, external, pointed], preferredName: "Q27G2SG4B+", lidClosed: false) == 1)
        // Nowhere on a listed screen (between frames): the built-in display with its camera housing, as before.
        #expect(NotchGeometry.pick([external, builtin, second], preferredName: "", lidClosed: false) == 1)
    }

    @Test func thePointerAtTheTopEdgeOrOnTheSeamIsOnOneScreen() {
        let left = NSRect(x: 0, y: 0, width: 2560, height: 1440)
        let right = NSRect(x: 2560, y: 0, width: 1920, height: 1080)
        // Pushed against the top of the left screen, as when opening the notch.
        #expect(NotchGeometry.holdsPointer(left, NSPoint(x: 1280, y: 1440)))
        #expect(!NotchGeometry.holdsPointer(right, NSPoint(x: 1280, y: 1440)))
        // On the seam it belongs to the right screen only.
        #expect(NotchGeometry.holdsPointer(right, NSPoint(x: 2560, y: 500)))
        #expect(!NotchGeometry.holdsPointer(left, NSPoint(x: 2560, y: 500)))
    }

    @Test func thePointerHasLeftOnlyForAnotherListedScreen() {
        let left = NSRect(x: 0, y: 0, width: 2560, height: 1440)
        let right = NSRect(x: 2560, y: 0, width: 1920, height: 1080)
        #expect(NotchGeometry.pointerLeft(left, for: NSPoint(x: 3000, y: 500), among: [left, right]))
        #expect(!NotchGeometry.pointerLeft(left, for: NSPoint(x: 1280, y: 1440), among: [left, right]))
        // Below the shorter right screen is on no screen: the notch stays.
        #expect(!NotchGeometry.pointerLeft(left, for: NSPoint(x: 3000, y: 1300), among: [left, right]))
    }

    @Test func aClosedLidWithOnlyTheBuiltInDisplayListedStillGivesAScreen() {
        #expect(NotchGeometry.pick([builtin], preferredName: "", lidClosed: true) == 0)
        #expect(NotchGeometry.pick([], preferredName: "", lidClosed: false) == nil)
    }
}

struct FollowAfterCloseTests {
    @Test func theNotchChangesScreensOnlyOnceItHasFinishedClosing() {
        let closed = Date(timeIntervalSinceReferenceDate: 1000)
        // Still shrinking: moved now, it would finish closing on the other screen.
        #expect(!NotchWindowController.hasSettled(closedAt: closed, now: closed.addingTimeInterval(0.1)))
        #expect(!NotchWindowController.hasSettled(closedAt: closed, now: closed.addingTimeInterval(NotchWindowController.closeSettle - 0.01)))
        #expect(NotchWindowController.hasSettled(closedAt: closed, now: closed.addingTimeInterval(NotchWindowController.closeSettle)))
        #expect(NotchWindowController.hasSettled(closedAt: .distantPast, now: closed))
    }
}

struct FollowAcrossDisplaysTests {
    private let current = NSRect(x: 0, y: 0, width: 1512, height: 982)
    private let pointer = NSPoint(x: 3000, y: 500)

    @Test func onlyAnAutomaticDisplayWithFollowingOnFollowsThePointer() {
        #expect(NotchWindowController.followsPointer(displayName: "", enabled: true))
        #expect(!NotchWindowController.followsPointer(displayName: "", enabled: false))
        #expect(!NotchWindowController.followsPointer(displayName: "DELL U2720Q", enabled: true))
    }

    @Test func aClosedNotchThatDoesNotFollowIsPickedWithoutThePointer() {
        #expect(NotchWindowController.screenPoint(following: true, idle: true, pointer: pointer, current: current) == pointer)
        #expect(NotchWindowController.screenPoint(following: false, idle: true, pointer: pointer, current: current) == nil)
    }

    @Test func anOpenNotchStaysOnItsScreenEitherWay() {
        let middle = NSPoint(x: 756, y: 491)
        #expect(NotchWindowController.screenPoint(following: true, idle: false, pointer: pointer, current: current) == middle)
        #expect(NotchWindowController.screenPoint(following: false, idle: false, pointer: pointer, current: current) == middle)
    }

    @Test func withoutThePointerTheNotchedThenTheMainScreenIsPicked() {
        // pickScreen with no pointer gives every candidate hasPointer false.
        let builtin = NotchGeometry.ScreenCandidate(name: "Built-in Retina Display", hasNotch: true, isMain: false, isBuiltin: true)
        let external = NotchGeometry.ScreenCandidate(name: "Q27G2SG4B+", hasNotch: false, isMain: true, isBuiltin: false)
        let second = NotchGeometry.ScreenCandidate(name: "DELL U2720Q", hasNotch: false, isMain: false, isBuiltin: false)
        #expect(NotchGeometry.pick([second, external, builtin], preferredName: "", lidClosed: false) == 2)
        #expect(NotchGeometry.pick([second, external, builtin], preferredName: "", lidClosed: true) == 1)
    }
}

struct MissionControlTests {
    @Test func theNotchIsHiddenByMissionControl() {
        #expect(NotchPanel.behavior.contains(.transient))
        #expect(!NotchPanel.behavior.contains(.stationary))
        #expect(NotchPanel.behavior.contains(.canJoinAllSpaces))
        #expect(NotchPanel.behavior.contains(.fullScreenAuxiliary))
    }
}

struct DynamicIslandTests {
    private let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func onlyThePROLEDModelsCountAsHavingAnIsland() {
        for model in ["Mac17,10", "Mac17,11", "Mac17,12", "Mac17,13"] {
            #expect(NotchGeometry.hasDynamicIsland(model: model), "\(model)")
        }
        // The same year's notched MacBook Pros, a model id that starts alike, and a Mac we can't read.
        for model in ["Mac17,6", "Mac17,7", "Mac17,8", "Mac17,9", "Mac18,1", "Mac17,1", "Mac15,6", ""] {
            #expect(!NotchGeometry.hasDynamicIsland(model: model), "\(model)")
        }
    }

    @Test func anIslandIsNeverTreatedAsACameraHousing() {
        let shape = NotchGeometry.collapsedSize(frame: screen, visibleFrame: screen, safeTop: 32, leftAuxWidth: 570, rightAuxWidth: 570,
                                                fakeNotchWidth: 0, island: 200)
        #expect(!shape.hasNotch)
        #expect(shape.size.width == NotchGeometry.browWidth)
    }

    @Test func theIslandIsAsWideAsTheGapItReportsAndOtherwiseAnEstimate() {
        #expect(NotchGeometry.islandWidth(frame: screen, safeTop: 32, leftAuxWidth: 620, rightAuxWidth: 620) == 272)
        #expect(NotchGeometry.islandWidth(frame: screen, safeTop: 0, leftAuxWidth: nil, rightAuxWidth: nil) == NotchGeometry.estimatedIslandWidth)
        #expect(NotchGeometry.islandWidth(frame: screen, safeTop: 32, leftAuxWidth: 620, rightAuxWidth: nil) == NotchGeometry.estimatedIslandWidth)
        // A gap too wide or too narrow to be an island says nothing about it.
        #expect(NotchGeometry.islandWidth(frame: screen, safeTop: 32, leftAuxWidth: 756, rightAuxWidth: 756) == NotchGeometry.estimatedIslandWidth)
    }

    @MainActor @Test func theEyebrowRestsBesideTheIslandAndOpensInTheMiddle() {
        var geometry = NotchGeometry()
        geometry.screenFrame = screen
        #expect(geometry.restShift(width: 300) == 0)
        geometry.islandWidth = 200
        // Half the island, the gap, half the eyebrow.
        #expect(geometry.restShift(width: NotchGeometry.browWidth) == 100 + 8 + NotchGeometry.browWidth / 2)
        let rect = NotchViewModel.collapsedRect(geometry: geometry, size: geometry.collapsedSize, shift: 0)
        #expect(rect.minX >= screen.midX + 100, "the eyebrow's target must clear the island")
        #expect(geometry.shapeRect(size: CGSize(width: 600, height: 200), inset: 0).midX == screen.midX)
    }

    @MainActor @Test func aShapeThatGrowsStaysClearOfTheIsland() {
        var geometry = NotchGeometry()
        geometry.screenFrame = screen
        geometry.islandWidth = 200
        // A HUD with two ears, the inline sneak peek, the approval card.
        for width in [120.0, 248, 266, 380, 500] {
            let rect = NotchViewModel.collapsedRect(geometry: geometry, size: CGSize(width: width, height: 28), shift: 0)
            #expect(rect.minX == screen.midX + 100 + 8, "\(width)")
            #expect(rect.maxX <= geometry.panelFrame.maxX, "\(width)")
        }
    }

    @Test func theReportHoldsWhatAFirstLookAtANewMacNeeds() {
        let report = NotchGeometry.screenReport(
            model: "Mac17,13", system: "27.1.0",
            screens: [.init(name: "Built-in Display", isBuiltin: true, frame: screen, visibleFrame: NSRect(x: 0, y: 0, width: 1512, height: 950),
                            scale: 2, safeTop: 32, leftAuxWidth: 620, rightAuxWidth: nil)])
        #expect(report.contains("model: Mac17,13"))
        #expect(report.contains("macOS: 27.1.0"))
        #expect(report.contains("dynamic island: yes"))
        #expect(report.contains("Built-in Display (built-in)"))
        #expect(report.contains("frame: 0 0 1512 982"))
        #expect(report.contains("visible: 0 0 1512 950"))
        #expect(report.contains("safe area top: 32"))
        #expect(report.contains("left of camera: 620"))
        #expect(report.contains("right of camera: none"))
        #expect(report.contains("scale: 2"))
    }
}
