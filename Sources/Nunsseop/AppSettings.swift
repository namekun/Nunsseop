import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// Below these every tab no longer fits without clipping.
    nonisolated static let expandedWidthRange: ClosedRange<Double> = 540...780
    nonisolated static let expandedHeightRange: ClosedRange<Double> = 180...260
    nonisolated static let browHideDelayRange: ClosedRange<Double> = 3...60
    /// At 100% the glass gives way to solid black.
    nonisolated static let glassTintRange: ClosedRange<Double> = 20...100

    private let defaults = UserDefaults.standard

    @Published var expandedWidth: Double = AppSettings.load("expandedWidth", default: 620.0, in: expandedWidthRange) { didSet { save(expandedWidth, "expandedWidth") } }
    @Published var expandedHeight: Double = AppSettings.load("expandedHeight", default: 196.0, in: expandedHeightRange) { didSet { save(expandedHeight, "expandedHeight") } }
    /// Width of the collapsed shape on screens without a camera housing.
    /// Smaller artwork/visualizer "ears" beside the collapsed notch while music plays.
    @Published var compactLiveActivity: Bool = AppSettings.load("compactLiveActivity", default: false) { didSet { save(compactLiveActivity, "compactLiveActivity") } }

    /// Shows title and artist under the collapsed notch when the track or play state changes.
    @Published var sneakPeekEnabled: Bool = AppSettings.load("sneakPeekEnabled", default: true) { didSet { save(sneakPeekEnabled, "sneakPeekEnabled") } }
    @Published var sneakPeekAlways: Bool = AppSettings.load("sneakPeekAlways", default: false) { didSet { save(sneakPeekAlways, "sneakPeekAlways") } }
    @Published var sneakPeekDuration: Double = AppSettings.load("sneakPeekDuration", default: 3.0) { didSet { save(sneakPeekDuration, "sneakPeekDuration") } }
    /// Seconds the pointer must rest on the notch before it opens.
    @Published var openDelay: Double = AppSettings.load("openDelay", default: 0.1) { didSet { save(openDelay, "openDelay") } }

    @Published var volumeHUDEnabled: Bool = AppSettings.load("volumeHUDEnabled", default: true) { didSet { save(volumeHUDEnabled, "volumeHUDEnabled") } }
    /// Takes over the volume/brightness keys so only the notch HUD shows.
    @Published var replaceSystemHUD: Bool = AppSettings.load("replaceSystemHUD", default: false) { didSet { save(replaceSystemHUD, "replaceSystemHUD") } }
    @Published var batteryInHeader: Bool = AppSettings.load("batteryInHeader", default: true) { didSet { save(batteryInHeader, "batteryInHeader") } }
    @Published var chargingHUDEnabled: Bool = AppSettings.load("chargingHUDEnabled", default: true) { didSet { save(chargingHUDEnabled, "chargingHUDEnabled") } }
    @Published var headphoneHUDEnabled: Bool = AppSettings.load("headphoneHUDEnabled", default: true) { didSet { save(headphoneHUDEnabled, "headphoneHUDEnabled") } }
    @Published var calendarEnabled: Bool = AppSettings.load("calendarEnabled", default: true) { didSet { save(calendarEnabled, "calendarEnabled") } }
    /// Calendars left out of the Home tab. Stored as hidden so newly added calendars show up.
    @Published var hiddenCalendarIDs: [String] = AppSettings.load("hiddenCalendarIDs", default: []) { didSet { save(hiddenCalendarIDs, "hiddenCalendarIDs") } }
    /// Shows a timed event under the notch five minutes before it starts.
    @Published var eventAlerts: Bool = AppSettings.load("eventAlerts", default: true) { didSet { save(eventAlerts, "eventAlerts") } }
    @Published var remindersEnabled: Bool = AppSettings.load("remindersEnabled", default: true) { didSet { save(remindersEnabled, "remindersEnabled") } }
    /// NSScreen.localizedName of the display to use; empty means automatic.
    @Published var displayName: String = AppSettings.load("displayName", default: "") { didSet { save(displayName, "displayName") } }
    /// Whether the notch shows on external displays while the MacBook lid is closed.
    @Published var showInClamshell: Bool = AppSettings.load("showInClamshell", default: true) { didSet { save(showInClamshell, "showInClamshell") } }
    /// Fades the eyebrow out on displays without a notch after it sat unused; the pointer at the top edge brings it back.
    @Published var autoHideBrow: Bool = AppSettings.load("autoHideBrow", default: true) { didSet { save(autoHideBrow, "autoHideBrow") } }
    @Published var browHideDelay: Double = AppSettings.load("browHideDelay", default: 8.0) { didSet { save(browHideDelay, "browHideDelay") } }
    @Published var checkForUpdates: Bool = AppSettings.load("checkForUpdates", default: true) { didSet { save(checkForUpdates, "checkForUpdates") } }
    @Published var batteryAlerts: Bool = AppSettings.load("batteryAlerts", default: true) { didSet { save(batteryAlerts, "batteryAlerts") } }
    @Published var capsLockHUD: Bool = AppSettings.load("capsLockHUD", default: true) { didSet { save(capsLockHUD, "capsLockHUD") } }
    @Published var screenshotsToShelf: Bool = AppSettings.load("screenshotsToShelf", default: true) { didSet { save(screenshotsToShelf, "screenshotsToShelf") } }
    /// Shows the notifications agents running in Muxy send.
    @Published var muxyNotifications: Bool = AppSettings.load("muxyNotifications", default: true) { didSet { save(muxyNotifications, "muxyNotifications") } }
    @Published var cmuxNotifications: Bool = AppSettings.load("cmuxNotifications", default: true) { didSet { save(cmuxNotifications, "cmuxNotifications") } }
    @Published var herdrNotifications: Bool = AppSettings.load("herdrNotifications", default: true) {
        didSet { save(herdrNotifications, "herdrNotifications"); updateWatchesHerdr() }
    }
    /// herdr is watched for its notifications, or for the agents count in the closed notch, or both.
    @Published private(set) var watchesHerdr = false
    /// Shows bells from tmux windows, through a hook on the running tmux server.
    @Published var tmuxBells: Bool = AppSettings.load("tmuxBells", default: true) { didSet { save(tmuxBells, "tmuxBells") } }
    /// Asks Anthropic for Claude's limits with Claude Code's sign-in. Off until the user agrees, in the AI tab or Settings.
    @Published var claudeLimitsFromAnthropic: Bool = AppSettings.load("claudeLimitsFromAnthropic", default: false) {
        didSet { save(claudeLimitsFromAnthropic, "claudeLimitsFromAnthropic"); ClaudeUsageAPI.isEnabled = claudeLimitsFromAnthropic }
    }
    /// The AI tab asked once whether to turn that on; asked or answered, it doesn't ask again.
    @Published var claudeLimitsAsked: Bool = AppSettings.load("claudeLimitsAsked", default: false) { didSet { save(claudeLimitsAsked, "claudeLimitsAsked") } }
    @Published var localNotifications: Bool = AppSettings.load("localNotifications", default: true) { didSet { save(localNotifications, "localNotifications") } }
    @Published var timerTab: Bool = AppSettings.load("timerTab", default: true) { didSet { save(timerTab, "timerTab") } }
    @Published var shelfTab: Bool = AppSettings.load("shelfTab", default: true) { didSet { save(shelfTab, "shelfTab") } }
    @Published var searchTab: Bool = AppSettings.load("searchTab", default: true) { didSet { save(searchTab, "searchTab") } }
    @Published var emojiTab: Bool = AppSettings.load("emojiTab", default: true) { didSet { save(emojiTab, "emojiTab") } }
    @Published var aiTab: Bool = AppSettings.load("aiTab", default: true) { didSet { save(aiTab, "aiTab") } }
    /// Grows the expanded notch past its set width, as far as the screen allows, so every tab fits.
    @Published var widenForTabs: Bool = AppSettings.load("widenForTabs", default: true) { didSet { save(widenForTabs, "widenForTabs") } }
    /// Liquid Glass surfaces on macOS 26 and later.
    @Published var liquidGlass: Bool = AppSettings.load("liquidGlass", default: true) { didSet { save(liquidGlass, "liquidGlass") } }
    /// How dark the expanded notch's glass is, in percent.
    /// Glass tint of the collapsed eyebrow on displays without a notch, set apart from the expanded notch's.
    @Published var browGlassTint: Double = AppSettings.load("browGlassTint", default: 55.0, in: glassTintRange) { didSet { save(browGlassTint, "browGlassTint") } }
    @Published var glassTint: Double = AppSettings.load("glassTint", default: 55.0, in: glassTintRange) { didSet { save(glassTint, "glassTint") } }
    /// A system-wide shortcut opens the Search tab from anywhere.
    @Published var searchHotkey: Bool = AppSettings.load("searchHotkey", default: true) { didSet { save(searchHotkey, "searchHotkey") } }
    @Published var searchHotKey: HotKeyCombo = AppSettings.loadSearchHotKey() {
        didSet {
            defaults.set(Int(searchHotKey.keyCode), forKey: "searchHotKeyCode")
            defaults.set(Int(searchHotKey.modifiers), forKey: "searchHotKeyModifiers")
            defaults.set(searchHotKey.key, forKey: "searchHotKeyName")
        }
    }
    /// Set when another app already holds the chosen shortcut.
    @Published var searchShortcutTaken = false
    /// While a new shortcut is being recorded the current one is released.
    @Published var recordingShortcut = false
    @Published var peripheralBatteries: Bool = AppSettings.load("peripheralBatteries", default: true) { didSet { save(peripheralBatteries, "peripheralBatteries") } }
    /// Shows when any app uses the camera or microphone.
    @Published var privacyIndicator: Bool = AppSettings.load("privacyIndicator", default: true) { didSet { save(privacyIndicator, "privacyIndicator") } }
    @Published var recordAudio: Bool = AppSettings.load("recordAudio", default: false) { didSet { save(recordAudio, "recordAudio") } }
    /// A volume slider for each app playing sound, in the Tools tab. Experimental, so off by default.
    @Published var perAppVolume: Bool = AppSettings.load("perAppVolume", default: false) { didSet { save(perAppVolume, "perAppVolume") } }
    /// Order of the tabs after Home, as NotchTab raw values.
    @Published var tabOrder: [String] = AppSettings.load("tabOrder", default: NotchTab.allCases.filter { $0 != .home }.map(\.rawValue)) { didSet { save(tabOrder, "tabOrder") } }
    @Published var headerDate: Bool = AppSettings.load("headerDate", default: true) { didSet { save(headerDate, "headerDate") } }
    @Published var headerWeather: Bool = AppSettings.load("headerWeather", default: true) { didSet { save(headerWeather, "headerWeather") } }
    @Published var collapsedMusic: Bool = AppSettings.load("collapsedMusic", default: true) { didSet { save(collapsedMusic, "collapsedMusic") } }
    @Published var collapsedTimer: Bool = AppSettings.load("collapsedTimer", default: true) { didSet { save(collapsedTimer, "collapsedTimer") } }
    @Published var collapsedDownloads: Bool = AppSettings.load("collapsedDownloads", default: true) { didSet { save(collapsedDownloads, "collapsedDownloads") } }
    /// Shows the call app and how long the call has run while one is in progress.
    @Published var callIsland: Bool = AppSettings.load("callIsland", default: true) { didSet { save(callIsland, "callIsland") } }
    @Published var idleLeft: IdleItem = AppSettings.load("idleLeft", default: .none) { didSet { save(idleLeft.rawValue, "idleLeft"); updateWatchesHerdr() } }
    @Published var idleRight: IdleItem = AppSettings.load("idleRight", default: .none) { didSet { save(idleRight.rawValue, "idleRight"); updateWatchesHerdr() } }

    private func updateWatchesHerdr() {
        let wanted = herdrNotifications || idleLeft == .agents || idleRight == .agents
        if wanted != watchesHerdr { watchesHerdr = wanted }
    }
    @Published var idleAIWindow: AIWindow = AppSettings.load("idleAIWindow", default: .tighter) { didSet { save(idleAIWindow.rawValue, "idleAIWindow") } }
    @Published var systemTab: Bool = AppSettings.load("systemTab", default: true) { didSet { save(systemTab, "systemTab") } }
    @Published var appsTab: Bool = AppSettings.load("appsTab", default: true) { didSet { save(appsTab, "appsTab") } }
    @Published var lyricsEnabled: Bool = AppSettings.load("lyricsEnabled", default: true) { didSet { save(lyricsEnabled, "lyricsEnabled") } }
    /// Keeps the current lyric line under the notch while music plays.
    @Published var lyricsUnderNotch: Bool = AppSettings.load("lyricsUnderNotch", default: false) { didSet { save(lyricsUnderNotch, "lyricsUnderNotch") } }
    /// City for the header weather chip; empty hides it.
    @Published var weatherCity: String = AppSettings.load("weatherCity", default: "") { didSet { save(weatherCity, "weatherCity") } }
    @Published var downloadAlerts: Bool = AppSettings.load("downloadAlerts", default: true) { didSet { save(downloadAlerts, "downloadAlerts") } }
    /// Shaking the pointer while dragging files shows a drop target that adds them to the shelf.
    @Published var shakeToShelf: Bool = AppSettings.load("shakeToShelf", default: true) { didSet { save(shakeToShelf, "shakeToShelf") } }
    @Published var downloadsToShelf: Bool = AppSettings.load("downloadsToShelf", default: false) { didSet { save(downloadsToShelf, "downloadsToShelf") } }
    /// Also controls whether copied text is recorded at all.
    @Published var clipboardTab: Bool = AppSettings.load("clipboardTab", default: true) { didSet { save(clipboardTab, "clipboardTab") } }
    /// Removes tracking parameters from copied links while the clipboard is watched.
    @Published var cleanLinks: Bool = AppSettings.load("cleanLinks", default: true) { didSet { save(cleanLinks, "cleanLinks") } }
    @Published var notesTab: Bool = AppSettings.load("notesTab", default: true) { didSet { save(notesTab, "notesTab") } }
    @Published var toolsTab: Bool = AppSettings.load("toolsTab", default: true) { didSet { save(toolsTab, "toolsTab") } }
    /// Off by default: macOS's Notification Center covers most of it; this is for going back to the exact terminal pane.
    @Published var noticesTab: Bool = AppSettings.load("noticesTab", default: false) { didSet { save(noticesTab, "noticesTab") } }
    @Published var mirrorEnabled: Bool = AppSettings.load("mirrorEnabled", default: true) { didSet { save(mirrorEnabled, "mirrorEnabled") } }
    /// AVCaptureDevice.uniqueID; empty means the system default camera.
    @Published var mirrorCameraID: String = AppSettings.load("mirrorCameraID", default: "") { didSet { save(mirrorCameraID, "mirrorCameraID") } }
    /// Two-finger swipe down on the notch opens it, swipe up closes it.
    @Published var swipeToOpen: Bool = AppSettings.load("swipeToOpen", default: true) { didSet { save(swipeToOpen, "swipeToOpen") } }
    /// Two-finger swipe left/right on the Home tab skips tracks.
    @Published var swipeForTracks: Bool = AppSettings.load("swipeForTracks", default: true) { didSet { save(swipeForTracks, "swipeForTracks") } }

    private init() {
        updateWatchesHerdr()
        ClaudeUsageAPI.isEnabled = claudeLimitsFromAnthropic
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    // Unset keys fall back to the default; set ones read the way UserDefaults always did,
    // so a "NO" passed as a launch argument still turns a switch off.
    nonisolated static func load(_ key: String, default value: Bool, from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) == nil ? value : defaults.bool(forKey: key)
    }

    nonisolated static func load(_ key: String, default value: Double, from defaults: UserDefaults = .standard) -> Double {
        defaults.object(forKey: key) == nil ? value : defaults.double(forKey: key)
    }

    /// Sizes saved before the minimums were raised come back clamped.
    nonisolated static func load(_ key: String, default value: Double, in range: ClosedRange<Double>, from defaults: UserDefaults = .standard) -> Double {
        min(max(load(key, default: value, from: defaults), range.lowerBound), range.upperBound)
    }

    nonisolated private static func load(_ key: String, default value: String, from defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: key) ?? value
    }

    nonisolated private static func load(_ key: String, default value: [String]) -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? value
    }

    nonisolated private static func load(_ key: String, default value: IdleItem) -> IdleItem {
        IdleItem(rawValue: load(key, default: value.rawValue)) ?? value
    }

    nonisolated private static func load(_ key: String, default value: AIWindow) -> AIWindow {
        AIWindow(rawValue: load(key, default: value.rawValue)) ?? value
    }

    nonisolated static func loadSearchHotKey(from defaults: UserDefaults = .standard) -> HotKeyCombo {
        guard let name = defaults.string(forKey: "searchHotKeyName") else { return .defaultSearch }
        return HotKeyCombo(keyCode: UInt32(defaults.integer(forKey: "searchHotKeyCode")),
                           modifiers: UInt32(defaults.integer(forKey: "searchHotKeyModifiers")), key: name)
    }

    /// Every tab after Home in the user's order, including tabs added in newer versions.
    var orderedTabs: [NotchTab] { Self.orderedTabs(saved: tabOrder) }

    nonisolated static func orderedTabs(saved order: [String]) -> [NotchTab] {
        var seen = Set<NotchTab>()
        let saved = order.compactMap(NotchTab.init(rawValue:)).filter { $0 != .home && seen.insert($0).inserted }
        let missing = NotchTab.allCases.filter { $0 != .home && !saved.contains($0) }
        return saved + missing
    }

    var visibleTabs: [NotchTab] { [.home] + orderedTabs.filter(isVisible) }

    func isVisible(_ tab: NotchTab) -> Bool {
        switch tab {
        case .home: return true
        case .shelf: return shelfTab
        case .timer: return timerTab
        case .clipboard: return clipboardTab
        case .notes: return notesTab
        case .tools: return toolsTab
        case .system: return systemTab
        case .apps: return appsTab
        case .search: return searchTab
        case .emoji: return emojiTab
        case .ai: return aiTab
        case .notices: return noticesTab
        case .mirror: return mirrorEnabled
        }
    }

    func setVisible(_ tab: NotchTab, _ visible: Bool) {
        switch tab {
        case .home: break
        case .shelf: shelfTab = visible
        case .timer: timerTab = visible
        case .clipboard: clipboardTab = visible
        case .notes: notesTab = visible
        case .tools: toolsTab = visible
        case .system: systemTab = visible
        case .apps: appsTab = visible
        case .search: searchTab = visible
        case .emoji: emojiTab = visible
        case .ai: aiTab = visible
        case .notices: noticesTab = visible
        case .mirror: mirrorEnabled = visible
        }
    }

    func moveTab(_ tab: NotchTab, by offset: Int) {
        guard let order = Self.moved(tab, by: offset, in: orderedTabs) else { return }
        tabOrder = order.map(\.rawValue)
    }

    /// `order` with `tab` swapped with the tab `offset` places away; nil when that is off either end.
    nonisolated static func moved(_ tab: NotchTab, by offset: Int, in order: [NotchTab]) -> [NotchTab]? {
        var order = order
        guard let index = order.firstIndex(of: tab) else { return nil }
        let target = index + offset
        guard order.indices.contains(target) else { return nil }
        order.swapAt(index, target)
        return order
    }

    func resetSizes() {
        expandedWidth = 620
        expandedHeight = 196
        compactLiveActivity = false
    }
}
