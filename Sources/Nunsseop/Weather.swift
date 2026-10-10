import CoreLocation
import Foundation
import os

/// Current conditions for a city from Open-Meteo (open-meteo.com), which needs no API key.
@MainActor
final class WeatherModel: ObservableObject {
    struct Current: Equatable {
        let place: String
        let temperature: Double
        let high: Double
        let low: Double
        let code: Int
    }

    @Published private(set) var current: Current?
    @Published private(set) var failed = false

    private var city = ""
    private var timer: Timer?
    private let useFahrenheit = Locale.current.measurementSystem == .us
    /// Stands in for the network lookup.
    private let lookUp: ((String) -> Void)?

    init(lookUp: ((String) -> Void)? = nil) {
        self.lookUp = lookUp
    }

    nonisolated private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration)
    }()

    func setCity(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != city else { return }
        city = trimmed
        timer?.invalidate()
        current = nil
        failed = false
        guard !trimmed.isEmpty else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = 3 * 60
    }

    private func refresh() {
        let city = city
        if let lookUp { lookUp(city); return }
        var geo = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        geo.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "1"),
                          URLQueryItem(name: "language", value: Locale.current.language.languageCode?.identifier ?? "en")]
        let fahrenheit = useFahrenheit
        Self.session.dataTask(with: geo.url!) { [weak self] data, _, _ in
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let place = (json["results"] as? [[String: Any]])?.first,
                  let lat = place["latitude"] as? Double, let lon = place["longitude"] as? Double else {
                // Open-Meteo misses short non-Latin names such as "서울" or "東京"; Apple's geocoder finds them.
                DispatchQueue.main.async { self?.geocodeWithApple(city, fahrenheit: fahrenheit) }
                return
            }
            guard let self else { return }
            Self.fetchForecast(latitude: lat, longitude: lon, name: place["name"] as? String ?? city,
                               fahrenheit: fahrenheit, city: city, into: self)
        }.resume()
    }

    private func geocodeWithApple(_ city: String, fahrenheit: Bool) {
        CLGeocoder().geocodeAddressString(city) { [weak self] placemarks, _ in
            MainActor.assumeIsolated {
                guard let self, city == self.city else { return }
                guard let placemark = placemarks?.first, let coordinate = placemark.location?.coordinate else {
                    self.failed = true
                    return
                }
                Self.fetchForecast(latitude: coordinate.latitude, longitude: coordinate.longitude,
                                   name: placemark.locality ?? placemark.name ?? city, fahrenheit: fahrenheit,
                                   city: city, into: self)
            }
        }
    }

    nonisolated private static func fetchForecast(latitude lat: Double, longitude lon: Double, name: String,
                                                  fahrenheit: Bool, city: String, into model: WeatherModel) {
        var forecast = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        forecast.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)), URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "1"), URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
        ]
        session.dataTask(with: forecast.url!) { [weak model] data, _, _ in
            let result = data.flatMap { parse(forecast: $0, name: name) }
            DispatchQueue.main.async { model?.receive(result, for: city) }
        }.resume()
    }

    /// Whether `city` is still the one asked for: an answer for an earlier city, or one that arrives
    /// after the chip was turned off, is dropped.
    func receive(_ result: Current?, for city: String) {
        guard city == self.city else { return }
        current = result
        failed = result == nil
    }

    nonisolated static func parse(forecast data: Data, name: String) -> Current? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let now = json["current"] as? [String: Any], let daily = json["daily"] as? [String: Any],
              let temperature = now["temperature_2m"] as? Double else { return nil }
        return Current(place: name, temperature: temperature,
                       high: (daily["temperature_2m_max"] as? [Double])?.first ?? temperature,
                       low: (daily["temperature_2m_min"] as? [Double])?.first ?? temperature,
                       code: now["weather_code"] as? Int ?? 0)
    }

    /// SF Symbol for a WMO weather code.
    static func symbol(for code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

/// Announces downloads in ~/Downloads as they start and finish, and follows how far along they are.
@MainActor
final class DownloadWatcher: ObservableObject {
    /// The downloads in progress together: how far along in whole percent, nil while none knows its size yet.
    struct Status: Equatable {
        var percent: Int?
    }

    var onStart: ((String) -> Void)?
    var onFinish: ((URL) -> Void)?
    /// What's downloading now, from the progress Safari and Chrome publish for the Finder's file icons; nil when nothing is.
    /// Other apps' downloads still start and finish as before, they just don't show progress.
    @Published private(set) var status: Status?

    private var source: DispatchSourceFileSystemObject?
    private var inProgress: [String: URL] = [:]
    private static let partialExtensions: Set<String> = ["crdownload", "download", "part", "partial", "opdownload"]
    private var subscriber: Any?
    private var downloads: [ObjectIdentifier: Progress] = [:]
    private var observations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    /// Any process may publish progress for a file here, so how much it can make Nunsseop do is bounded:
    /// this many downloads followed at once, and reports gathered into at most ten updates a second.
    private static let maxFollowed = 32
    private let updateQueued = OSAllocatedUnfairLock(initialState: false)

    func start(in directory: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]) {
        follow(directory)
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scan(directory) }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
        inProgress = Self.partials(in: directory)
    }

    /// Subscribes to the file progress published for the folder's files: the same reports the Finder draws its bars from,
    /// so nothing polls. Copies into the folder publish too and are left out.
    private func follow(_ directory: URL) {
        guard subscriber == nil else { return }
        subscriber = Progress.addSubscriber(forFileURL: directory) { [weak self] progress in
            let kind = progress.userInfo[.fileOperationKindKey] as? String ?? progress.fileOperationKind?.rawValue
            guard kind == Progress.FileOperationKind.downloading.rawValue else { return nil }
            let id = ObjectIdentifier(progress)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.add(progress, id: id) }
            }
            return {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.remove(id) }
                }
            }
        }
    }

    private func add(_ progress: Progress, id: ObjectIdentifier) {
        guard downloads.count < Self.maxFollowed else { return }
        downloads[id] = progress
        // Reports arrive many times a second, on any thread; one update a tenth of a second covers them all.
        observations[id] = progress.observe(\.fractionCompleted) { [weak self, updateQueued] _, _ in
            let first = updateQueued.withLock { queued in
                defer { queued = true }
                return !queued
            }
            guard first else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                updateQueued.withLock { $0 = false }
                MainActor.assumeIsolated { self?.update() }
            }
        }
        update()
    }

    private func remove(_ id: ObjectIdentifier) {
        downloads[id] = nil
        observations[id] = nil
        update()
    }

    private func update() {
        let new = Self.status(of: downloads.values.map { (completed: $0.completedUnitCount, total: $0.totalUnitCount) })
        if new != status { status = new }
    }

    /// Bytes done over bytes in all, counting only downloads that know their size. Rounded down, so 100% means done.
    /// Summed as Double: reported sizes come from other processes, and Int64 sums of them could overflow.
    nonisolated static func status(of downloads: [(completed: Int64, total: Int64)]) -> Status? {
        guard !downloads.isEmpty else { return nil }
        let sized = downloads.filter { $0.total > 0 }
        let total = sized.reduce(0.0) { $0 + Double($1.total) }
        let done = sized.reduce(0.0) { $0 + Double(min(max($1.completed, 0), $1.total)) }
        let percent = total > 0 ? Int(min(done / total, 1) * 100) : nil
        return Status(percent: percent)
    }

    private static func partials(in directory: URL) -> [String: URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                                  options: [.skipsHiddenFiles])) ?? []
        var result: [String: URL] = [:]
        for url in files where partialExtensions.contains(url.pathExtension.lowercased()) {
            result[url.lastPathComponent] = url
        }
        return result
    }

    private func scan(_ directory: URL) {
        let now = Self.partials(in: directory)
        for (name, url) in now where inProgress[name] == nil {
            onStart?(url.deletingPathExtension().lastPathComponent)
        }
        for (name, url) in inProgress where now[name] == nil {
            let finished = url.deletingPathExtension()
            if FileManager.default.fileExists(atPath: finished.path) { onFinish?(finished) }
        }
        inProgress = now
    }
}
