import Foundation

/// Time-synced lyrics from LRCLIB (lrclib.net), a free and open lyrics database.
@MainActor
final class LyricsModel: ObservableObject {
    struct Line: Equatable {
        let time: TimeInterval
        let text: String
    }

    @Published private(set) var lines: [Line]
    var isEnabled = true

    init(lines: [Line] = []) {
        self.lines = lines
    }

    private var identity: String?
    private var cache: [String: [Line]] = [:]
    private var task: URLSessionDataTask?

    nonisolated private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.httpAdditionalHeaders = ["User-Agent": "Nunsseop (https://github.com/namekun/Nunsseop)"]
        return URLSession(configuration: configuration)
    }()

    func update(for track: NowPlayingTrack?) {
        guard isEnabled, let track, !track.title.isEmpty, !track.artist.isEmpty else {
            identity = nil
            lines = []
            return
        }
        guard track.identity != identity else { return }
        identity = track.identity
        if let cached = cache[track.identity] {
            lines = cached
            return
        }
        lines = []
        task?.cancel()
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(Int(track.duration.rounded()))),
        ]
        guard let url = components.url else { return }
        let key = track.identity
        task = Self.session.dataTask(with: url) { [weak self] data, response, _ in
            guard (response as? HTTPURLResponse)?.statusCode == 200, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let synced = json["syncedLyrics"] as? String else { return }
            let parsed = Self.parse(synced)
            DispatchQueue.main.async {
                guard let self else { return }
                self.cache[key] = parsed
                if self.identity == key { self.lines = parsed }
            }
        }
        task?.resume()
    }

    /// The line being sung at `position`, if any.
    func line(at position: TimeInterval) -> String? {
        guard let index = lines.lastIndex(where: { $0.time <= position + 0.25 }) else { return nil }
        let text = lines[index].text
        return text.isEmpty ? nil : text
    }

    /// Parses LRC lines such as `[01:23.45] text`.
    nonisolated static func parse(_ lrc: String) -> [Line] {
        var result: [Line] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            var rest = Substring(raw)
            var times: [TimeInterval] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let stamp = rest[rest.index(after: rest.startIndex)..<close]
                let parts = stamp.split(separator: ":")
                if parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) {
                    times.append(minutes * 60 + seconds)
                }
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            result += times.map { Line(time: $0, text: text) }
        }
        return result.sorted { $0.time < $1.time }
    }
}
