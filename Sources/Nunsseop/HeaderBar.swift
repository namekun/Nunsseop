import SwiftUI

/// The tab bar: every tab in one row, the current one a capsule with its title beside the icon, then Settings and Quit.
struct HeaderBar: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var shelf: ShelfStore
    let height: CGFloat

    init(model: NotchViewModel, height: CGFloat) {
        self.model = model
        self.shelf = model.shelf
        self.height = height
    }

    /// Room for the tab strip: left of the camera on notched displays, otherwise up to the status icons. Tabs that don't fit scroll.
    /// `label` is the room the current tab's title takes beyond an icon (see `NotchViewModel.tabLabelWidth`), kept for every tab so
    /// that choosing another does not move anything.
    nonisolated static func layout(width: CGFloat, status: CGFloat, hasNotch: Bool, notchWidth: CGFloat)
        -> (strip: CGFloat, camera: CGFloat, side: CGFloat) {
        let content = width - 2 * NotchViewModel.headerInset
        // Without a notch: the gaps after the strip and between the two spacers.
        guard hasNotch else { return (content - status - 12, 0, content) }
        let camera = notchWidth + 8
        let side = (content - camera - 12) / 2
        return (side, camera, side)
    }

    var body: some View {
        HeaderRow(tabs: model.settings.visibleTabs, selected: model.tab,
                  badges: [.shelf: shelf.items.count, .notices: model.notices.unseen],
                  width: model.expandedSize.width, hasNotch: model.geometry.hasNotch, notchWidth: model.geometry.collapsedSize.width,
                  showsDate: model.settings.headerDate, height: height) {
            model.recap.close()
            model.tab = $0
        }
    }
}

/// What HeaderBar draws, from plain values so that it can be laid out without a notch model.
struct HeaderRow: View {
    let tabs: [NotchTab]
    let selected: NotchTab
    let badges: [NotchTab: Int]
    let width: CGFloat
    let hasNotch: Bool
    let notchWidth: CGFloat
    let showsDate: Bool
    let height: CGFloat
    let select: (NotchTab) -> Void
    @ObservedObject private var updates = UpdateChecker.shared

