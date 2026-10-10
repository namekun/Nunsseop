import SwiftUI

/// A single scratch note saved to Application Support.
@MainActor
final class NotesModel: ObservableObject {
    @Published var text: String { didSet { scheduleSave() } }
    private let url: URL
    private let debounce: TimeInterval
    private var saveWork: DispatchWorkItem?

    init(url: URL = NotesModel.defaultURL, debounce: TimeInterval = 0.6) {
        self.url = url
        self.debounce = debounce
        text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    nonisolated static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Nunsseop/notes.txt")
    }

    /// Writes any edit still waiting out the delay.
    func flush() {
        guard let work = saveWork else { return }
        work.cancel()
        saveWork = nil
        Self.write(text, to: url)
    }

    nonisolated private static func write(_ text: String, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let text = text, url = url
        let work = DispatchWorkItem { Self.write(text, to: url) }
        saveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + debounce, execute: work)
    }
}

struct NotesTab: View {
    @ObservedObject var notes: NotesModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.surface(RoundedRectangle(cornerRadius: 14), opacity: 0.05)
            if notes.text.isEmpty {
                Text("Jot something down…")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $notes.text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 8)
        }
    }
}
