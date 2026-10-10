import Foundation
import Testing
@testable import Nunsseop

struct BrowserMediaSiteTests {
    @Test(arguments: [
        "https://music.youtube.com/watch?v=1", "https://www.youtube.com/watch", "https://YOUTUBE.com/x",
        "https://OPEN.SPOTIFY.COM/track/1", "https://artist.bandcamp.com/album/x", "https://music.amazon.com/x",
    ])
    func probesMediaSites(url: String) {
        #expect(BrowserMedia.isMediaSite(url))
    }

    @Test(arguments: [
        "http://youtube.com", "https://notyoutube.com", "https://notyoutube.com/", "https://youtube.com.evil.com/",
        "https://evil.com/?q=youtube.com", "https://evil.example/youtube.com", "file:///youtube.com",
        "https://music.amazon/x", "not a url", "",
    ])
    func skipsEverythingElse(url: String) {
        #expect(!BrowserMedia.isMediaSite(url))
    }
}

struct BrowserMediaScriptTests {
    private let chrome = BrowserMedia(bundleID: "com.google.Chrome", dialect: .chromium)
    private let safari = BrowserMedia(bundleID: "com.apple.Safari", dialect: .safari)
    private let location = BrowserMedia.Location(window: 2, tab: 3, url: "https://a/b")

    @Test func escapesQuotesAndBackslashes() {
        #expect(BrowserMedia.appleScriptLiteral(#"a"b\c"#) == #""a\"b\\c""#)
        #expect(BrowserMedia.appleScriptLiteral("") == "\"\"")
        #expect(BrowserMedia.appleScriptLiteral(#"https://x.com/\"#) == #""https://x.com/\\""#)
    }

    @Test func hostileUrlStaysInsideItsLiteral() {
        let literal = BrowserMedia.appleScriptLiteral(#"https://x.com/"& (do shell script "id") &""#)
        #expect(literal.hasPrefix("\"") && literal.hasSuffix("\""))
        let inner = Array(literal.dropFirst().dropLast())
        var index = 0
        while index < inner.count {
            if inner[index] == "\\" {
                index += 2
                continue
            }
            #expect(inner[index] != "\"", "unescaped quote at \(index)")
            index += 1
        }
    }

    @Test func guardedScriptChecksTheTabBeforeRunning() {
        let script = chrome.guardedScript("js()", at: location)
        #expect(script.contains("if (count of windows) < 2 then return \"\""))
        #expect(script.contains("if (count of tabs of window 2) < 3 then return \"\""))
        #expect(script.contains("if URL of tab 3 of window 2 is not \"https://a/b\" then return \"\""))
        #expect(script.contains("tell application id \"com.google.Chrome\""))
    }

    @Test func dialectsRunTheScriptInTheirOwnWay() {
        #expect(chrome.guardedScript("js()", at: location).contains("return execute tab 3 of window 2 javascript \"js()\""))
        #expect(safari.guardedScript("js()", at: location).contains("return do JavaScript \"js()\" in tab 3 of window 2"))
    }

    @Test func commandScriptsCarryTheirValues() {
        #expect(BrowserMedia.commandJS(.seek(-5)).contains("currentTime = 0.0"))
        #expect(BrowserMedia.commandJS(.seek(42.5)).contains("currentTime = 42.5"))
        #expect(BrowserMedia.commandJS(.rate(1.25)).contains("playbackRate = 1.25"))
        #expect(BrowserMedia.commandJS(.playPause).contains("ytmusic-player-bar #play-pause-button"))
        #expect(BrowserMedia.commandJS(.next).contains("ytmusic-player-bar .next-button"))
        #expect(BrowserMedia.commandJS(.previous).contains("ytmusic-player-bar .previous-button"))
    }

    @Test func classifiesScriptErrors() {
        #expect(BrowserMedia.failure(code: -1743, message: "x") == .notAuthorized)
        #expect(BrowserMedia.failure(code: 0, message: "Executing JavaScript through AppleScript is turned off") == .javaScriptDisabled)
        #expect(BrowserMedia.failure(code: 0, message: "Invalid index") == .other)
        #expect(BrowserMedia.failure(code: -1743, message: "javascript") == .notAuthorized)
    }
}

struct BrowserMediaHitTests {
    private let chrome = BrowserMedia(bundleID: "com.google.Chrome", dialect: .chromium)
    private let location = BrowserMedia.Location(window: 1, tab: 4, url: "https://music.youtube.com/watch")

    @Test func readsAPlayingMediaElement() throws {
        let json = #"{"title":"S","artist":"A","album":"B","art":"https://i.ytimg.com/a.jpg","playing":true,"pos":12.5,"dur":200,"rate":1.5,"el":true}"#
        let hit = try #require(chrome.makeHit(json, location: location))
        #expect(hit.track.title == "S" && hit.track.artist == "A" && hit.track.album == "B")
        #expect(hit.track.isPlaying)
        #expect(hit.track.position == 12.5)
        #expect(hit.track.duration == 200)
        #expect(hit.track.rate == 1.5)
        #expect(hit.track.canSeek && hit.track.canChangeRate)
        #expect(hit.track.sourceBundleID == "com.google.Chrome")
        #expect(hit.artworkURL == URL(string: "https://i.ytimg.com/a.jpg"))
        #expect(hit.location == location)
    }

    @Test func mediaSessionOnlyPageCannotSeekOrChangeSpeed() throws {
        let hit = try #require(chrome.makeHit(#"{"title":"S","el":false}"#, location: location))
        #expect(hit.track.duration == 0)
        #expect(hit.track.rate == 1)
        #expect(!hit.track.canSeek && !hit.track.canChangeRate)
        #expect(hit.track.artist == "")
        #expect(!hit.track.isPlaying)
    }

    @Test func integerDurationBecomesDouble() throws {
        let hit = try #require(chrome.makeHit(#"{"title":"S","dur":0,"pos":3,"el":true}"#, location: location))
        #expect(hit.track.duration == 0)
        #expect(hit.track.position == 3)
    }

    @Test func unreadableStateHasNoHit() {
        #expect(chrome.makeHit("", location: location) == nil)
        #expect(chrome.makeHit("not json", location: location) == nil)
        #expect(chrome.makeHit(nil, location: location) == nil)
        #expect(chrome.makeHit("[1]", location: location) == nil)
    }

    @Test func emptyArtworkHasNoUrl() throws {
        let hit = try #require(chrome.makeHit(#"{"title":"S","art":""}"#, location: location))
        #expect(hit.artworkURL == nil)
    }
}
