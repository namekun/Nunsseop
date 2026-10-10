import SwiftUI

struct HeaderBar: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var weather: WeatherModel
    @ObservedObject private var updates = UpdateChecker.shared
    let height: CGFloat

    init(model: NotchViewModel, height: CGFloat) {
        self.model = model
        self.shelf = model.shelf
        self.weather = model.weather
        self.height = height
    }

    private static let slot: CGFloat = 36

    /// Room for the tab strip: left of the camera on notched displays, otherwise up to the status icons.
    /// `left` is how many tabs sit left of the camera when the tabs are split around it; nil keeps them in one row.
    private var layout: (strip: CGFloat, camera: CGFloat, side: CGFloat, left: Int?) {
        let content = model.expandedSize.width - 2 * NotchViewModel.headerInset
        let status = model.headerStatusWidth
        // Without a notch: the gaps after the strip and between the two spacers.
        guard model.geometry.hasNotch else { return (content - status - 12, 0, content, nil) }
        let camera = model.geometry.collapsedSize.width + 8
        let side = (content - camera - 12) / 2
        // Split only when both halves fit; otherwise every tab scrolls in one row on the left.
        let split = NotchViewModel.tabSplit(count: model.settings.visibleTabs.count, status: status)
        return (side, camera, side, split.side <= side + 0.5 ? split.left : nil)
    }

    var body: some View {
        let layout = layout
        let tabs = model.settings.visibleTabs
        let needed = NotchViewModel.stripWidth(tabs.count)
        HStack(spacing: 6) {
            if model.geometry.hasNotch {
                let left = layout.left.map { Array(tabs.prefix($0)) } ?? tabs
                let right = layout.left.map { Array(tabs.dropFirst($0)) } ?? []
                tabStrip(left, width: layout.strip, overflowing: layout.left == nil && needed > layout.strip)
                    .frame(width: layout.strip, alignment: .leading)
                Color.clear.frame(width: layout.camera)
                HStack(spacing: 6) {
                    if right.isEmpty {
                        Spacer(minLength: 0)
                    } else {
                        let width = NotchViewModel.stripWidth(right.count) + 2
                        tabStrip(right, width: width, overflowing: false)
                            .frame(width: width)
                            .frame(minWidth: width, maxWidth: .infinity, alignment: .leading)
                    }
                    status
                }
                .frame(width: layout.side)
            } else {
                tabStrip(tabs, width: layout.strip, overflowing: needed > layout.strip)
                    .frame(width: min(needed, layout.strip), alignment: .leading)
                Spacer(minLength: 0)
                if model.settings.headerDate && needed + 110 < layout.strip {
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

    private func tabStrip(_ tabs: [NotchTab], width: CGFloat, overflowing: Bool) -> some View {
        TabStrip(model: model, shelf: shelf, tabs: tabs, overflowing: overflowing,
                 visibleCount: max(1, Int((width + 6) / Self.slot)))
    }

    @ViewBuilder private var status: some View {
        if model.settings.headerWeather, let weather = model.weather.current {
            HStack(spacing: 4) {
                Image(systemName: WeatherModel.symbol(for: weather.code)).symbolRenderingMode(.multicolor)
                Text("\(Int(weather.temperature.rounded()))°").monospacedDigit()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))
            .help("\(weather.place) · \(Int(weather.low.rounded()))° / \(Int(weather.high.rounded()))°")
        }
        if model.settings.batteryInHeader, let power = model.hud.power {
            BatteryBadge(state: power)
        }
        Button { SettingsWindowController.shared.show() } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 26, height: 22)
                .overlay(alignment: .topTrailing) {
                    if updates.available != nil {
                        Circle().fill(Color.blue).frame(width: 6, height: 6).offset(x: -4, y: 3)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Settings")
        Button { NSApp.terminate(nil) } label: {
            Image(systemName: "power")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Quit Nunsseop")
    }
}

/// Tabs that don't fit scroll sideways, with arrows at the ends; the selected one is kept in view.
private struct TabStrip: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var shelf: ShelfStore
    let tabs: [NotchTab]
    let overflowing: Bool
    let visibleCount: Int
    @State private var leading: NotchTab?

    private var leadingIndex: Int { leading.flatMap { tabs.firstIndex(of: $0) } ?? 0 }
    private var canGoBack: Bool { overflowing && leadingIndex > 0 }
    private var canGoForward: Bool { overflowing && leadingIndex + visibleCount < tabs.count }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tabs) { tab in
                    TabButton(symbol: tab.symbol, selected: model.tab == tab,
                              badge: tab == .shelf ? shelf.items.count : tab == .notices ? model.notices.unseen : 0) { model.tab = tab }
                        .help(tab.title)
                        .id(tab)
                }
            }
            .scrollTargetLayout()
        }
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
        .onAppear { reveal(model.tab, animated: false) }
        .onChange(of: model.tab) { _, tab in reveal(tab, animated: true) }
    }

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

private struct TabButton: View {
    let symbol: String
    let selected: Bool
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? .white : .white.opacity(0.45))
                .frame(width: 30, height: 22)
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
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
