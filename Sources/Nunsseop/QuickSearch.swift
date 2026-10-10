import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Evaluates arithmetic such as `12*(3+4)/2`, `2^10` or `15%`. Returns nil for anything else.
enum Calculator {
    static func evaluate(_ input: String) -> Double? {
        // The parser recurses per sign and bracket, so very long input could exhaust the stack.
        guard input.count <= 256 else { return nil }
        let text = input.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
        guard !text.isEmpty, text.contains(where: { "+-*/^%(".contains($0) }) || text.hasSuffix("%"),
              text.allSatisfy({ "0123456789.+-*/^%()".contains($0) }) else { return nil }
        var parser = Parser(chars: Array(text))
        guard let value = parser.expression(), parser.index == parser.chars.count, value.isFinite else { return nil }
        return value
    }

    static func format(_ value: Double, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 10
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// What the Copy action puts on the clipboard: a decimal point and no grouping, whatever the display language.
    static func copyString(_ value: Double) -> String {
        format(value, locale: Locale(identifier: "en_US_POSIX")).replacingOccurrences(of: ",", with: "")
    }

    private struct Parser {
        let chars: [Character]
        var index = 0

        mutating func peek() -> Character? { index < chars.count ? chars[index] : nil }

        mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while let op = peek(), op == "+" || op == "-" {
                index += 1
                guard let rhs = term() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        mutating func term() -> Double? {
            guard var value = unary() else { return nil }
            while let op = peek(), op == "*" || op == "/" {
                index += 1
                guard let rhs = unary() else { return nil }
                value = op == "*" ? value * rhs : value / rhs
            }
            return value
        }

        /// A sign binds looser than `^`, so `-2^2` is -4, while `2^-1` still takes a signed exponent.
        mutating func unary() -> Double? {
            if peek() == "-" { index += 1; return unary().map { -$0 } }
            if peek() == "+" { index += 1; return unary() }
            return power()
        }

        mutating func power() -> Double? {
            guard var base = primary() else { return nil }
            if peek() == "%" { index += 1; base /= 100 }
            if peek() == "^" {
                index += 1
                guard let exponent = unary() else { return nil }
                return pow(base, exponent)
            }
            return base
        }

        mutating func primary() -> Double? {
            if peek() == "(" {
                index += 1
                let value = expression()
                guard peek() == ")" else { return nil }
                index += 1
                return value
            }
            let start = index
            while let c = peek(), c.isNumber || c == "." { index += 1 }
            guard index > start else { return nil }
            return Double(String(chars[start..<index]))
        }
    }
}

/// One row in Search: an app, file, command, clipboard entry, emoji, calculation or web search.
struct SearchResult: Identifiable {
    enum Icon {
        case image(NSImage)
        case symbol(String)
        case text(String)
    }

    let id: String
    let icon: Icon
    let title: String
    let subtitle: String
    let run: () -> Void
}

/// A launcher meant to stand in for Spotlight or Raycast: apps, files, system commands,
/// clipboard history, emoji, sums and the web, all from one field.
@MainActor
final class QuickSearchModel: ObservableObject {
    struct AppItem: Hashable {
        let url: URL
        let name: String
        let fileName: String
    }

    private struct Command {
        let id: String
        let title: String
        let keywords: String
        let symbol: String
        let action: () -> Void
    }

    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            selection = 0
            scheduleFileSearch(query.trimmingCharacters(in: .whitespaces))
            update()
        }
    }
    @Published var focusToken = 0
    @Published private(set) var results: [SearchResult] = []
    @Published var selection = 0
    /// Closes the notch after an action runs.
    var onFinish: (() -> Void)?

    private weak var clipboard: ClipboardHistory?
    private weak var tools: ToolsModel?
    private let emoji: EmojiModel
    private(set) var apps: [AppItem] = []
    private var files: [SearchResult] = []
    private var fileQuery: NSMetadataQuery?
    private var fileWork: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private let defaults = UserDefaults.standard

