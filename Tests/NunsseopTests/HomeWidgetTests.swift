import Foundation
import Testing
@testable import Nunsseop

@MainActor
struct HomeWidgetTests {
    private final class Folder {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("todo-test-\(UUID().uuidString)")
        var url: URL { dir.appendingPathComponent("nested/todos.json") }
        deinit { try? FileManager.default.removeItem(at: dir) }
    }

    @Test func nothingIsChosenAtFirst() {
        #expect(HomeWidget.chosen(saved: []).isEmpty)
    }

    @Test func chosenKeepsTheSavedOrderAndDropsRepeatsAndUnknowns() {
        #expect(HomeWidget.chosen(saved: ["todo", "gone", "clock", "todo"]) == [.todo, .clock])
    }

    @Test func switchingOnAppendsAndSwitchingOffRemoves() {
        var saved = HomeWidget.setting(.note, on: true, in: [])
        saved = HomeWidget.setting(.clock, on: true, in: saved)
        #expect(saved == ["note", "clock"])
        #expect(HomeWidget.setting(.note, on: true, in: saved) == ["clock", "note"])
        #expect(HomeWidget.setting(.note, on: false, in: saved) == ["clock"])
    }

    @Test func movingStopsAtTheEndsAndIgnoresWidgetsThatAreOff() {
        let saved = ["clock", "note", "todo"]
        #expect(HomeWidget.moving(.todo, by: -1, in: saved) == ["clock", "todo", "note"])
        #expect(HomeWidget.moving(.clock, by: -1, in: saved) == saved)
        #expect(HomeWidget.moving(.todo, by: 1, in: saved) == saved)
        #expect(HomeWidget.moving(.clock, by: 5, in: saved) == ["note", "todo", "clock"])
        #expect(HomeWidget.moving(.todo, by: -1, in: ["clock"]) == ["clock"])
    }

    @Test func theNotePreviewIsTheFirstLineWithSomethingInIt() {
        #expect(HomeWidget.notePreview(of: "") == nil)
        #expect(HomeWidget.notePreview(of: " \n\n  buy milk \nsecond") == "buy milk")
    }

    @Test func aTodoModelReadsNothingUntilAskedAndKeepsWhatIsAdded() throws {
        let folder = Folder()
        let todos = TodoModel(url: folder.url)
        #expect(todos.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.url.path))
        todos.add("  write tests ")
        todos.add("   ")
        todos.add("ship")
        #expect(todos.items.map(\.text) == ["write tests", "ship"])

        let again = TodoModel(url: folder.url)
        #expect(again.items.isEmpty)
        again.loadIfNeeded()
        #expect(again.items.map(\.text) == ["write tests", "ship"])
    }

    @Test func checkingATodoOffRemovesItForGood() throws {
        let folder = Folder()
        let todos = TodoModel(url: folder.url)
        todos.add("a")
        todos.add("b")
        todos.complete(try #require(todos.items.first).id)
        #expect(todos.items.map(\.text) == ["b"])
        let again = TodoModel(url: folder.url)
        again.loadIfNeeded()
        #expect(again.items.map(\.text) == ["b"])
    }

    @Test func aDamagedFileIsAnEmptyList() throws {
        let folder = Folder()
        try FileManager.default.createDirectory(at: folder.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "not json".write(to: folder.url, atomically: true, encoding: .utf8)
        let todos = TodoModel(url: folder.url)
        todos.loadIfNeeded()
        #expect(todos.items.isEmpty)
    }

    @Test func theNewSentencesAreTranslatedIntoEveryLanguage() throws {
        let keys = ["Clock", "Note", "To-do", "Home widgets", "Move up", "Move down", "Add a to-do", "Nothing to do", "Mark as done",
                    "Widgets show under the calendar in the order they are listed. A widget that is off runs nothing."]
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources")
        for language in ["de", "es", "fr", "ja", "ko", "zh-Hans"] {
            let strings = try #require(NSDictionary(contentsOfFile: resources.appendingPathComponent("\(language).lproj/Localizable.strings").path))
            for key in keys {
                let text = strings[key] as? String ?? ""
                // French writes "Note" as English does.
                let same = language == "fr" && key == "Note"
                #expect(!text.isEmpty && (same || text != key), Comment(rawValue: "\(language): \(key)"))
            }
        }
    }
}
