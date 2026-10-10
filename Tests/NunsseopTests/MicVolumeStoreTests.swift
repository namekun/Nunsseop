import Foundation
import Testing
@testable import Nunsseop

@MainActor
struct MicVolumeStoreTests {
    @Test func persistsPerDeviceAndClears() throws {
        // One fixed name: removing a domain empties it but leaves its plist behind, so a fresh name per run piles up files.
        let suite = "NunsseopTests.MicVolumeStore"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(ToolsModel.savedInputVolume(for: "mic-a", defaults: defaults) == nil)
        ToolsModel.setSavedInputVolume(0.6, for: "mic-a", defaults: defaults)
        ToolsModel.setSavedInputVolume(0.25, for: "mic-b", defaults: defaults)
        #expect(ToolsModel.savedInputVolume(for: "mic-a", defaults: defaults) == 0.6)
        #expect(ToolsModel.savedInputVolumes(defaults) == ["mic-a": 0.6, "mic-b": 0.25])

        ToolsModel.setSavedInputVolume(nil, for: "mic-a", defaults: defaults)
        #expect(ToolsModel.savedInputVolume(for: "mic-a", defaults: defaults) == nil)
        #expect(ToolsModel.savedInputVolume(for: "mic-b", defaults: defaults) == 0.25)

        ToolsModel.setSavedInputVolume(nil, for: "mic-b", defaults: defaults)
        #expect(defaults.object(forKey: "savedInputVolumes") == nil)
    }
}
