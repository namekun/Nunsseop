import AppKit
import EventKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    /// Set by the notch, which owns the tour.
    var onReplayTour: (() -> Void)?

    /// Closes Settings and starts the tour again from its first step.
    func replayTour() {
        window?.close()
        onReplayTour?()
    }

    /// Settings' window: the sidebar runs up under a transparent title bar, as in System Settings.
    static func makeWindow<Content: View>(_ content: Content) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: SettingsView.size),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = String(localized: "Nunsseop Settings")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        // The content runs under the title bar, so the window is as tall as the content; it must not grow by the title bar's height.
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        window.contentView = host
        window.setFrame(NSRect(origin: .zero, size: SettingsView.size), display: false)
        return window
    }

    func show() {
        if window == nil {
            let window = Self.makeWindow(SettingsView(settings: .shared))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    // The raw values are what @AppStorage("settingsPane") has stored since the tabs had these names.
    case general, layout, alerts, alarms, services

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .layout: "Notch"
        case .alerts: "Alerts"
        case .alarms: "알람"
        case .services: "Services"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .layout: "rectangle.topthird.inset.filled"
        case .alerts: "bell.badge"
        case .alarms: "alarm"
        case .services: "puzzlepiece.extension"
        }
    }
}

/// The panes in a sidebar and the chosen one beside it, laid out like macOS System Settings.
struct SettingsView: View {
    static let size = CGSize(width: 720, height: 600)
    private static let sidebarWidth: CGFloat = 200

    @ObservedObject var settings: AppSettings
    /// Reopens on the pane used last.
    @AppStorage("settingsPane") private var pane = SettingsPane.general.rawValue

    var body: some View {
        let current = SettingsPane(rawValue: pane) ?? .general
        HStack(spacing: 0) {
            sidebar(current)
                .frame(width: Self.sidebarWidth)
                .background(Color.primary.opacity(0.04))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(current.title)
                    .font(.system(size: 22, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 24)
                    .frame(height: 56, alignment: .bottomLeading)
                switch current {
                case .general: GeneralPane(settings: settings)
                case .layout: LayoutPane(settings: settings)
                case .alerts: AlertsPane(settings: settings)
                case .alarms: AlarmsPane()
                case .services: ServicesPane(settings: settings)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
    }

    private func sidebar(_ current: SettingsPane) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsPane.allCases) { item in
                let selected = item == current
                Button { pane = item.rawValue } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 24, height: 24)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.12)))
                            .accessibilityHidden(true)
                        Text(item.title).fontWeight(selected ? .semibold : .regular)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 34)
                    .background { if selected { RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.1)) } }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 56)
    }
}