    init(clipboard: ClipboardHistory, emoji: EmojiModel, tools: ToolsModel) {
        self.clipboard = clipboard
        self.emoji = emoji
        self.tools = tools
    }

    // MARK: Sources

    func loadApps() {
        guard apps.isEmpty else { update(); return }
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                       "/System/Library/CoreServices/Applications",
                       (NSHomeDirectory() as NSString).appendingPathComponent("Applications")]
        var seen = Set<String>()
        apps = folders.flatMap { folder -> [AppItem] in
            let urls = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil)) ?? []
            return urls.filter { $0.pathExtension == "app" }.compactMap { url in
                let fileName = url.deletingPathExtension().lastPathComponent
                guard !fileName.hasPrefix(".") else { return nil }
                let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
                return seen.insert(fileName).inserted ? AppItem(url: url, name: name, fileName: fileName) : nil
            }
        }
        update()
        Task { [weak self] in
            let extra = await Task.detached(priority: .utility) { Self.indexedApps() }.value
            guard let self else { return }
            var names = Set(self.apps.map(\.fileName))
            self.apps += extra.filter { names.insert($0.fileName).inserted }
            self.update()
        }
    }

    /// Apps the Spotlight index knows about outside the usual folders, such as one left in Downloads.
    nonisolated private static func indexedApps() -> [AppItem] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["kMDItemContentType == 'com.apple.application-bundle'"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let home = NSHomeDirectory()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
            let path = String(line)
            let inside = path.dropLast(4)
            guard path.hasSuffix(".app"), !inside.contains(".app/"), !path.hasPrefix("/System/"), !path.hasPrefix("/Library/"),
                  !path.hasPrefix(home + "/Library/"), !path.hasPrefix("/Volumes/"), !path.hasPrefix("/private/"),
                  !path.contains("/."), !["/node_modules/", "/build/", "/dist/", "/DerivedData/"].contains(where: path.contains)
            else { return nil }
            let url = URL(fileURLWithPath: path)
            let fileName = url.deletingPathExtension().lastPathComponent
            let name = FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
            return AppItem(url: url, name: name, fileName: fileName)
        }
    }

    private var launchCounts: [String: Int] {
        get { defaults.dictionary(forKey: "searchLaunchCounts") as? [String: Int] ?? [:] }
        set { defaults.set(newValue, forKey: "searchLaunchCounts") }
    }

    private lazy var commands: [Command] = {
        func settingsPane(_ id: String, _ title: String, _ keywords: String, _ symbol: String) -> Command {
            Command(id: "pane-\(id)", title: title, keywords: keywords, symbol: symbol) {
                if let url = URL(string: "x-apple.systempreferences:\(id)") { NSWorkspace.shared.open(url) }
            }
        }
        func run(_ path: String, _ arguments: [String]) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            try? process.run()
        }
        return [
            Command(id: "sleep-display", title: String(localized: "Turn off display"), keywords: "sleep display lock screen off", symbol: "display") {
                run("/usr/bin/pmset", ["displaysleepnow"])
            },
            Command(id: "sleep", title: String(localized: "Sleep"), keywords: "sleep mac", symbol: "moon.zzz.fill") {
                run("/usr/bin/pmset", ["sleepnow"])
            },
            Command(id: "screensaver", title: String(localized: "Start screen saver"), keywords: "screen saver", symbol: "sparkles.tv") {
                run("/usr/bin/open", ["-a", "ScreenSaverEngine"])
            },
            Command(id: "downloads", title: String(localized: "Downloads folder"), keywords: "downloads folder", symbol: "arrow.down.circle.fill") {
                NSWorkspace.shared.open(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0])
            },
            Command(id: "trash", title: String(localized: "Open Trash"), keywords: "trash bin", symbol: "trash.fill") {
                NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash"))
            },
            Command(id: "capture-text", title: String(localized: "Capture text from the screen"), keywords: "ocr text capture scan copy", symbol: "text.viewfinder") { [weak self] in
                self?.tools?.captureText()
            },
            Command(id: "pick-color", title: String(localized: "Pick a color from the screen"), keywords: "color picker eyedropper hex", symbol: "eyedropper") { [weak self] in
                self?.tools?.pickColor()
            },
            Command(id: "nunsseop-settings", title: String(localized: "Nunsseop Settings"), keywords: "nunsseop settings preferences", symbol: "gearshape.fill") {
                SettingsWindowController.shared.show()
            },
            settingsPane("com.apple.wifi-settings-extension", String(localized: "Wi-Fi settings"), "wifi wi-fi wireless network", "wifi"),
            settingsPane("com.apple.BluetoothSettings", String(localized: "Bluetooth settings"), "bluetooth", "dot.radiowaves.left.and.right"),
            settingsPane("com.apple.Displays-Settings.extension", String(localized: "Display settings"), "displays monitor resolution", "display.2"),
            settingsPane("com.apple.Sound-Settings.extension", String(localized: "Sound settings"), "sound audio volume output", "speaker.wave.2.fill"),
            settingsPane("com.apple.Battery-Settings.extension", String(localized: "Battery settings"), "battery power energy", "battery.75percent"),
            settingsPane("com.apple.Keyboard-Settings.extension", String(localized: "Keyboard settings"), "keyboard shortcuts input", "keyboard"),
            settingsPane("com.apple.settings.PrivacySecurity.extension", String(localized: "Privacy & Security settings"), "privacy security permissions", "hand.raised.fill"),
        ]
    }()

    // MARK: Matching

    /// Higher is better: prefix, then word prefix, then initials ("vsc"), then substring.
    static func score(_ name: String, _ query: String) -> Double? {
        let n = name.lowercased(), q = query.lowercased()
        guard !q.isEmpty else { return nil }
        if n.hasPrefix(q) { return 5 }
        let words = n.split(whereSeparator: { " -_.()".contains($0) })
        if words.contains(where: { $0.hasPrefix(q) }) { return 4 }
        if String(words.compactMap(\.first)).hasPrefix(q) { return 3.5 }
        return n.contains(q) ? 3 : nil
    }

    private func update() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            let counts = launchCounts
            results = apps.filter { counts[$0.url.path] != nil }
                .sorted { counts[$0.url.path]! > counts[$1.url.path]! }
                .prefix(5).map(appResult)
            return
        }
        if q.hasPrefix(":") {
            let term = String(q.dropFirst())
            results = emoji.results(for: term).prefix(term.isEmpty ? 12 : 30).map { item in
                SearchResult(id: "emoji-\(item.character)", icon: .text(item.character), title: item.name.capitalized,
                             subtitle: String(localized: "Copy emoji")) { [weak self] in
                    self?.emoji.copy(item)
                    self?.finish()
                }
            }
            return
        }
        var list: [SearchResult] = []
        if let value = Calculator.evaluate(q) {
            list.append(SearchResult(id: "calc", icon: .symbol("equal.circle.fill"), title: Calculator.format(value),
                                     subtitle: String(localized: "Copy result")) { [weak self] in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Calculator.copyString(value), forType: .string)
                self?.finish()
            })
        }
        let counts = launchCounts
        var ranked: [(Double, SearchResult)] = apps.compactMap { app in
            guard let s = [Self.score(app.name, q), Self.score(app.fileName, q)].compactMap({ $0 }).max() else { return nil }
            return (s + min(Double(counts[app.url.path] ?? 0), 20) / 10, appResult(app))
        }
        ranked += commands.compactMap { command in
            guard let s = [Self.score(command.title, q), Self.score(command.keywords, q)].compactMap({ $0 }).max() else { return nil }
            return (s - 0.5, SearchResult(id: command.id, icon: .symbol(command.symbol), title: command.title,
                                          subtitle: String(localized: "Command")) { [weak self] in
                command.action()
                self?.finish()
            })
        }
        list += ranked.sorted { $0.0 > $1.0 }.prefix(8).map(\.1)
        list += files
        if let clipboard {
            list += clipboard.items.filter { $0.text.localizedCaseInsensitiveContains(q) }.prefix(3).map { item in
                SearchResult(id: "clip-\(item.id)", icon: .symbol("doc.on.clipboard"),
                             title: item.text.replacingOccurrences(of: "\n", with: " "),
                             subtitle: String(localized: "Clipboard")) { [weak self, weak clipboard] in
                    clipboard?.copy(item)
                    self?.finish()
                }
            }
        }
        list.append(SearchResult(id: "web", icon: .symbol("globe"), title: String(localized: "Search the web for “\(q)”"),
                                 subtitle: "Google") { [weak self] in
            var components = URLComponents(string: "https://www.google.com/search")!
            components.queryItems = [URLQueryItem(name: "q", value: q)]
            if let url = components.url { NSWorkspace.shared.open(url) }
            self?.finish()
        })
        results = list
    }

    private func appResult(_ app: AppItem) -> SearchResult {
        SearchResult(id: "app-\(app.url.path)", icon: .image(NSWorkspace.shared.icon(forFile: app.url.path)), title: app.name,
                     subtitle: String(localized: "Application")) { [weak self] in
            NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
            self?.launchCounts[app.url.path, default: 0] += 1
            self?.finish()
        }
    }

    /// Files by name from the Spotlight index, newest first.
    private func scheduleFileSearch(_ q: String) {
        fileWork?.cancel()
        fileQuery?.stop()
        fileQuery = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        files = []
        guard q.count >= 2, !q.hasPrefix(":"), Calculator.evaluate(q) == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.startFileQuery(q) }
        fileWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func startFileQuery(_ q: String) {
        let metadata = NSMetadataQuery()
        metadata.predicate = NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemDisplayNameKey, "*\(q)*")
        metadata.searchScopes = [NSMetadataQueryUserHomeScope]
        observers.append(NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: metadata, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let metadata = self.fileQuery else { return }
                self.finishFileQuery(metadata, for: q)
            }
        })
        fileQuery = metadata
        metadata.start()
    }

    private func finishFileQuery(_ metadata: NSMetadataQuery, for q: String) {
        metadata.stop()
        guard q == query.trimmingCharacters(in: .whitespaces) else { return }
        let home = NSHomeDirectory()
        var candidates: [(path: String, used: Date)] = []
        for index in 0..<min(metadata.resultCount, 2000) {
            guard let item = metadata.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  !path.hasSuffix(".app"), !path.hasPrefix(home + "/Library/"), !path.contains("/."),
                  !path.contains("/node_modules/") else { continue }
            let used = item.value(forAttribute: "kMDItemLastUsedDate") as? Date
                ?? item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date ?? .distantPast
            candidates.append((path, used))
        }
        files = candidates.sorted { $0.used > $1.used }.prefix(5).map { candidate in
            let url = URL(fileURLWithPath: candidate.path)
            let folder = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
            return SearchResult(id: "file-\(candidate.path)", icon: .image(NSWorkspace.shared.icon(forFile: candidate.path)),
                                title: url.lastPathComponent, subtitle: folder) { [weak self] in
                NSWorkspace.shared.open(url)
                self?.finish()
            }
        }
        let current = selection
        update()
        selection = min(current, max(0, results.count - 1))
    }

    // MARK: Actions

    func move(_ offset: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + offset + results.count) % results.count
    }

    func runSelected() {
        guard results.indices.contains(selection) else { return }
        results[selection].run()
    }

    private func finish() {
        query = ""
        onFinish?()
    }
}

