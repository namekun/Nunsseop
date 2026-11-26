import CoreLocation
import Foundation
import SwiftUI

/// The time in a few cities and how far it is from here. A city is found among the system's time zones first, which needs no
/// network, and otherwise by the same lookups the weather uses. Nothing runs while no city is set.
@MainActor
final class WorldClockModel: ObservableObject {
    struct Clock: Equatable, Identifiable {
        let name: String
        let timeZone: TimeZone
        var id: String { name }
    }

    /// How many cities fit in the column.
    nonisolated static let limit = 3

    @Published private(set) var clocks: [Clock] = []

    private var names: [String] = []
    private var found: [String: TimeZone] = [:]
    /// Stands in for the network lookup.
    private let lookUp: ((String) -> Void)?

    init(lookUp: ((String) -> Void)? = nil) {
        self.lookUp = lookUp
    }

    func setCities(_ text: String) {
        let wanted = Self.cities(in: text)
        guard wanted != names else { return }
        names = wanted
        found = found.filter { wanted.contains($0.key) }
        for name in wanted where found[name] == nil {
            if let zone = Self.localZone(for: name) { found[name] = zone } else { search(name) }
        }
        publish()
    }

    /// An answer for a city that is still wanted; one for a city dropped since is ignored.
    func receive(_ zone: TimeZone?, for name: String) {
        guard names.contains(name), let zone else { return }
        found[name] = zone
        publish()
    }

    private func publish() {
        let next = names.compactMap { name in found[name].map { Clock(name: name, timeZone: $0) } }
        if next != clocks { clocks = next }
    }

    private func search(_ name: String) {
        if let lookUp { lookUp(name); return }
        var geo = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        geo.queryItems = [URLQueryItem(name: "name", value: name), URLQueryItem(name: "count", value: "1"),
                          URLQueryItem(name: "language", value: Locale.current.language.languageCode?.identifier ?? "en")]
        URLSession.shared.dataTask(with: geo.url!) { [weak self] data, _, _ in
            if let zone = data.flatMap(Self.parse(geocoding:)) {
                DispatchQueue.main.async { self?.receive(zone, for: name) }
            } else {
                // Open-Meteo misses short non-Latin names; Apple's geocoder finds them.
                DispatchQueue.main.async { self?.searchWithApple(name) }
            }
        }.resume()
    }

    private func searchWithApple(_ name: String) {
        CLGeocoder().geocodeAddressString(name) { [weak self] placemarks, _ in
            MainActor.assumeIsolated { self?.receive(placemarks?.first?.timeZone, for: name) }
        }
    }

    nonisolated static func parse(geocoding data: Data) -> TimeZone? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let place = (json["results"] as? [[String: Any]])?.first,
              let identifier = place["timezone"] as? String else { return nil }
        return TimeZone(identifier: identifier)
    }

    /// The cities in what was typed: separated by commas, without repeats, as many as fit.
    nonisolated static func cities(in text: String) -> [String] {
        var seen = Set<String>()
        let names = text.split(whereSeparator: { ",，、;\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        return Array(names.prefix(limit))
    }

    /// The system time zone named by `name`, either as its identifier ("Asia/Seoul") or by its city ("Seoul", "new york").
    nonisolated static func localZone(for name: String) -> TimeZone? {
        func key(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .replacingOccurrences(of: "_", with: " ")
        }
        let wanted = key(name)
        let identifiers = TimeZone.knownTimeZoneIdentifiers
        let identifier = identifiers.first { key($0) == wanted }
            ?? identifiers.first { key(String($0.split(separator: "/").last ?? "")) == wanted }
        return identifier.flatMap { TimeZone(identifier: $0) }
    }

    /// How far `zone` is ahead of (+) or behind (-) `local` at `date`: "+9h", "-5h", "+5h30m", "0h".
    nonisolated static func offset(of zone: TimeZone, from local: TimeZone = .current, at date: Date) -> String {
        let minutes = (zone.secondsFromGMT(for: date) - local.secondsFromGMT(for: date)) / 60
        if minutes == 0 { return "0h" }
        let (hours, rest) = (abs(minutes) / 60, abs(minutes) % 60)
        return (minutes < 0 ? "-" : "+") + "\(hours)h" + (rest == 0 ? "" : "\(rest)m")
    }

    nonisolated static func time(in zone: TimeZone, at date: Date, locale: Locale = .current) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: zone))
    }
}

/// Each city with the time there and its offset from here; nothing until a city is found.
struct WorldClockRow: View {
    @ObservedObject var worldClock: WorldClockModel

    var body: some View {
        if !worldClock.clocks.isEmpty {
            VStack(spacing: 0) {
                PanelHLine()
                TimelineView(.everyMinute) { context in
                    VStack(spacing: 0) {
                        ForEach(worldClock.clocks) { clock in
                            HStack(spacing: 8) {
                                Image(systemName: "clock").symbolRenderingMode(.monochrome)
                                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.8)).frame(width: 16).accessibilityHidden(true)
                                Text.panel(clock.name, size: 12, weight: .semibold).lineLimit(1)
                                Text.panel(WorldClockModel.offset(of: clock.timeZone, at: context.date), size: 11, opacity: 0.6, mono: true)
                                    .lineLimit(1).fixedSize()
                                Spacer(minLength: 4)
                                Text.panel(WorldClockModel.time(in: clock.timeZone, at: context.date), size: 13, weight: .semibold, mono: true).fixedSize()
                            }
                            .padding(.horizontal, 8).frame(height: 22)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }
}
