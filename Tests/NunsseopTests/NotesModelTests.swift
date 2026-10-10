import Foundation
import Testing
@testable import Nunsseop

@MainActor
struct NotesModelTests {
    private final class Folder {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("notes-test-\(UUID().uuidString)")
        var url: URL { dir.appendingPathComponent("nested/notes.txt") }
        deinit { try? FileManager.default.removeItem(at: dir) }

        var contents: String? { try? String(contentsOf: url, encoding: .utf8) }
    }

    /// Waits for a background write without a fixed sleep.
    private func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func flushWritesTheLatestTextAtOnce() {
        let folder = Folder()
        let notes = NotesModel(url: folder.url, debounce: 60)
        notes.text = "a"
        notes.text = "ab"
        #expect(folder.contents == nil)
        notes.flush()
        #expect(folder.contents == "ab")
    }

    @Test func flushWithoutAnEditLeavesTheFileAlone() throws {
        let folder = Folder()
        try FileManager.default.createDirectory(at: folder.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "kept".write(to: folder.url, atomically: true, encoding: .utf8)
        let notes = NotesModel(url: folder.url, debounce: 60)
        #expect(notes.text == "kept")
        try "other".write(to: folder.url, atomically: true, encoding: .utf8)
        notes.flush()
        #expect(folder.contents == "other")
    }

    @Test func rapidTypingEndsWithTheLastTextOnDisk() async {
        let folder = Folder()
        let notes = NotesModel(url: folder.url, debounce: 0.05)
        for text in ["h", "he", "hel", "hell", "hello"] { notes.text = text }
        await waitFor { folder.contents == "hello" }
        #expect(folder.contents == "hello")
    }

    @Test func aNewModelLoadsWhatWasSaved() {
        let folder = Folder()
        let notes = NotesModel(url: folder.url, debounce: 60)
        notes.text = "ab"
        notes.flush()
        #expect(NotesModel(url: folder.url, debounce: 60).text == "ab")
    }

    @Test func clearingTheNoteEmptiesTheFile() {
        let folder = Folder()
        let notes = NotesModel(url: folder.url, debounce: 60)
        notes.text = "something"
        notes.flush()
        notes.text = ""
        notes.flush()
        #expect(folder.contents == "")
    }

    @Test func aMissingFileLoadsAsAnEmptyNote() {
        #expect(NotesModel(url: Folder().url, debounce: 60).text == "")
    }
}