struct SearchTab: View {
    @ObservedObject var model: QuickSearchModel
    let shortcut: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
                TextField("Search apps, files, commands, or calculate", text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 15))
                    .focused($focused)
                    .onSubmit { model.runSelected() }
                    .onKeyPress(.downArrow) { model.move(1); return .handled }
                    .onKeyPress(.upArrow) { model.move(-1); return .handled }
            }
            .padding(.horizontal, 12).frame(height: 34)
            .surface(RoundedRectangle(cornerRadius: 10), opacity: 0.1)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        if model.query.isEmpty {
                            hint
                        }
                        ForEach(Array(model.results.enumerated()), id: \.element.id) { index, result in
                            ResultRow(result: result, selected: index == model.selection)
                                .id(result.id)
                                .onTapGesture { model.selection = index; model.runSelected() }
                        }
                    }
                }
                .onChange(of: model.selection) { _, index in
                    guard model.results.indices.contains(index) else { return }
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(model.results[index].id) }
                }
            }
        }
        .foregroundStyle(.white)
        .onAppear {
            model.loadApps()
            focused = true
        }
        .onChange(of: model.focusToken) { _, _ in focused = true }
    }

    @ViewBuilder private var hint: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let shortcut {
                Text("Open this from anywhere with \(shortcut). Start with : to find emoji.")
            } else {
                Text("Start with : to find emoji.")
            }
            if !model.results.isEmpty {
                Text("Frequently used").padding(.top, 4)
            }
        }
        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4).padding(.bottom, 2)
    }
}

