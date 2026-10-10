import Foundation
import Testing
@testable import Nunsseop

@MainActor
struct ShelfPersistenceTests {
    @MainActor private final class Folder {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-test-\(UUID().uuidString)")
        var store: URL { url.appendingPathComponent("store/shelf.json") }

        init() { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        deinit { try? FileManager.default.removeItem(at: url) }

        func file(_ name: String) throws -> URL {
            let file = url.appendingPathComponent(name)
            try Data(name.utf8).write(to: file)
            return file
        }

        func shelf() -> ShelfStore { ShelfStore(storeURL: store) }
    }

    private func names(_ shelf: ShelfStore) -> [String] { shelf.items.map(\.url.lastPathComponent) }

    @Test func itemsComeBackAfterARelaunch() throws {
        let folder = Folder()
        let shelf = folder.shelf()
        shelf.add([try folder.file("f1.txt"), try folder.file("f2.txt")])
        #expect(names(folder.shelf()) == ["f1.txt", "f2.txt"])
    }

    @Test func aRenamedFileIsFoundAgainThroughItsBookmark() throws {
        let folder = Folder()
        let f1 = try folder.file("f1.txt")
        folder.shelf().add([f1])
        try FileManager.default.moveItem(at: f1, to: folder.url.appendingPathComponent("g1.txt"))
        #expect(names(folder.shelf()) == ["g1.txt"])
    }

    @Test func aDeletedFileIsDroppedWhenLoading() throws {
        let folder = Folder()
        let f1 = try folder.file("f1.txt")
        let f2 = try folder.file("f2.txt")
        folder.shelf().add([f1, f2])
        try FileManager.default.removeItem(at: f2)
        #expect(names(folder.shelf()) == ["f1.txt"])
    }

    @Test func removingAnItemAndClearingAreSaved() throws {
        let folder = Folder()
        let shelf = folder.shelf()
        shelf.add([try folder.file("f1.txt"), try folder.file("f2.txt")])
        shelf.remove(try #require(shelf.items.first { $0.url.lastPathComponent == "f1.txt" }))
        #expect(names(folder.shelf()) == ["f2.txt"])
        shelf.removeAll()
        #expect(folder.shelf().items.isEmpty)
    }

    @Test func aCorruptStoreFileLoadsAsEmptyAndIsReplacedOnTheNextSave() throws {
        let folder = Folder()
        try FileManager.default.createDirectory(at: folder.store.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: folder.store)
        let shelf = folder.shelf()
        #expect(shelf.items.isEmpty)
        shelf.add([try folder.file("f1.txt")])
        #expect(names(folder.shelf()) == ["f1.txt"])
    }

    @Test func theSameFileTwiceInOneDropIsAddedOnce() throws {
        let folder = Folder()
        let shelf = folder.shelf()
        let f1 = try folder.file("f1.txt")
        shelf.add([f1, f1])
        #expect(names(shelf) == ["f1.txt"])
    }

    @Test func webAddressesAreNotAdded() throws {
        let folder = Folder()
        let shelf = folder.shelf()
        shelf.add([URL(string: "https://example.com/a.png")!])
        #expect(shelf.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.store.path))
    }
}
