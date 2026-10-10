import Foundation
import Testing
@testable import Nunsseop

@MainActor
struct MediaRemoteBridgeTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    private enum MessageError: Error { case notAnUpdate }

    private func line(_ info: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: info)
    }

    private func update(_ info: [String: Any]) throws -> MediaRemoteUpdate {
        guard case .update(let update)? = MediaRemoteBridge.message(from: try line(info), now: now) else {
            throw MessageError.notAnUpdate
        }
        return update
    }

    private func playing(_ extra: [String: Any] = [:]) -> [String: Any] {
        ["active": true, "title": "T", "elapsed": 10.0, "rate": 1.0, "timestamp": now.timeIntervalSince1970 - 5]
            .merging(extra) { _, new in new }
    }

    @Test func extrapolatesPositionFromTheTimestamp() throws {
        let track = try #require(try update(playing()).track)
        #expect(abs(track.position - 15) < 0.001)
        #expect(track.isPlaying)
        #expect(track.rate == 1)
        #expect(track.fetchedAt == now)
        let fast = try #require(try update(playing(["rate": 2.0])).track)
        #expect(abs(fast.position - 20) < 0.001)
        #expect(fast.rate == 2)
    }

    @Test func pausedTrackKeepsItsPositionAndShowsNormalSpeed() throws {
        let track = try #require(try update(playing(["rate": 0.0])).track)
        #expect(track.position == 10)
        #expect(!track.isPlaying)
        #expect(track.rate == 1)
    }

    @Test func commandsDecideSeekAndSpeedControls() throws {
        let both = try #require(try update(playing(["commands": [19, 24]])).track)
        #expect(both.canSeek && both.canChangeRate)
        let none = try #require(try update(playing(["commands": [Int]()])).track)
        #expect(!none.canSeek && !none.canChangeRate)
        let unknown = try #require(try update(playing()).track)
        #expect(unknown.canSeek && !unknown.canChangeRate)
    }

    @Test func missingFieldsFallBackToEmptyValues() throws {
        let track = try #require(try update(["active": true, "title": "T"]).track)
        #expect(track.artist == "" && track.album == "" && track.sourceBundleID == "")
        #expect(track.duration == 0 && track.position == 0)
        #expect(!track.isPlaying)
    }

    @Test func readsTrackFields() throws {
        let extra: [String: Any] = ["artist": "Ar", "album": "Al", "duration": 240.0, "bundleID": "com.spotify.client"]
        let track = try #require(try update(playing(extra)).track)
        #expect(track.artist == "Ar" && track.album == "Al")
        #expect(track.duration == 240)
        #expect(track.sourceBundleID == "com.spotify.client")
    }

    @Test func inactiveOrUntitledMeansNoTrack() throws {
        let none = MediaRemoteUpdate(track: nil, artwork: nil)
        #expect(try update(["active": false, "title": "T"]) == none)
        #expect(try update(["active": true, "title": ""]) == none)
        #expect(try update(["active": true]) == none)
    }

    @Test func artworkIsDecodedOrFlaggedUnchanged() throws {
        #expect(try update(playing(["artwork": "AAEC"])).artwork == Data([0, 1, 2]))
        #expect(try update(playing(["artwork": "!!not base64!!"])).artwork == nil)
        #expect(try update(playing(["artworkUnchanged": true])).artworkUnchanged)
        #expect(try !update(playing()).artworkUnchanged)
    }

    @Test func errorLineFailsAndGarbageIsIgnored() throws {
        guard case .failure? = MediaRemoteBridge.message(from: try line(["error": "no framework"]), now: now) else {
            Issue.record("an error line should stop the helper")
            return
        }
        #expect(MediaRemoteBridge.message(from: Data("not json".utf8), now: now) == nil)
        #expect(MediaRemoteBridge.message(from: Data("[1,2]".utf8), now: now) == nil)
        #expect(MediaRemoteBridge.message(from: Data(), now: now) == nil)
    }

    @Test func buffersLinesSplitAcrossReads() throws {
        let bridge = MediaRemoteBridge()
        var titles: [String?] = []
        bridge.onUpdate = { titles.append($0.track?.title) }
        let first = try line(["active": true, "title": "One"])
        let second = try line(["active": true, "title": "Two"])
        let half = first.count / 2
        bridge.receive(Data(first.prefix(half)))
        #expect(titles.isEmpty)
        bridge.receive(Data(first.suffix(from: half)) + Data("\n".utf8))
        #expect(titles == ["One"])
        bridge.receive(second + Data("\n".utf8) + first + Data("\n".utf8))
        #expect(titles == ["One", "Two", "One"])
        bridge.receive(Data("\n".utf8))
        #expect(titles.count == 3)
    }
}
