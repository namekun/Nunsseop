import AppKit
import EventKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
                                  styleMask: [.titled, .closable],
                                  backing: .buffered, defer: false)
            window.title = String(localized: "Nunsseop Settings")
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(settings: .shared))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    /// Reopens on the pane used last.
    @AppStorage("settingsPane") private var pane = "general"

    var body: some View {
        TabView(selection: $pane) {
            GeneralPane(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
            LayoutPane(settings: settings)
                .tabItem { Label("Notch", systemImage: "rectangle.topthird.inset.filled") }
                .tag("layout")
            AlertsPane(settings: settings)
                .tabItem { Label("Alerts", systemImage: "bell.badge") }
                .tag("alerts")
            ServicesPane(settings: settings)
                .tabItem { Label("Services", systemImage: "puzzlepiece.extension") }
                .tag("services")
        }
        .frame(width: 500, height: 600)
    }
}

private struct GeneralPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var updates = UpdateChecker.shared
    @State private var copiedUpdateCommand = false
    @StateObject private var launchAtLogin = LaunchAtLogin()

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
            }
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $settings.checkForUpdates)
                HStack {
                    if let release = updates.available {
                        Text("Version \(release.version) is available")
                        Spacer()
                        if UpdateChecker.brewInstalled {
                            Button(copiedUpdateCommand ? String(localized: "Copied") : String(localized: "Copy Update Command")) {
                                updates.copyUpdateCommand()
                                copiedUpdateCommand = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedUpdateCommand = false }
                            }
                        } else {
                            Button("Get Homebrew") { NSWorkspace.shared.open(URL(string: "https://brew.sh")!) }
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
                    Text(UpdateChecker.brewInstalled
                         ? String(localized: "The command goes to the clipboard. Paste it in Terminal and press Return.")
                         : String(localized: "Updates come through Homebrew. Install it, then come back here to copy the update command."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Version \(updates.currentVersion)").font(.caption).foregroundStyle(.secondary)
            }
            Section("Display") {
                Picker("Show on", selection: $settings.displayName) {
                    Text("Automatic (built-in display first)").tag("")
                    ForEach(NSScreen.screens.map(\.localizedName), id: \.self) { name in
                        Text(name).tag(name)
                    }
                    if !settings.displayName.isEmpty && !NSScreen.screens.contains(where: { $0.localizedName == settings.displayName }) {
                        Text(settings.displayName).tag(settings.displayName)
                    }
                }
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
                Button("Reset sizes") { settings.resetSizes() }
            }
            Section("Behavior") {
                SliderRow(title: "Delay before opening on hover", value: $settings.openDelay,
                          range: 0...1, unit: String(localized: "sec"), format: "%.1f")
                Toggle("Swipe down on the notch to open, up to close", isOn: $settings.swipeToOpen)
                Toggle("Swipe left or right on the Home tab to skip tracks", isOn: $settings.swipeForTracks)
            }
        }
        .formStyle(.grouped)
    }
}