private struct ResultRow: View {
    let result: SearchResult
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Group {
                switch result.icon {
                case .image(let image): Image(nsImage: image).resizable()
                case .symbol(let name): Image(systemName: name).font(.system(size: 14))
                case .text(let text): Text(text).font(.system(size: 17))
                }
            }
            .frame(width: 22, height: 22)
            Text(result.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
            Spacer(minLength: 8)
            Text(result.subtitle).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1).truncationMode(.head)
        }
        .padding(.horizontal, 10).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(selected ? 0.16 : hovering ? 0.08 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// A key combination for a global hotkey, kept as Carbon key code and modifiers.
struct HotKeyCombo: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var key: String

    static let defaultSearch = HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(shiftKey | cmdKey), key: "Space")

    var label: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + key
    }

    private static let names: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
        kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    /// A combination needs ⌘, ⌃ or ⌥, unless it is a function key.
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        let code = Int(event.keyCode)
        let isFunctionKey = Self.names[code]?.hasPrefix("F") == true
        guard carbon & UInt32(controlKey | optionKey | cmdKey) != 0 || isFunctionKey else { return nil }
        let key = Self.names[code] ?? (event.charactersIgnoringModifiers ?? "").uppercased()
        guard !key.isEmpty else { return nil }
        self.init(keyCode: UInt32(code), modifiers: carbon, key: key)
    }

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// The macOS keyboard shortcut already bound to this combination, if any.
    var systemConflict: String? {
        guard let table = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys") else { return nil }
        var cocoa = 0
        if modifiers & UInt32(shiftKey) != 0 { cocoa |= 1 << 17 }
        if modifiers & UInt32(controlKey) != 0 { cocoa |= 1 << 18 }
        if modifiers & UInt32(optionKey) != 0 { cocoa |= 1 << 19 }
        if modifiers & UInt32(cmdKey) != 0 { cocoa |= 1 << 20 }
        let known: [String: String] = [
            "60": String(localized: "Select the previous input source"), "61": String(localized: "Select next source in Input menu"),
            "64": String(localized: "Show Spotlight search"), "65": String(localized: "Show Finder search window"),
        ]
        // The plist stores these numbers as strings on some systems.
        func number(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue ?? (value as? String).flatMap { Int($0) } }
        for (id, value) in table {
            guard let entry = value as? [String: Any], number(entry["enabled"]) == 1,
                  let parameters = ((entry["value"] as? [String: Any])?["parameters"] as? [Any])?.compactMap(number),
                  parameters.count == 3, parameters[1] == Int(keyCode), parameters[2] & 0x1E0000 == cocoa else { continue }
            return known[id] ?? String(localized: "a macOS shortcut")
        }
        return nil
    }
}

/// A system-wide hotkey through Carbon, which needs no Accessibility permission.
final class GlobalHotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private(set) var isRegistered = false

    init(combo: HotKeyCombo, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let me = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { me.action() }
            return noErr
        }, 1, &spec, context, &handler)
        let id = EventHotKeyID(signature: OSType(0x4E534550), id: 1)
        isRegistered = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &reference) == noErr
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