private struct GeneralPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var updates = UpdateChecker.shared
    @ObservedObject private var sparkle = SparkleUpdater.shared
    @State private var copiedUpdateCommand = false
    @StateObject private var launchAtLogin = LaunchAtLogin()

    /// Once Sparkle has failed, a copy it would update gets the DMG instead.
    private var updateWay: UpdateMethod {
        UpdateMethod.current == .sparkle && sparkle.failed ? .manual : UpdateMethod.current
    }

    private var updateNote: String {
        switch updateWay {
        case .homebrew: String(localized: "The command goes to the clipboard. Paste it in Terminal and press Return.")
        case .sparkle: String(localized: "Shows what's new, then installs the update and restarts Nunsseop.")
        case .manual: String(localized: "Open the downloaded file and drag Nunsseop to Applications, replacing this one.")
        }
    }

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open Nunsseop at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.set($0) }
                ))
                if launchAtLogin.needsApproval {
                    Text("Allow Nunsseop in System Settings › General › Login Items.")
                        .font(.caption).foregroundStyle(.orange)
                }
                if !launchAtLogin.isInApplicationsFolder {
                    Text("Move the app to /Applications before turning this on. Current location: \(Bundle.main.bundlePath)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = launchAtLogin.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                ChevronRow(title: Text(OnboardingText.showAgain)) { SettingsWindowController.shared.replayTour() }
            }
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $settings.checkForUpdates)
                HStack {
                    if let release = updates.available {
                        Text("Version \(release.version) is available")
                        Spacer()
                        switch updateWay {
                        case .homebrew:
                            Button(copiedUpdateCommand ? String(localized: "Copied") : String(localized: "Copy Update Command")) {
                                updates.copyUpdateCommand()
                                copiedUpdateCommand = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedUpdateCommand = false }
                            }
                        case .sparkle:
                            Button("Install Update") { sparkle.install() }
                        case .manual:
                            Button("Download Update") { NSWorkspace.shared.open(UpdateChecker.downloadURL(version: release.version)) }
                        }
                    } else {
                        Text(updates.isChecking ? String(localized: "Checking…")
                             : updates.failed ? String(localized: "Couldn't check for updates")
                             : updates.lastChecked == nil ? String(localized: "Not checked yet")
                             : String(localized: "Nunsseop is up to date"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Check Now") { updates.check() }.disabled(updates.isChecking)
                    }
                }
                if updates.available != nil {
                    Text(updateNote).font(.caption).foregroundStyle(.secondary)
                }
                Text("Version \(updates.currentVersion)").font(.caption).foregroundStyle(.secondary)
            }
            Section("Display") {
                Picker("Show on", selection: $settings.displayName) {
                    Text("Automatic").tag("")
                    ForEach(NSScreen.screens.map(\.localizedName), id: \.self) { name in
                        Text(name).tag(name)
                    }
                    if !settings.displayName.isEmpty && !NSScreen.screens.contains(where: { $0.localizedName == settings.displayName }) {
                        Text(settings.displayName).tag(settings.displayName)
                    }
                }
                Toggle("Move to the screen the pointer is on", isOn: $settings.followPointerAcrossDisplays)
                    .disabled(!settings.displayName.isEmpty)
                Text(settings.displayName.isEmpty
                     ? (settings.followPointerAcrossDisplays
                        ? String(localized: "The closed notch goes to whichever screen you move the pointer to.")
                        : String(localized: "The notch stays on the screen that has one, or else on the main screen."))
                     : String(localized: "The notch stays on the screen chosen above."))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show the notch when the MacBook lid is closed", isOn: $settings.showInClamshell)
                Text("In clamshell mode the notch appears as a pill on your external display.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Hide the eyebrow when it sits unused on a screen without a notch", isOn: $settings.autoHideBrow)
                if settings.autoHideBrow {
                    SliderRow(title: "Hide after", value: $settings.browHideDelay,
                              range: AppSettings.browHideDelayRange, unit: "s")
                    Text("Move the pointer to the top edge to bring it back.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Size") {
                SliderRow(title: "Expanded width", value: $settings.expandedWidth,
                          range: AppSettings.expandedWidthRange, unit: "pt")
                Toggle("Widen the notch when needed so every tab fits", isOn: $settings.widenForTabs)
                if LiquidGlass.isAvailable {
                    Toggle("Liquid Glass look", isOn: $settings.liquidGlass)
                    if settings.liquidGlass {
                        SliderRow(title: "Glass tint", value: $settings.glassTint,
                                  range: AppSettings.glassTintRange, unit: "%")
                        SliderRow(title: "Eyebrow glass tint", value: $settings.browGlassTint,
                                  range: AppSettings.glassTintRange, unit: "%")
                    }
                }
                SliderRow(title: "Expanded height", value: $settings.expandedHeight,
                          range: AppSettings.expandedHeightRange, unit: "pt")
                Toggle("Compact artwork and visualizer while playing", isOn: $settings.compactLiveActivity)
                HStack {
                    Spacer()
                    Button("Reset sizes") { settings.resetSizes() }
                }
            }
            Section("Behavior") {
                SliderRow(title: "Delay before opening on hover", value: $settings.openDelay,
                          range: 0...1, unit: String(localized: "sec"), format: "%.1f")
                Toggle("Swipe down on the notch to open, up to close", isOn: $settings.swipeToOpen)
                Toggle("Swipe left or right on the Home tab to skip tracks", isOn: $settings.swipeForTracks)
            }
            ShortcutsSection(settings: settings)
        }
        .formStyle(.grouped)
    }
}

/// One recordable shortcut for each thing the notch can be told to do from anywhere.
struct ShortcutsSection: View {
    @ObservedObject var settings: AppSettings
    /// The action a recording was refused for, and the one that already has the combination.
    @State private var refused: (action: ShortcutAction, by: ShortcutAction)?

