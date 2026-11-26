import Foundation
import Testing
@testable import Nunsseop

struct WorldClockTextTests {
    @Test func citiesAreSplitTrimmedAndWithoutRepeats() {
        #expect(WorldClockModel.cities(in: " New York ,London,, new york\n서울") == ["New York", "London", "서울"])
    }

    @Test func onlyAsManyCitiesAsFitAreKept() {
        #expect(WorldClockModel.cities(in: "a, b, c, d, e") == ["a", "b", "c"])
    }

    @Test func nothingTypedMeansNoCities() {
        #expect(WorldClockModel.cities(in: "").isEmpty)
        #expect(WorldClockModel.cities(in: " , ,").isEmpty)
    }

    @Test(arguments: [("Seoul", "Asia/Seoul"), ("new york", "America/New_York"), ("Asia/Tokyo", "Asia/Tokyo"),
                      ("SAO PAULO", "America/Sao_Paulo")])
    func aCityIsFoundAmongTheSystemTimeZones(name: String, identifier: String) {
        #expect(WorldClockModel.localZone(for: name)?.identifier == identifier)
    }

    @Test func aNameNoTimeZoneHasIsNotFoundLocally() {
        #expect(WorldClockModel.localZone(for: "Atlantis") == nil)
    }

    @Test func geocodingGivesTheTimeZoneOfTheFirstResult() {
        let data = Data(#"{"results":[{"name":"Pune","timezone":"Asia/Kolkata"},{"timezone":"UTC"}]}"#.utf8)
        #expect(WorldClockModel.parse(geocoding: data)?.identifier == "Asia/Kolkata")
    }

    @Test(arguments: [#"{"results":[{"name":"x"}]}"#, #"{"results":[{"timezone":"Not/AZone"}]}"#, #"{}"#, "not json", ""])
    func aGeocodingAnswerWithoutAUsableTimeZoneGivesNothing(text: String) {
        #expect(WorldClockModel.parse(geocoding: Data(text.utf8)) == nil)
    }
}

struct WorldClockTimeTests {
    // 2026-01-15 12:00 UTC, winter in the northern hemisphere.
    private let winter = Date(timeIntervalSince1970: 1_768_478_400)
    private let utc = TimeZone(identifier: "UTC")!

    @Test(arguments: [("Asia/Seoul", "+9h"), ("America/New_York", "-5h"), ("Asia/Kolkata", "+5h30m"),
                      ("UTC", "0h"), ("America/St_Johns", "-3h30m")])
    func theOffsetFromHere(identifier: String, label: String) {
        #expect(WorldClockModel.offset(of: TimeZone(identifier: identifier)!, from: utc, at: winter) == label)
    }

    @Test func theOffsetFollowsDaylightSavingTime() {
        let summer = Date(timeIntervalSince1970: 1_784_116_800) // 2026-07-15 12:00 UTC
        #expect(WorldClockModel.offset(of: TimeZone(identifier: "America/New_York")!, from: utc, at: summer) == "-4h")
    }

    @Test func theTimeIsTheOneInThatZone() {
        let text = WorldClockModel.time(in: TimeZone(identifier: "Asia/Seoul")!, at: winter, locale: Locale(identifier: "en_GB"))
        #expect(text == "21:00")
    }
}

@MainActor
struct WorldClockModelTests {
    private final class Lookups {
        var names: [String] = []
    }

    private func model(_ lookups: Lookups) -> WorldClockModel {
        WorldClockModel(lookUp: { lookups.names.append($0) })
    }

    @Test func aKnownCityShowsAtOnceWithoutAnyLookup() {
        let lookups = Lookups()
        let clock = model(lookups)
        clock.setCities("Seoul, Tokyo")
        #expect(clock.clocks.map(\.name) == ["Seoul", "Tokyo"])
        #expect(clock.clocks.map(\.timeZone.identifier) == ["Asia/Seoul", "Asia/Tokyo"])
        #expect(lookups.names.isEmpty)
    }

    @Test func anUnknownCityIsLookedUpOnceAndShownWhenFound() {
        let lookups = Lookups()
        let clock = model(lookups)
        clock.setCities("Seoul, Pune")
        clock.setCities("Seoul, Pune")
        #expect(lookups.names == ["Pune"])
        #expect(clock.clocks.map(\.name) == ["Seoul"])
        clock.receive(TimeZone(identifier: "Asia/Kolkata"), for: "Pune")
        #expect(clock.clocks.map(\.name) == ["Seoul", "Pune"])
    }

    @Test func aCityNotFoundIsLeftOut() {
        let clock = model(Lookups())
        clock.setCities("Pune")
        clock.receive(nil, for: "Pune")
        #expect(clock.clocks.isEmpty)
    }

    @Test func clearingTheCitiesStopsEverythingAndDropsLateAnswers() {
        let lookups = Lookups()
        let clock = model(lookups)
        clock.setCities("Pune, Seoul")
        clock.setCities("")
        clock.receive(TimeZone(identifier: "Asia/Kolkata"), for: "Pune")
        #expect(clock.clocks.isEmpty)
        #expect(lookups.names == ["Pune"])
    }
}

struct WorldClockTranslationTests {
    @Test(arguments: ["de", "es", "fr", "ja", "ko", "zh-Hans"])
    func everySentenceIsTranslated(language: String) throws {
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources")
        let table = try #require(NSDictionary(contentsOfFile: resources.appendingPathComponent("\(language).lproj/Localizable.strings").path) as? [String: String])
        for key in ["World clock", "Cities for the world clock (e.g. New York, London)",
                    "Shows up to three cities' time on Home, and how far it is from here. Cities the Mac doesn't know are looked up on Open-Meteo. Leave it empty to hide it."] {
            let text = table[key] ?? ""
            #expect(!text.isEmpty && text != key, Comment(rawValue: "\(language): \(key)"))
        }
    }
}
