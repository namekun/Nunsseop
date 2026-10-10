import AppKit
import Foundation
import Testing
@testable import Nunsseop

struct NowPlayingTrackTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 0)

    private func track(position: Double = 10, duration: Double = 200, playing: Bool = true, rate: Double = 1,
                       album: String = "Al") -> NowPlayingTrack {
        NowPlayingTrack(title: "T", artist: "Ar", album: album, duration: duration, position: position,
                        isPlaying: playing, sourceBundleID: "com.apple.Music", fetchedAt: t0, rate: rate)
    }

    @Test func positionAdvancesWithPlaybackRate() {
        #expect(track().position(at: t0 + 5) == 15)
        #expect(track(rate: 2).position(at: t0 + 5) == 20)
    }

    @Test func pausedPositionStaysPut() {
        #expect(track(playing: false).position(at: t0 + 500) == 10)
    }

    @Test func positionStopsAtTheEnd() {
        #expect(track(position: 198).position(at: t0 + 10) == 200)
    }

    @Test func positionAdvancesWhenDurationIsUnknown() {
        #expect(track(position: 12, duration: 0).position(at: t0 + 5) == 17)
    }

    @Test func identityNamesSourceTitleArtistAndAlbum() {
        #expect(track().identity == "com.apple.Music|T|Ar|Al")
        #expect(track().identity != track(album: "Other").identity)
    }
}

struct ArtworkHostAllowlistTests {
    private func allowed(_ string: String) -> Bool {
        NowPlayingController.isAllowedArtworkURL(URL(string: string)!)
    }

    @Test(arguments: [
        "https://i.ytimg.com/vi/x/hq.jpg", "https://YTIMG.com/x", "https://I.YTIMG.COM/x", "https://i.scdn.co/image/a",
        "https://is1-ssl.mzstatic.com/a.jpg", "https://lh3.googleusercontent.com/a", "https://f4.bcbits.com/img/a.jpg",
    ])
    func allowsKnownImageHostsAndTheirSubdomains(url: String) {
        #expect(allowed(url))
    }

    @Test(arguments: [
        "http://i.ytimg.com/x", "ftp://i.ytimg.com/a", "file:///etc/passwd", "https://evilytimg.com/x",
        "https://eviltimg.com/a", "https://ytimg.com.evil.com/x", "https://evil.example/ytimg.com",
        "https://localhost/x", "https://192.168.0.1/a.png", "https://[::1]/x", "https:///a",
    ])
    func rejectsOtherSchemesAndLookAlikeHosts(url: String) {
        #expect(!allowed(url))
    }
}

struct PlaybackMathTests {
    @Test func skipStaysWithinTheTrack() {
        #expect(NowPlayingController.skipTarget(position: 100, duration: 200, by: 30) == 130)
        #expect(NowPlayingController.skipTarget(position: 190, duration: 200, by: 30) == 199)
        #expect(NowPlayingController.skipTarget(position: 5, duration: 200, by: -30) == 0)
        #expect(NowPlayingController.skipTarget(position: 0.2, duration: 0.5, by: 10) == 0)
    }

    @Test(arguments: [(1.0, 1.25), (1.25, 1.5), (1.5, 2.0), (2.0, 1.0), (1.75, 2.0), (0.5, 1.0)])
    func speedCyclesThroughTheSteps(from rate: Double, to next: Double) {
        #expect(NowPlayingController.nextRate(after: rate) == next)
    }
}

struct ScriptSourceTests {
    @Test func buildsTransportCommands() {
        #expect(ScriptSource.music.command(.seek(-3)) == "tell application id \"com.apple.Music\" to set player position to 0.0")
        #expect(ScriptSource.music.command(.seek(12.5)) == "tell application id \"com.apple.Music\" to set player position to 12.5")
        #expect(ScriptSource.music.command(.playPause) == "tell application id \"com.apple.Music\" to playpause")
        #expect(ScriptSource.spotify.command(.next) == "tell application id \"com.spotify.client\" to next track")
        #expect(ScriptSource.spotify.command(.previous) == "tell application id \"com.spotify.client\" to previous track")
    }

    @Test func hasNoSpeedCommand() {
        #expect(ScriptSource.music.command(.rate(1.5)) == nil)
        #expect(ScriptSource.spotify.command(.rate(1.5)) == nil)
    }

    private func descriptor(_ state: String, duration: Double) -> NSAppleEventDescriptor {
        let list = NSAppleEventDescriptor.list()
        list.insert(NSAppleEventDescriptor(string: state), at: 1)
        list.insert(NSAppleEventDescriptor(string: "Song"), at: 2)
        list.insert(NSAppleEventDescriptor(string: "Artist"), at: 3)
        list.insert(NSAppleEventDescriptor(string: "Album"), at: 4)
        list.insert(NSAppleEventDescriptor(double: duration), at: 5)
        list.insert(NSAppleEventDescriptor(double: 31.5), at: 6)
        return list
    }

    @Test func spotifyReportsMillisecondsAsSeconds() throws {
        let spotify = try #require(NowPlayingController.parse(descriptor("playing", duration: 214_000), source: .spotify))
        #expect(spotify.duration == 214)
        #expect(spotify.position == 31.5)
        #expect(spotify.isPlaying)
        #expect(spotify.title == "Song" && spotify.artist == "Artist" && spotify.album == "Album")
        #expect(spotify.sourceBundleID == "com.spotify.client")
        let music = try #require(NowPlayingController.parse(descriptor("paused", duration: 214), source: .music))
        #expect(music.duration == 214)
        #expect(!music.isPlaying)
    }

    @Test func stoppedOrShortReplyHasNoTrack() {
        #expect(NowPlayingController.parse(descriptor("stopped", duration: 1), source: .music) == nil)
        let stopped = NSAppleEventDescriptor.list()
        stopped.insert(NSAppleEventDescriptor(string: "stopped"), at: 1)
        #expect(NowPlayingController.parse(stopped, source: .music) == nil)
    }
}