    var body: some View {
        Section {
            ForEach(ShortcutAction.allCases) { action in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: action.title)
                            if let subtitle = action.subtitle {
                                Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        ShortcutRecorder(settings: settings, action: action, refused: $refused)
                    }
                    notes(for: action)
                }
            }
        } header: {
            Text("Shortcuts")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("New actions start empty. You'll be told when another app already uses a combination.")
                Text("To use Search in place of Spotlight, record ⌘Space here and turn off Spotlight’s shortcut in Keyboard Shortcuts.")
            }
        }
    }

    @ViewBuilder
    private func notes(for action: ShortcutAction) -> some View {
        if let refused, refused.action == action {
            Text("Already used by “\(refused.by.title)”. Pick a different combination.")
                .font(.caption).foregroundStyle(.orange)
        } else if !settings.recordingShortcut, let combo = settings.shortcut(for: action) {
            if let conflict = combo.systemConflict {
                VStack(alignment: .leading, spacing: 6) {
                    Text("macOS uses this shortcut for “\(conflict)”. Turn that off in Keyboard Shortcuts so Nunsseop gets it.")
                        .font(.caption).foregroundStyle(.orange)
                    Button("Open Keyboard Shortcuts") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
            } else if settings.shortcutsTaken.contains(action) {
                Text("Another app is already using this shortcut. Pick a different one.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }
}

/// What the notch shows: which tabs and in what order, the header, and the collapsed notch.
private struct LayoutPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                TabOrderList(settings: settings)
            } header: {
                Text("Tabs")
            } footer: {
                Text("Turned-off tabs disappear from the notch and stop running in the background.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Home tab") {
                Toggle("Calendar", isOn: $settings.calendarEnabled)
                Toggle("Reminders", isOn: $settings.remindersEnabled)
                    .disabled(!settings.calendarEnabled)
                Toggle("Show weather on Home", isOn: $settings.headerWeather)
            }
            if settings.calendarEnabled {
                CalendarChoices(settings: settings)
            }
            Section("Header") {
                Toggle("Date", isOn: $settings.headerDate)
            }
            Section("System tab") {
                Toggle("Show the battery panel in System", isOn: $settings.batteryInHeader)
            }
            Section("Collapsed notch") {
                Toggle("Artwork and visualizer while music plays", isOn: $settings.collapsedMusic)
                Toggle("Time left while a timer runs", isOn: $settings.collapsedTimer)
                Toggle("Progress while a download runs", isOn: $settings.collapsedDownloads)
                Toggle("Call app and duration during calls", isOn: $settings.callIsland)
                Picker("Left side when idle", selection: $settings.idleLeft) {
                    ForEach(IdleItem.allCases) { Text($0.title).tag($0) }
                }
                Picker("Right side when idle", selection: $settings.idleRight) {
                    ForEach(IdleItem.allCases) { Text($0.title).tag($0) }
                }
                if [settings.idleLeft, settings.idleRight].contains(where: \.usesAIUsage) {
                    Picker("AI usage limit to show", selection: $settings.idleAIWindow) {
                        ForEach(AIWindow.allCases) { Text($0.title).tag($0) }
                    }
                }
                Toggle("Title under the notch when the track changes", isOn: $settings.sneakPeekEnabled)
                Toggle("Always show the title while something is playing", isOn: $settings.sneakPeekAlways)
                    .disabled(!settings.sneakPeekEnabled)
                SliderRow(title: "Duration", value: $settings.sneakPeekDuration,
                          range: 1...10, unit: String(localized: "sec"), format: "%.1f")
                    .disabled(!settings.sneakPeekEnabled || settings.sneakPeekAlways)
                Toggle("Current lyric under the notch while playing", isOn: $settings.lyricsUnderNotch)
                    .disabled(!settings.lyricsEnabled)
            }
        }
        .formStyle(.grouped)
    }
}

/// Where a dragged tab lands in the grid of tabs (two to a row, in reading order) and how far the tabs it passes step aside, in slots.
enum TabReorder {
    /// The slot a tab dragged from slot `from` by `offset` points lands on: the cell its middle is over. Slots before `first` are fixed
    /// (Home), and the last row may be short.
    static func target(from: Int, offset: CGSize, cell: CGSize, columns: Int = 2, first: Int = 1, count: Int) -> Int {
        let rows = (count + columns - 1) / columns
        let column = min(max(from % columns + Int((offset.width / cell.width).rounded()), 0), columns - 1)
        let row = min(max(from / columns + Int((offset.height / cell.height).rounded()), 0), rows - 1)
        return min(max(row * columns + column, first), count - 1)
    }

    /// The arguments for `AppSettings.moveTabs` when the tab in grid slot `from` is dropped on slot `to`: the grid has Home in front of the
    /// tabs that `moveTabs` orders.
    static func move(from: Int, to: Int) -> (source: IndexSet, destination: Int) {
        ([from - 1], to > from ? to : to - 1)
    }

    /// -1, 0 or 1 for the tab at `index` while the tab at `from` is over `target`.
    static func shift(_ index: Int, from: Int?, target: Int?) -> Int {
        guard let from, let target, index != from else { return 0 }
        if from < target, index > from, index <= target { return -1 }
        if target < from, index >= target, index < from { return 1 }
        return 0
    }
}

/// Every tab, Home first, two to a row. A tab is dragged where it should go: it follows the pointer and the tabs it passes step aside.
/// A Form's rows don't take onMove, so the grid is one row of its own with the separators drawn in place.
private struct TabOrderList: View {
    @ObservedObject var settings: AppSettings
    @State private var dragging: NotchTab?
    @State private var offset: CGSize = .zero
    private static let columns = 2
    private static let rowHeight: CGFloat = 36

    var body: some View {
        let tabs = [NotchTab.home] + settings.orderedTabs
        let rows = (tabs.count + Self.columns - 1) / Self.columns
        GeometryReader { geometry in
            let cell = CGSize(width: geometry.size.width / CGFloat(Self.columns), height: Self.rowHeight)
            let from = dragging.flatMap { tabs.firstIndex(of: $0) }
            let target = from.map { TabReorder.target(from: $0, offset: offset, cell: cell, columns: Self.columns, count: tabs.count) }
            ZStack(alignment: .topLeading) {
                ForEach(1..<max(rows, 2), id: \.self) { row in
                    Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 0.5).offset(y: CGFloat(row) * cell.height)
                }
                Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 0.5, height: CGFloat(rows) * cell.height).offset(x: cell.width)
                ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                    let lifted = tab == dragging
                    let slot = index + (lifted ? 0 : TabReorder.shift(index, from: from, target: target))
                    TabRow(tab: tab, settings: settings)
                        .padding(.horizontal, 8)
                        .frame(width: cell.width, height: cell.height)
                        .background {
                            if lifted {
                                RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor))
                                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                            }
                        }
                        .contentShape(Rectangle())
                        .offset(x: CGFloat(slot % Self.columns) * cell.width + (lifted ? clamped(offset, from: index, cell: cell, rows: rows).width : 0),
                                y: CGFloat(slot / Self.columns) * cell.height + (lifted ? clamped(offset, from: index, cell: cell, rows: rows).height : 0))
                        .zIndex(lifted ? 1 : 0)
                        .animation(lifted ? nil : .easeOut(duration: 0.15), value: target)
                        .gesture(drag(tab, at: index, cell: cell, count: tabs.count), including: tab == .home ? .none : .all)
                }
            }
            .coordinateSpace(name: "tabOrder")
        }
        .frame(height: CGFloat(rows) * Self.rowHeight)
    }

    /// Keeps a dragged tab within the grid.
    private func clamped(_ offset: CGSize, from index: Int, cell: CGSize, rows: Int) -> CGSize {
        let column = index % Self.columns, row = index / Self.columns
        return CGSize(width: min(max(offset.width, -CGFloat(column) * cell.width), CGFloat(Self.columns - 1 - column) * cell.width),
                      height: min(max(offset.height, -CGFloat(row) * cell.height), CGFloat(rows - 1 - row) * cell.height))
    }

    private func drag(_ tab: NotchTab, at index: Int, cell: CGSize, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("tabOrder"))
            .onChanged { value in
                guard dragging == nil || dragging == tab else { return }
                dragging = tab
                offset = value.translation
            }
            .onEnded { _ in
                guard dragging == tab else { return }
                let to = TabReorder.target(from: index, offset: offset, cell: cell, columns: Self.columns, count: count)
                // Settle into the slot, then reorder in place so nothing jumps.
                withAnimation(.easeOut(duration: 0.12)) {
                    offset = CGSize(width: CGFloat(to % Self.columns - index % Self.columns) * cell.width,
                                    height: CGFloat(to / Self.columns - index / Self.columns) * cell.height)
                } completion: {
                    var still = Transaction()
                    still.disablesAnimations = true
                    withTransaction(still) {
                        if to != index {
                            let move = TabReorder.move(from: index, to: to)
                            settings.moveTabs(from: move.source, to: move.destination)
                        }
                        dragging = nil
                        offset = .zero
                    }
                }
            }
    }
}

