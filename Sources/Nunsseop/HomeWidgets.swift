import SwiftUI

/// The small widgets the user may put on Home, under the calendar: the order they are chosen in is the order they show.
enum HomeWidget: String, CaseIterable, Identifiable {
    case clock, note, todo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: return String(localized: "Clock")
        case .note: return String(localized: "Note")
        case .todo: return String(localized: "To-do")
        }
    }

    var symbol: String {
        switch self {
        case .clock: return "clock"
        case .note: return "note.text"
        case .todo: return "checkmark.circle"
        }
    }

    /// The saved raw values as the widgets they name, in order, without repeats; what is no longer a widget is dropped.
    nonisolated static func chosen(saved: [String]) -> [HomeWidget] {
        var seen = Set<HomeWidget>()
        return saved.compactMap(HomeWidget.init(rawValue:)).filter { seen.insert($0).inserted }
    }

    /// The first line of the note that has anything in it.
    nonisolated static func notePreview(of text: String) -> String? {
        text.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    }

    /// `saved` with the widget switched on (at the end) or off.
    nonisolated static func setting(_ widget: HomeWidget, on: Bool, in saved: [String]) -> [String] {
        let rest = chosen(saved: saved).filter { $0 != widget }
        return (on ? rest + [widget] : rest).map(\.rawValue)
    }

    /// `saved` with the widget moved `by` places (negative is up) among the chosen ones, stopping at the ends.
    nonisolated static func moving(_ widget: HomeWidget, by offset: Int, in saved: [String]) -> [String] {
        var list = chosen(saved: saved)
        guard let index = list.firstIndex(of: widget) else { return list.map(\.rawValue) }
        let target = min(max(index + offset, 0), list.count - 1)
        list.insert(list.remove(at: index), at: target)
        return list.map(\.rawValue)
    }
}

/// What Home needs to show the widgets that are on.
struct HomeWidgetBoard {
    let widgets: [HomeWidget]
    let notes: NotesModel
    let todos: TodoModel
    /// Jumps to the Notes tab; nil while that tab is off.
    let openNotes: (() -> Void)?
}

/// A short list of things to do, kept in Application Support. It reads nothing until a widget that shows it asks, so with the
/// widget off it does not touch the disk.
@MainActor
final class TodoModel: ObservableObject {
    struct Item: Codable, Equatable, Identifiable {
        var id = UUID()
        var text: String
    }

    @Published private(set) var items: [Item] = []
    private let url: URL
    private var loaded = false

    init(url: URL = TodoModel.defaultURL) { self.url = url }

    nonisolated static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Nunsseop/todos.json")
    }

    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        items = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([Item].self, from: $0) } ?? []
    }

    /// Adds what was typed, trimmed, unless it is blank.
    func add(_ text: String) {
        loadIfNeeded()
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        items.append(Item(text: text))
        save()
    }

    /// Checking a to-do off removes it.
    func complete(_ id: Item.ID) {
        loadIfNeeded()
        items.removeAll { $0.id == id }
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(items).write(to: url, options: .atomic)
    }
}

/// The widgets, one row each, with a hairline above. Each one is a view that exists only while it is on, so what is off runs nothing.
struct HomeWidgetRows: View {
    let board: HomeWidgetBoard

    var body: some View {
        VStack(spacing: 0) {
            ForEach(board.widgets) { widget in
                PanelHLine()
                switch widget {
                case .clock: ClockWidget()
                case .note: NoteWidget(notes: board.notes, open: board.openNotes)
                case .todo: TodoWidget(todos: board.todos)
                }
            }
        }
    }
}

/// The first line of the note; a click opens the whole note.
private struct NoteWidget: View {
    @ObservedObject var notes: NotesModel
    let open: (() -> Void)?

    var body: some View {
        let line = HomeWidget.notePreview(of: notes.text)
        Button { open?() } label: {
            HStack(spacing: 8) {
                Image(systemName: HomeWidget.note.symbol).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                    .frame(width: 16).accessibilityHidden(true)
                if let line {
                    Text.panel(line, size: 12).lineLimit(1)
                } else {
                    Text("Jot something down…").font(.system(size: 12)).foregroundStyle(PanelInk.hint).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).frame(height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(open == nil)
        .accessibilityLabel(Text(HomeWidget.note.title))
        .accessibilityValue(Text(verbatim: line ?? ""))
    }
}

/// The time, as the system writes it, and the date. Redrawn once a minute and not at all while Home is closed.
private struct ClockWidget: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 8) {
                Image(systemName: HomeWidget.clock.symbol).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                    .frame(width: 16).accessibilityHidden(true)
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 15, weight: .semibold).monospacedDigit()).lineLimit(1).fixedSize()
                Spacer(minLength: 4)
                Text(context.date, format: .dateTime.month(.abbreviated).day().weekday(.abbreviated))
                    .font(.system(size: 11)).foregroundStyle(PanelInk.secondary).lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8).frame(height: 26)
            .accessibilityElement(children: .combine)
        }
    }
}

/// The next thing to do with a check to tick it off, and how many more wait; a field to add one.
private struct TodoWidget: View {
    @ObservedObject var todos: TodoModel
    @State private var adding = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            if adding {
                Image(systemName: "plus.circle").font(.system(size: 13)).foregroundStyle(.white.opacity(0.8))
                    .frame(width: 16).accessibilityHidden(true)
                TextField("Add a to-do", text: $draft)
                    .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(.white)
                    .focused($focused)
                    .onSubmit { commit(keepOpen: true) }
                    .onExitCommand { commit(keepOpen: false) }
                Button { commit(keepOpen: false) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).frame(width: 20, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(Text("Done"))
            } else {
                if let next = todos.items.first {
                    Button { todos.complete(next.id) } label: {
                        Image(systemName: "circle").font(.system(size: 13)).foregroundStyle(.white.opacity(0.8))
                            .frame(width: 20, height: 22).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help(Text("Mark as done"))
                    Text.panel(next.text, size: 12).lineLimit(1)
                    Spacer(minLength: 4)
                    if todos.items.count > 1 {
                        Text.panel("+\(todos.items.count - 1)", size: 11, opacity: 0.6, mono: true).fixedSize()
                    }
                } else {
                    Image(systemName: HomeWidget.todo.symbol).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                        .frame(width: 16).accessibilityHidden(true)
                    Text("Nothing to do").font(.system(size: 12)).foregroundStyle(PanelInk.hint).lineLimit(1)
                    Spacer(minLength: 4)
                }
                Button { adding = true; focused = true } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(Text("Add a to-do"))
            }
        }
        .padding(.horizontal, 8).frame(height: 26)
        .onAppear { todos.loadIfNeeded() }
    }

    private func commit(keepOpen: Bool) {
        todos.add(draft)
        draft = ""
        adding = keepOpen
        focused = keepOpen
    }
}
