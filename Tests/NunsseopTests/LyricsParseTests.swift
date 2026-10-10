import Testing
@testable import Nunsseop

struct LyricsParseTests {
    @Test func parsesAndSortsTimedLines() {
        let lrc = """
        [ar:Some Artist]
        [00:01.50] Hello
        [00:00.00]Start
        [01:00.00][02:00.00] Chorus
        no timestamp here
        [00:05.00]
        """
        #expect(LyricsModel.parse(lrc) == [
            .init(time: 0, text: "Start"),
            .init(time: 1.5, text: "Hello"),
            .init(time: 5, text: ""),
            .init(time: 60, text: "Chorus"),
            .init(time: 120, text: "Chorus"),
        ])
    }

    @Test func emptyInputHasNoLines() {
        #expect(LyricsModel.parse("").isEmpty)
        #expect(LyricsModel.parse("plain text\nwithout times").isEmpty)
    }

    @Test func parsesCRLFLineEndings() {
        #expect(LyricsModel.parse("[00:01.00]A\r\n[00:02.00]B\r\n") == [
            .init(time: 1, text: "A"),
            .init(time: 2, text: "B"),
        ])
    }

    @Test func parsesTimestampForms() {
        #expect(LyricsModel.parse("[00:05]x") == [.init(time: 5, text: "x")])
        let fraction = LyricsModel.parse("[01:02.345]x")
        #expect(fraction.count == 1)
        #expect(abs(fraction[0].time - 62.345) < 0.0005)
        #expect(LyricsModel.parse("[1:02:03]x").isEmpty)
        #expect(LyricsModel.parse("[offset:+500]\n[00:01.00]x") == [.init(time: 1, text: "x")])
    }
}

@MainActor
struct LyricsLineSelectionTests {
    private let model = LyricsModel(lines: [
        .init(time: 0, text: "A"), .init(time: 10, text: ""), .init(time: 20, text: "B"),
    ])

    @Test func picksTheLineBeingSung() {
        #expect(model.line(at: -1) == nil)
        #expect(model.line(at: 0) == "A")
        #expect(model.line(at: 9.74) == "A")
        #expect(model.line(at: 19.8) == "B")
        #expect(model.line(at: 1000) == "B")
    }

    @Test func blankLineShowsNothing() {
        #expect(model.line(at: 9.8) == nil)
        #expect(model.line(at: 15) == nil)
    }

    @Test func noLyricsShowNothing() {
        #expect(LyricsModel().line(at: 5) == nil)
    }
}