private struct TabRow: View {
    let tab: NotchTab
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 8) {
            // Home stays first; the others are dragged into order.
            if tab == .home {
                Color.clear.frame(width: 14, height: 1)
            } else {
                Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).frame(width: 14)
                    .help(Text("Drag to reorder"))
                    .onHover { $0 ? NSCursor.openHand.push() : NSCursor.pop() }
            }
            Image(systemName: tab.symbol).frame(width: 20).foregroundStyle(.secondary)
            Text(tab.title).lineLimit(1)
            Spacer(minLength: 4)
            Toggle("", isOn: Binding(get: { settings.isVisible(tab) }, set: { settings.setVisible(tab, $0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(tab == .home)
        }
    }
}

/// Pop-ups the notch can show.
private struct AlertsPane: View {
    @ObservedObject var settings: AppSettings
    @State private var connected: Set<NotifyIntegration> = []
    @State private var failed: URL?
    @State private var connecting: ConnectRequest?
    @State private var terminals = ResumeTerminal.installed
    @State private var muxyBridge = MuxyBridge.status()
    @State private var paseo = PaseoStatus.current()
    /// Whether Hermes has the plugin turned on, when it is connected and its config says.
    @State private var hermesEnabled: Bool?

    var body: some View {
        Form {
            Section("Volume and brightness") {
                Toggle("Show volume changes in the notch", isOn: $settings.volumeHUDEnabled)
                Toggle("Replace the system volume and brightness HUD", isOn: $settings.replaceSystemHUD)
                if settings.replaceSystemHUD && !MediaKeyInterceptor.isTrusted {
                    Text("Allow Nunsseop in System Settings › Privacy & Security › Accessibility.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text("Brightness keys adjust the display under the pointer, including external displays that support DDC. Keyboard backlight keys work on keyboards that have them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Power and devices") {
                Toggle("Show when power is connected or disconnected", isOn: $settings.chargingHUDEnabled)
                Toggle("Warn at 20% battery and when fully charged", isOn: $settings.batteryAlerts)
                Toggle("Show headphone battery when they connect", isOn: $settings.headphoneHUDEnabled)
                Toggle("Show Caps Lock changes", isOn: $settings.capsLockHUD)
                Toggle("Show mouse and keyboard batteries and warn when low", isOn: $settings.peripheralBatteries)
            }
            Section("Privacy") {
                Toggle("Show when an app uses the camera or microphone", isOn: $settings.privacyIndicator)
            }
            Section("Calendar") {
                Toggle("Show events 5 minutes before they start", isOn: $settings.eventAlerts)
                    .disabled(!settings.calendarEnabled)
            }
            Section("AI usage") {
                Toggle("Tell me when Claude or Codex limits are nearly used up, and when they reset", isOn: $settings.limitAlerts)
                Text("At \(LimitAlerts.share(80)) and \(LimitAlerts.share(95)) of the 5-hour or weekly limit, once each, and again when a limit that got that far resets.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Recap last week's agent work on Mondays", isOn: $settings.weeklyRecap)
                Text("Added up on this Mac from your coding agents' session files, and never sent anywhere. The AI tab can show it any time.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Files") {
                Toggle("Add new screenshots to the shelf", isOn: $settings.screenshotsToShelf)
                Toggle("Show when downloads start and finish", isOn: $settings.downloadAlerts)
                Toggle("Add finished downloads to the shelf", isOn: $settings.downloadsToShelf)
                Toggle("Shake while dragging files to open a shelf", isOn: $settings.shakeToShelf)
            }
            Section("Notifications from local tools") {
                Toggle("Let tools on this Mac show notifications in the notch", isOn: $settings.localNotifications)
                Text("Used by Claude Code hooks and scripts. Only requests from this Mac with the secret token are accepted.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(NotifyIntegration.allCases.filter(\.isPresent)) { tool in
                    HStack {
                        Text(tool.name)
                        if connected.contains(tool) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                        Spacer()
                        Button(connected.contains(tool) ? LocalizedStringKey("Disconnect") : LocalizedStringKey("Connect")) { toggle(tool) }
                            .disabled(!settings.localNotifications && !connected.contains(tool))
                    }
                }
                Text("Connecting changes the tool's own settings file and keeps the old one with a `.nunsseop-backup` extension. Sessions started afterwards send their notifications here. Claude Code and Codex also report their sessions for the agents count in the closed notch, which works while notifications from local tools are on.")
                    .font(.caption).foregroundStyle(.secondary)
                if NotifyIntegration.allCases.contains(where: { $0.piAgent != nil && $0.isPresent }) {
                    Text("Connecting omp, omo or pi adds a file to the extensions folder of the tool. Sessions started afterwards report to the agents count and the Agents tab; Disconnect removes the file. gjc needs no setup: its sessions are read from its own state files while the count or the Agents tab is showing.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if NotifyIntegration.newerTools.contains(where: \.isPresent) {
                    Text("Gemini CLI, GitHub Copilot, Antigravity, Cursor, Hermes and Amp also report their sessions to the agents count and the Agents tab once connected.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if NotifyIntegration.hermes.isPresent {
                    if connected.contains(.hermes) {
                        HStack {
                            switch hermesEnabled {
                            case true?: Label("Enabled in Hermes", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            case false?: Text("Not enabled in Hermes yet").foregroundStyle(.orange)
                            case nil: EmptyView()
                            }
                            Spacer()
                            Button("Copy Hermes enable command") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(HermesPlugin.enableCommand, forType: .string)
                            }
                        }
                    }
                    Text("Hermes loads a plugin only after you enable it: run `hermes plugins enable nunsseop` in a terminal once.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if NotifyIntegration.amp.isPresent {
                    Text("Amp's plugin API is experimental, so an Amp update may stop this from working.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("The Agents tab lists their sessions and recent conversations with name, folder, model, context used, permission mode and last prompt, read from the tools' own session files on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Cheer when an agent finishes its turn", isOn: $settings.cheerFinished)
                Text("The eyebrow hops and the notch says which agent is done, unless its terminal is already in front. Its face also follows the agents: raised while one waits for you, low and level while they work.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Resume conversations in", selection: Binding(
                    get: { ResumeTerminal.effective(saved: settings.resumeTerminal, installed: terminals) },
                    set: { settings.resumeTerminal = $0.rawValue })) {
                    ForEach(terminals) { Text(verbatim: $0.name).tag($0) }
                }
                if connected.contains(.codex) {
                    Text("Codex asks you to review Nunsseop's hooks the next time it starts. Trust them (\"Review hooks\" lets you trust only Nunsseop's; \"Trust all and continue\" trusts every tool's new hooks); until then its sessions don't count.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                let asking = NotifyIntegration.askingForPermission(present: Set(NotifyIntegration.allCases.filter(\.isPresent)))
                if !asking.isEmpty || paseo.present {
                    Toggle("Answer permission prompts and questions in the notch", isOn: $settings.permissionPrompts)
                        .disabled(!settings.localNotifications && !asking.isEmpty)
                    if paseo.present {
                        Text("Paseo's tool approvals show in the notch too, where you can allow or deny them. “Answer in Paseo” leaves one for Paseo's own screens, and the notch lets go of one you answer there.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if asking.contains(.claudeCode) {
                        Text("Claude Code's permission prompts and questions also show in the notch, where you can allow or deny a prompt and pick the answer to a question. Answer a prompt in the terminal and the notch lets go of it; a question is asked in the terminal once you press “Answer in terminal” in the notch. If Nunsseop isn't running, the terminal asks as before. Works with Claude Code connected above. What a prompt asks is kept in memory only.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if asking.contains(.openCode) {
                        Text("OpenCode's permission prompts show in the notch too, where you can allow or deny them. OpenCode's own prompt stays in its terminal: answer in either place and the other lets go. Works with OpenCode connected above.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !asking.isDisjoint(with: [.copilot, .antigravity, .cursor]) {
                        Text("Approvals from GitHub Copilot, Antigravity and Cursor show in the notch too, where you can allow or deny them. While the notch holds one, the tool waits for it; “Answer in terminal” (“Answer in Cursor” for Cursor) hands it back. If Nunsseop isn't running, the tool asks as before.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if asking.contains(.codex) {
                        Text("Codex's approvals (commands, file edits, tools) show in the notch too. Codex asks once to trust the new hook: review it in /hooks. While the notch holds an approval, Codex shows no prompt of its own; “Answer in terminal” hands it back.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let failed {
                    Text("Couldn't change \(failed.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")). Copy the hook command and add it by hand.")
                        .font(.caption).foregroundStyle(.red)
                }
                Button("Copy Claude Code hook command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(NotifyServer.hookCommand, forType: .string)
                }
                .disabled(!settings.localNotifications)
                Button("Copy command for scripts") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(NotifyServer.scriptCommand, forType: .string)
                }
                .disabled(!settings.localNotifications)
                if Muxy.isInstalled {
                    Toggle("Show notifications from agents running in Muxy", isOn: $settings.muxyNotifications)
                    Text("Read from Muxy's own agent activity while it runs, so every agent in Muxy works without setup. Hidden while Muxy is in front, and skipped for tools connected above.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text("Muxy bridge")
                        switch muxyBridge {
                        case .running: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        case .loaded: Text("Loaded, not running").foregroundStyle(.secondary)
                        case .notLoaded: Text("Not loaded").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Show extension in Finder") { MuxyBridge.reveal() }
                    }
                    Text("Lets Nunsseop open a session's own tab in Muxy and resume conversations there. In Muxy, open Settings › Extensions › Load Unpacked…, pick the folder shown in Finder, then turn the extension on.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if Cmux.isInstalled {
                    Toggle("Show notifications from agents running in cmux", isOn: $settings.cmuxNotifications)
                    Text("Read through the cmux command inside the app, so cmux's settings stay as they are. Hidden while cmux is in front.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if Tmux.isInstalled {
                    Toggle("Show bells from tmux windows", isOn: $settings.tmuxBells)
                        .disabled(!settings.localNotifications)
                    Text("Agents ring the bell when they finish or wait for you (for Claude Code, set its notifications to the terminal bell). Nunsseop adds a hook to the running tmux server only; tmux.conf stays as it is.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if WezTerm.isInstalled {
                    HStack {
                        Text("WezTerm")
                        Spacer()
                        Button("Copy WezTerm config") {
                            TerminalBell.install()
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(WezTerm.snippet(), forType: .string)
                        }
                        .disabled(!settings.localNotifications)
                    }
                    Text("Paste it into ~/.wezterm.lua before `return config`. Bells from any WezTerm pane then show in the notch; WezTerm's config isn't changed for you.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if Herdr.isInstalled {
                    Toggle("Show when agents in herdr finish or wait for you", isOn: $settings.herdrNotifications)
                    Text("Read from herdr's socket while its server runs, so nothing needs setting up.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if paseo.present {
                    Toggle("Show when agents in Paseo finish or fail", isOn: $settings.paseoNotifications)
                    Text(verbatim: [paseo.daemonRunning ? String(localized: "Paseo daemon running") : String(localized: "Paseo daemon not running"),
                                    paseo.cliFound ? String(localized: "command line found") : String(localized: "command line not found")].joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    if paseo.daemonRunning && !paseo.approvalsAvailable {
                        Text("Paseo's daemon asks for a password or listens on a socket, so its approvals and notices can't show here.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Text("Its agents are read from Paseo's own files, and its approvals and notices from its daemon on this Mac, which Nunsseop never starts. Messages go through its command line.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .onAppear(perform: refreshConnections)
            // The bridge starts answering a moment after the user turns it on in Muxy.
            .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
                if Muxy.isInstalled { refreshBridge() }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $connecting) { request in
            ConnectSheet(request: request, cancel: { connecting = nil }, connect: {
                connecting = nil
                connect(request.tool)
            })
        }
    }

    private func refreshConnections() {
        paseo = PaseoStatus.current()
        connected = Set(NotifyIntegration.allCases.filter(\.isInstalled))
        hermesEnabled = connected.contains(.hermes) ? HermesPlugin.isEnabled() : nil
        terminals = ResumeTerminal.installed
        muxyBridge = MuxyBridge.status()
    }

    /// Only what the bridge's heartbeat changes: the hooks' config files are not read again every few seconds.
    private func refreshBridge() {
        terminals = ResumeTerminal.installed
        muxyBridge = MuxyBridge.status()
    }

    /// Connecting asks first, with the lines it would change; disconnecting doesn't.
    private func toggle(_ tool: NotifyIntegration) {
        guard !connected.contains(tool) else {
            do {
                try tool.uninstall()
                failed = nil
            } catch {
                failed = tool.file(failing: error)
            }
            return refreshConnections()
        }
        do {
            if let request = ConnectRequest(tool: tool, changes: try tool.changes()) {
                connecting = request
            } else {
                connect(tool)
            }
        } catch {
            failed = tool.file(failing: error)
        }
    }

    private func connect(_ tool: NotifyIntegration) {
        do {
            try tool.install()
            failed = nil
        } catch {
            failed = tool.file(failing: error)
        }
        refreshConnections()
    }
}

/// Features that use the network, the camera or other apps' data.
private struct ServicesPane: View {
    @ObservedObject var settings: AppSettings
    @State private var statusLine = ClaudeStatusLine.State.notConnected
    @State private var statusLineFailed = false
    @State private var statusLineLost = false

    var body: some View {
        Form {
            Section("Lyrics") {
                Toggle("Show synced lyrics (from LRCLIB)", isOn: $settings.lyricsEnabled)
            }
            Section("AI usage") {
                Toggle("Ask Anthropic for Claude's limits", isOn: $settings.claudeLimitsFromAnthropic)
                    .onChange(of: settings.claudeLimitsFromAnthropic) { _, _ in settings.claudeLimitsAsked = true }
                Text("Reads the sign-in Claude Code keeps in the Keychain and asks api.anthropic.com for your 5-hour and weekly limits about once an hour, so they also move when another app or claude.ai uses them. While that sign-in has expired they stop updating, until Claude Code runs again and renews it. The sign-in is never changed or sent anywhere else.")
                    .font(.caption).foregroundStyle(.secondary)
                if NotifyIntegration.claudeCode.isPresent || statusLine != .notConnected {
                    HStack {
                        Text("Claude Code status line")
                        if statusLine == .connected {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                        Spacer()
                        Button(statusLine == .connected ? LocalizedStringKey("Disconnect") : LocalizedStringKey("Connect"), action: toggleStatusLine)
                    }
                    Text("Takes Claude's 5-hour and weekly limits from what Claude Code passes to its status line, and keeps running your own status line as before. Nothing leaves this Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                    switch statusLine {
                    case .connected:
                        Text("Connected. The limits update while Claude Code runs.").font(.caption).foregroundStyle(.secondary)
                    case .notConnected:
                        Text("Not connected.").font(.caption).foregroundStyle(.secondary)
                    case .changed:
                        Text("Something else has changed Claude Code's status line since you connected. Connect again to use the new one.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if statusLineLost {
                        Text("Your previous status line command couldn't be restored. After you disconnect, you can set it again in ~/.claude/settings.json.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if statusLineFailed {
                        Text("Couldn't change Claude Code's settings.").font(.caption).foregroundStyle(.red)
                    }
                }
            }
            Section("Weather") {
                TextField("Weather city (e.g. Seoul)", text: $settings.weatherCity)
                Text("Weather comes from Open-Meteo. Leave the city empty to hide it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Clipboard") {
                Toggle("Remove tracking parameters from copied links", isOn: $settings.cleanLinks)
                    .disabled(!settings.clipboardTab)
                Text("Removes utm_ and similar tracking parameters when you copy a single link. Works while the Clipboard tab is on.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Screen recording") {
                Toggle("Record microphone audio", isOn: $settings.recordAudio)
                Text("Recordings are saved where screenshots go and added to the shelf. Screen Recording permission is needed the first time.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("App volume") {
                Toggle("Per-app volume (experimental)", isOn: $settings.perAppVolume)
                    .disabled(!AppVolumeModel.isSupported && !settings.perAppVolume)
                Text("Adds a volume slider for each app playing sound to the Output panel in the Tools tab. macOS asks for permission to record system audio the first time you turn an app down; Nunsseop only changes the level and records nothing. Needs macOS 14.2 or later.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Mirror") {
                Picker("Camera", selection: $settings.mirrorCameraID) {
                    Text("System default").tag("")
                    ForEach(MirrorModel.cameras, id: \.uniqueID) { camera in
                        Text(camera.localizedName).tag(camera.uniqueID)
                    }
                }
                .disabled(!settings.mirrorEnabled)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshStatusLine)
    }

    private func toggleStatusLine() {
        do {
            if statusLine == .connected { try ClaudeStatusLine.disconnect() } else { try ClaudeStatusLine.connect() }
            statusLineFailed = false
        } catch {
            statusLineFailed = true
        }
        refreshStatusLine()
    }

    private func refreshStatusLine() {
        statusLine = ClaudeStatusLine.state()
        statusLineLost = ClaudeStatusLine.originalLost()
    }
}

/// The calendars macOS knows about, grouped by account, each with a switch for the Home tab.
private struct CalendarChoices: View {
    @ObservedObject var settings: AppSettings
    @State private var groups: [(account: String, calendars: [EKCalendar])] = []
    @State private var expandedAccounts: Set<String> = []
    private let store = EKEventStore()

    var body: some View {
        Section {
            if EKEventStore.authorizationStatus(for: .event) != .fullAccess {
                Text("Allow calendar access on the Home tab to choose calendars.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if groups.isEmpty {
                Text("No calendars yet.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(groups, id: \.account) { group in
                let switches = group.calendars.map { shown($0.calendarIdentifier) }
                DisclosureGroup(isExpanded: expanded(group.account)) {
                    // Rows inside a disclosure group lose the form's row spacing, so give it back,
                    // with a gap above the first one so it doesn't touch the account row.
                    VStack(spacing: 0) {
                        ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                            Toggle(isOn: shown(calendar.calendarIdentifier)) {
                                HStack(spacing: 8) {
                                    Circle().fill(Color(nsColor: calendar.color ?? .systemBlue)).frame(width: 8, height: 8)
                                    Text(calendar.title)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .padding(.top, 6)
                    .padding(.leading, 6)
                    // Line the switches up with the account's switch, which sits inset from the edge.
                    .padding(.trailing, 4)
                } label: {
                    // One switch for the whole account; it shows a mixed state when only some calendars are on.
                    Toggle(sources: switches, isOn: \.self) {
                        HStack(spacing: 6) {
                            Text(group.account).fontWeight(.semibold)
                            Text("\(switches.filter(\.wrappedValue).count)/\(switches.count)")
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
            ChevronRow(title: Text("Add an Account…")) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!)
            }
        } header: {
            Text("Calendars")
        } footer: {
            Text("Google, iCloud, Exchange and other accounts added to macOS appear here.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear(perform: load)
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in load() }
    }

    private func expanded(_ account: String) -> Binding<Bool> {
        Binding {
            expandedAccounts.contains(account)
        } set: { open in
            if open { expandedAccounts.insert(account) } else { expandedAccounts.remove(account) }
        }
    }

    private func shown(_ id: String) -> Binding<Bool> {
        Binding {
            !settings.hiddenCalendarIDs.contains(id)
        } set: { show in
            settings.hiddenCalendarIDs.removeAll { $0 == id }
            if !show { settings.hiddenCalendarIDs.append(id) }
        }
    }

    private func load() {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { groups = []; return }
        let calendars = store.calendars(for: .event)
        groups = Dictionary(grouping: calendars) { $0.source.title }
            .map { (account: $0.key, calendars: $0.value.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) }
            .sorted { $0.account.localizedStandardCompare($1.account) == .orderedAscending }
    }
}

private struct SliderRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    var format = "%.0f"

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
            Spacer(minLength: 8)
            Slider(value: $value, in: range)
                .frame(width: 150)
                .accessibilityLabel(Text(title))
            Text(String(format: format, value) + " " + unit)
                .monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
    }
}

/// A row that does something when clicked, marked with a chevron like the rows of System Settings that open a page.
private struct ChevronRow: View {
    let title: Text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                title
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Click, then press the keys to use. Escape cancels.
private struct ShortcutRecorder: View {
    @ObservedObject var settings: AppSettings
    let action: ShortcutAction
    @Binding var refused: (action: ShortcutAction, by: ShortcutAction)?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        let combo = settings.shortcut(for: action)
        HStack(spacing: 4) {
            Button {
                recording ? stop() : start()
            } label: {
                if let combo, !recording {
                    Text(verbatim: combo.label).font(.system(size: 12, weight: .medium).monospaced()).frame(minWidth: 104)
                } else {
                    Text(recording ? String(localized: "Press keys…") : String(localized: "Record shortcut"))
                        .font(.system(size: 12)).foregroundStyle(recording ? .primary : .secondary).frame(minWidth: 104)
                }
            }
            // Always there, so the buttons line up whether or not there is a shortcut to remove.
            let removable = combo != nil && !recording
            Button {
                refused = nil
                settings.clearShortcut(action)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(removable ? 1 : 0)
            .disabled(!removable)
            .accessibilityHidden(!removable)
            .help(Text("Remove shortcut"))
            .accessibilityLabel(Text("Remove shortcut"))
        }
        .onDisappear { stop() }
    }

    private func start() {
        refused = nil
        settings.recordingShortcut = true
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stop()
            } else if let combo = HotKeyCombo(event: event) {
                if case .takenBy(let other) = settings.assign(combo, to: action) { refused = (action, other) }
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { settings.recordingShortcut = false }
        recording = false
    }
}
