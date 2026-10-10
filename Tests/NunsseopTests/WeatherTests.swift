import Foundation
import Testing
@testable import Nunsseop

struct WeatherParseTests {
    private func json(_ text: String) -> Data { Data(text.utf8) }

    @Test func readsTemperatureRangeAndCode() {
        let data = json("""
        {"current":{"temperature_2m":18.4,"weather_code":61},
         "daily":{"temperature_2m_max":[21.5],"temperature_2m_min":[12.0]}}
        """)
        #expect(WeatherModel.parse(forecast: data, name: "Seoul")
                == WeatherModel.Current(place: "Seoul", temperature: 18.4, high: 21.5, low: 12.0, code: 61))
    }

    @Test func aMissingRangeFallsBackToTheCurrentTemperature() {
        let data = json("""
        {"current":{"temperature_2m":7,"weather_code":3},"daily":{"temperature_2m_max":[],"temperature_2m_min":[]}}
        """)
        #expect(WeatherModel.parse(forecast: data, name: "Oslo")
                == WeatherModel.Current(place: "Oslo", temperature: 7, high: 7, low: 7, code: 3))
    }

    @Test func aMissingWeatherCodeMeansClearSky() {
        let data = json(#"{"current":{"temperature_2m":20.0},"daily":{}}"#)
        #expect(WeatherModel.parse(forecast: data, name: "Rome")?.code == 0)
    }

    @Test(arguments: [
        #"{"current":{"weather_code":1},"daily":{}}"#,
        #"{"daily":{}}"#,
        #"{"current":{"temperature_2m":20.0}}"#,
        #"{"error":true,"reason":"limit"}"#,
        "not json",
        "",
    ])
    func unusableResponsesGiveNothing(text: String) {
        #expect(WeatherModel.parse(forecast: json(text), name: "x") == nil)
    }
}

@MainActor
struct WeatherModelTests {
    private final class Lookups {
        var cities: [String] = []
    }

    private func model(_ lookups: Lookups) -> WeatherModel {
        WeatherModel(lookUp: { lookups.cities.append($0) })
    }

    private func current(_ place: String) -> WeatherModel.Current {
        WeatherModel.Current(place: place, temperature: 20, high: 24, low: 15, code: 0)
    }

    @Test func settingACityLooksItUpOnceWithoutSurroundingSpaces() {
        let lookups = Lookups()
        let weather = model(lookups)
        weather.setCity("  Seoul ")
        weather.setCity("Seoul")
        #expect(lookups.cities == ["Seoul"])
        weather.setCity("")
    }

    @Test func clearingTheCityLooksNothingUp() {
        let lookups = Lookups()
        let weather = model(lookups)
        weather.setCity("")
        weather.setCity("   ")
        #expect(lookups.cities.isEmpty)
    }

    @Test func anAnswerForTheCurrentCityIsShown() {
        let weather = model(Lookups())
        weather.setCity("Seoul")
        weather.receive(current("Seoul"), for: "Seoul")
        #expect(weather.current == current("Seoul"))
        #expect(!weather.failed)
        weather.setCity("")
    }

    @Test func anAnswerArrivingAfterTheChipWasTurnedOffIsDropped() {
        let weather = model(Lookups())
        weather.setCity("Seoul")
        weather.setCity("")
        weather.receive(current("Seoul"), for: "Seoul")
        #expect(weather.current == nil)
        #expect(!weather.failed)
    }

    @Test func aLateAnswerForAnEarlierCityDoesNotReplaceTheNewOne() {
        let weather = model(Lookups())
        weather.setCity("Seoul")
        weather.setCity("Tokyo")
        weather.receive(current("Tokyo"), for: "Tokyo")
        weather.receive(current("Seoul"), for: "Seoul")
        weather.receive(nil, for: "Seoul")
        #expect(weather.current == current("Tokyo"))
        #expect(!weather.failed)
        weather.setCity("")
    }

    @Test func aFailureForTheCurrentCityIsFlaggedAndClearedByTheNextAnswer() {
        let weather = model(Lookups())
        weather.setCity("Seoul")
        weather.receive(nil, for: "Seoul")
        #expect(weather.failed)
        #expect(weather.current == nil)
        weather.receive(current("Seoul"), for: "Seoul")
        #expect(!weather.failed)
        #expect(weather.current == current("Seoul"))
        weather.setCity("")
    }

    @Test func changingTheCityClearsTheOldReading() {
        let weather = model(Lookups())
        weather.setCity("Seoul")
        weather.receive(current("Seoul"), for: "Seoul")
        weather.setCity("Tokyo")
        #expect(weather.current == nil)
        weather.setCity("")
    }

    @Test(arguments: [
        (0, "sun.max.fill"), (1, "cloud.sun.fill"), (2, "cloud.sun.fill"), (3, "cloud.fill"),
        (45, "cloud.fog.fill"), (48, "cloud.fog.fill"), (51, "cloud.drizzle.fill"), (55, "cloud.drizzle.fill"),
        (56, "cloud.drizzle.fill"), (57, "cloud.drizzle.fill"), (61, "cloud.rain.fill"), (67, "cloud.rain.fill"),
        (80, "cloud.rain.fill"), (81, "cloud.rain.fill"), (82, "cloud.rain.fill"), (71, "cloud.snow.fill"),
        (77, "cloud.snow.fill"), (85, "cloud.snow.fill"), (86, "cloud.snow.fill"), (95, "cloud.bolt.rain.fill"),
        (99, "cloud.bolt.rain.fill"), (1234, "cloud.fill"), (-1, "cloud.fill"), (68, "cloud.fill"),
    ])
    func symbolForAWeatherCode(code: Int, symbol: String) {
        #expect(WeatherModel.symbol(for: code) == symbol)
    }
}
