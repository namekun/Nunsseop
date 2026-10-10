import AppKit

/// Compares the running version with the latest GitHub release.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    struct Release: Equatable {
        let version: String
    }

    @Published private(set) var available: Release?
    @Published private(set) var isChecking = false
    @Published private(set) var lastChecked: Date?
    @Published private(set) var failed = false

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    private let endpoint = URL(string: "https://api.github.com/repos/namekun/Nunsseop/releases/latest")!
    private var timer: Timer?

    func startAutomaticChecks(enabled: Bool) {
        timer?.invalidate()
        timer = nil
        guard enabled else { return }
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer?.tolerance = 60 * 60
    }

    func check() {
        guard !isChecking else { return }
        isChecking = true
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode
            // 404 means the repository has no releases yet.
            let release = status == 200 ? data.flatMap(Self.parse) : nil
            let ok = status == 404 || (status == 200 && release != nil)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isChecking = false
                self.lastChecked = Date()
                self.failed = !ok
                if let release, Self.isNewer(release.version, than: self.currentVersion) {
                    self.available = release
                } else if ok {
                    self.available = nil
                }
            }
        }.resume()
    }

    nonisolated private static func parse(_ data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              page.scheme == "https", page.host == "github.com",
              page.path.hasPrefix("/namekun/Nunsseop/") else { return nil }
        return Release(version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")))
    }

    /// The Terminal line that updates the app. One installed some other way is replaced by Homebrew's, since only
    /// Homebrew installs are offered now.
    nonisolated static func brewCommand(installedWithBrew: Bool) -> String {
        installedWithBrew ? "brew upgrade --cask nunsseop" : "brew install --cask --force namekun/tap/nunsseop"
    }

    /// Homebrew keeps a folder in its Caskroom for every cask it installed.
    nonisolated static var installedWithBrew: Bool {
        ["/opt/homebrew/Caskroom/nunsseop", "/usr/local/Caskroom/nunsseop"].contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// Homebrew itself, at the prefix of either kind of Mac. Without it there is no command to copy.
    nonisolated static var brewInstalled: Bool {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func copyUpdateCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.brewCommand(installedWithBrew: Self.installedWithBrew), forType: .string)
    }

    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