/// What the notch shows: which tabs and in what order, the header, and the collapsed notch.
private struct LayoutPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                TabRow(tab: .home, settings: settings, canMoveUp: false, canMoveDown: false)
                let tabs = settings.orderedTabs
                ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                    TabRow(tab: tab, settings: settings, canMoveUp: index > 0, canMoveDown: index < tabs.count - 1)
                }
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
            }
            if settings.calendarEnabled {
                CalendarChoices(settings: settings)
            }
            Section("Header") {
                Toggle("Date", isOn: $settings.headerDate)
                Toggle("Weather", isOn: $settings.headerWeather)
                Toggle("Battery", isOn: $settings.batteryInHeader)
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

private struct TabRow: View {
    let tab: NotchTab
    @ObservedObject var settings: AppSettings
    let canMoveUp: Bool
    let canMoveDown: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tab.symbol).frame(width: 20).foregroundStyle(.secondary)
            Text(tab.title)
            Spacer()
            if tab != .home {
                Button { settings.moveTab(tab, by: -1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless).disabled(!canMoveUp)
                    .help(Text("Move up"))
                Button { settings.moveTab(tab, by: 1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless).disabled(!canMoveDown)
                    .help(Text("Move down"))
            }
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
    @State private var failed: NotifyIntegration?

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
                Text("Connecting changes the tool's own settings file and keeps the old one with a `.nunsseop-backup` extension. Sessions started afterwards send their notifications here.")
                    .font(.caption).foregroundStyle(.secondary)
                if let failed {
                    Text("Couldn't change \(failed.configURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")). Copy the hook command and add it by hand.")
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
                if MuxyNotice.isInstalled {
                    Toggle("Show notifications from agents running in Muxy", isOn: $settings.muxyNotifications)
                    Text("Read from Muxy's own notification list, so every agent and terminal in Muxy works without setup. Hidden while Muxy is in front, and skipped for tools connected above.")
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
            }
            .onAppear(perform: refreshConnections)
        }
        .formStyle(.grouped)
    }

    private func refreshConnections() {
        connected = Set(NotifyIntegration.allCases.filter(\.isInstalled))
    }

    private func toggle(_ tool: NotifyIntegration) {
        do {
            if connected.contains(tool) { try tool.uninstall() } else { try tool.install() }
            failed = nil
        } catch {
            failed = tool
        }
        refreshConnections()
    }
}

/// Features that use the network, the camera or other apps' data.
private struct ServicesPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Lyrics") {
                Toggle("Show synced lyrics (from LRCLIB)", isOn: $settings.lyricsEnabled)
            }
            Section("AI usage") {
                Toggle("Ask Anthropic for Claude's limits", isOn: $settings.claudeLimitsFromAnthropic)
                    .onChange(of: settings.claudeLimitsFromAnthropic) { _, _ in settings.claudeLimitsAsked = true }
                Text("Reads the sign-in Claude Code keeps in the Keychain and asks api.anthropic.com for your 5-hour and weekly limits about once an hour, so they also move when another app or claude.ai uses them. While that sign-in has expired they stop updating, until Claude Code signs in again. The sign-in is never changed or sent anywhere else.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Weather") {
                TextField("Weather city (e.g. Seoul)", text: $settings.weatherCity)
                Text("Weather comes from Open-Meteo. Leave the city empty to hide it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Quick search") {
                Toggle("Open Search from anywhere with a shortcut", isOn: $settings.searchHotkey)
                LabeledContent("Shortcut") {
                    ShortcutRecorder(settings: settings)
                }
                .disabled(!settings.searchHotkey)
                if settings.searchHotkey && !settings.recordingShortcut {
                    if let conflict = settings.searchHotKey.systemConflict {
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
                    } else if settings.searchShortcutTaken {
                        Text("Another app is already using this shortcut. Pick a different one.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                Text("To use Search in place of Spotlight, record ⌘Space here and turn off Spotlight’s shortcut in Keyboard Shortcuts.")
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
                Text("Adds a volume slider for each app playing sound to the Output tile in the Tools tab. macOS asks for permission to record system audio the first time you turn an app down; Nunsseop only changes the level and records nothing. Needs macOS 14.2 or later.")
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
            Button("Add an Account…") {
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value) + " " + unit).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}

/// Click, then press the keys to use. Escape cancels.
private struct ShortcutRecorder: View {
    @ObservedObject var settings: AppSettings
    @State private var monitor: Any?

    var body: some View {
        Button {
            settings.recordingShortcut ? stop() : start()
        } label: {
            Text(settings.recordingShortcut ? String(localized: "Press keys…") : settings.searchHotKey.label)
                .font(.system(size: 12, weight: .medium).monospaced())
                .frame(minWidth: 96)
        }
        .onDisappear { stop() }
    }

    private func start() {
        settings.recordingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stop()
            } else if let combo = HotKeyCombo(event: event) {
                settings.searchHotKey = combo
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        settings.recordingShortcut = false
    }
}