    var body: some View {
        let label = NotchViewModel.tabLabelWidth(tabs)
        let layout = HeaderBar.layout(width: width, status: NotchViewModel.headerStatusWidth, hasNotch: hasNotch, notchWidth: notchWidth)
        let needed = NotchViewModel.stripWidth(tabs.count) + label
        HStack(spacing: 6) {
            if hasNotch {
                tabStrip(tabs, width: layout.strip, label: label, overflowing: needed > layout.strip)
                    .frame(width: layout.strip, alignment: .leading)
                Color.clear.frame(width: layout.camera)
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    status
                }
                .frame(width: layout.side)
            } else {
                tabStrip(tabs, width: layout.strip, label: label, overflowing: needed > layout.strip)
                    .frame(width: min(needed, layout.strip), alignment: .leading)
                Spacer(minLength: 0)
                if showsDate && needed + 110 < layout.strip {
                    // Re-reads the clock each minute so the date turns over at midnight; only this text redraws.
                    TimelineView(.everyMinute) { context in
                        Text(context.date, format: .dateTime.month().day().weekday(.abbreviated))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                Spacer(minLength: 0)
                status
            }
        }
        .frame(height: max(height, 24))
    }

    private func tabStrip(_ tabs: [NotchTab], width: CGFloat, label: CGFloat, overflowing: Bool) -> some View {
        TabStrip(tabs: tabs, selected: selected, badges: badges, overflowing: overflowing,
                 visibleCount: max(1, Int((width + NotchViewModel.tabGap - label) / NotchViewModel.tabSlot)), select: select)
    }

    @ViewBuilder private var status: some View {
        Button { SettingsWindowController.shared.show() } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 26, height: 24)
                .overlay(alignment: .topTrailing) {
                    if updates.available != nil {
                        Circle().fill(Color.blue).frame(width: 6, height: 6).offset(x: -4, y: 3)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Settings")
        .accessibilityLabel("Settings")
        Button { NSApp.terminate(nil) } label: {
            Image(systemName: "power")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Quit Nunsseop")
        .accessibilityLabel("Quit Nunsseop")
    }
}

/// Whether tabs lie past an end of the strip, so that end gets an arrow. Within a point counts as in view, so rounding
/// never leaves an arrow over a tab that is in full view.
enum TabArrows {
    static func hidesBefore(firstMinX: CGFloat) -> Bool { firstMinX < -1 }
    static func hidesAfter(lastMaxX: CGFloat, width: CGFloat) -> Bool { lastMaxX > width + 1 }
}

/// Tabs that don't fit scroll sideways, with arrows at the ends; the selected one is kept in view.
private struct TabStrip: View {
    let tabs: [NotchTab]
    let selected: NotchTab
    let badges: [NotchTab: Int]
    let overflowing: Bool
    let visibleCount: Int
    let select: (NotchTab) -> Void
    @State private var leading: NotchTab?
    @State private var dragHover = TabDragHover()
    /// Where the row of tabs starts and ends in the strip, and how wide the strip is: the arrows go by these,
    /// since how many tabs fit changes with the selected one's title.
    @State private var firstMinX: CGFloat = 0
    @State private var lastMaxX: CGFloat = 0
    @State private var stripWidth: CGFloat = 0

    private var leadingIndex: Int { leading.flatMap { tabs.firstIndex(of: $0) } ?? 0 }
    private var canGoBack: Bool { overflowing && TabArrows.hidesBefore(firstMinX: firstMinX) }
    private var canGoForward: Bool { overflowing && TabArrows.hidesAfter(lastMaxX: lastMaxX, width: stripWidth) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: NotchViewModel.tabGap) {
                ForEach(tabs) { tab in
                    TabButton(tab: tab, selected: selected == tab, badge: badges[tab] ?? 0) { select(tab) }
                        .help(tab.title)
                        .id(tab)
                        .onDrop(of: tab == .agents ? [.fileURL] : [], delegate: TabDragHoverDelegate(hover: dragHover) { select(tab) })
                }
            }
            .scrollTargetLayout()
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frame in
                firstMinX = frame.minX
                lastMaxX = frame.maxX
            }
        }
        .coordinateSpace(.named(Self.space))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stripWidth = $0 }
        .scrollPosition(id: $leading, anchor: .leading)
        .scrollDisabled(!overflowing)
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [canGoBack ? .clear : .black, .black], startPoint: .leading, endPoint: .trailing).frame(width: 22)
                Color.black
                LinearGradient(colors: [.black, canGoForward ? .clear : .black], startPoint: .leading, endPoint: .trailing).frame(width: 22)
            }
        }
        .overlay(alignment: .leading) { if canGoBack { arrow("chevron.left", fade: .leading) { page(-1) } } }
        .overlay(alignment: .trailing) { if canGoForward { arrow("chevron.right", fade: .trailing) { page(1) } } }
        .onAppear { reveal(selected, animated: false) }
        .onChange(of: selected) { _, tab in reveal(tab, animated: true) }
    }

    private static let space = "tabStrip"

    /// Scrolls just enough to bring the tab into view.
    private func reveal(_ tab: NotchTab, animated: Bool) {
        guard overflowing, let index = tabs.firstIndex(of: tab) else { return }
        var target = leadingIndex
        if index < target { target = index }
        if index >= target + visibleCount { target = index - visibleCount + 1 }
        target = min(max(0, target), max(0, tabs.count - visibleCount))
        guard target != leadingIndex || leading == nil else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { leading = tabs[target] }
        } else {
            leading = tabs[target]
        }
    }

    private func page(_ direction: Int) {
        let step = max(1, visibleCount - 1)
        let target = min(max(0, leadingIndex + direction * step), max(0, tabs.count - visibleCount))
        withAnimation(.easeOut(duration: 0.25)) { leading = tabs[target] }
    }

    private func arrow(_ symbol: String, fade: Edge, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 22, height: 22)
                .background(
                    LinearGradient(colors: [.black.opacity(0), .black],
                                   startPoint: fade == .trailing ? .leading : .trailing,
                                   endPoint: fade == .trailing ? .trailing : .leading)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// An icon with, when it is the current tab, its title beside it in a capsule. 24 pt tall, 26 wide at least.
struct TabButton: View {
    let tab: NotchTab
    let selected: Bool
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tab.symbol).font(.system(size: 11, weight: .semibold)).accessibilityHidden(true)
                if selected {
                    Text(verbatim: tab.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        .frame(maxWidth: NotchViewModel.tabTitleCap)
                }
            }
            .foregroundStyle(selected ? .white : .white.opacity(0.55))
            .padding(.leading, selected ? 9 : 0)
            .padding(.trailing, selected ? (badge > 0 ? 15 : 9) : 0)
            .frame(minWidth: 26, minHeight: 24)
            .background(Capsule().fill(.white.opacity(selected ? 0.16 : 0)))
            .overlay(alignment: .topTrailing) {
                if badge > 0 {
                    Text(badge > 9 ? "9+" : "\(badge)")
                        .font(.system(size: 8, weight: .bold).monospacedDigit())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 3)
                        .background(Capsule().fill(.white))
                        // Inside the button on every side: the tab row scrolls and clips anything past it,
                        // so a badge on the tab at the end of the row, or a wider one, lost its edge.
                        .padding(.top, 1)
                        .padding(.trailing, 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
